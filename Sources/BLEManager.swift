import Foundation
import CoreBluetooth

// 蚂蚁保护板 (ANT BMS) BLE 管理器 —— 纯读取，不发送任何写参数命令
// 协议来源: https://github.com/yosle/ant-bms-ble (MIT, 开源规范)
final class BLEManager: NSObject, ObservableObject {
    @Published var status: String = "未连接"
    @Published var deviceName: String = ""
    @Published var packVoltage: Double = 0      // V
    @Published var current: Double = 0          // A (负=充电)
    @Published var power: Double = 0            // W (显示用 V*I)
    @Published var soc: Int = 0                 // %
    @Published var cellVoltages: [Double] = []  // 每串电压 V
    @Published var temperatures: [Double] = []  // 温度 ℃
    @Published var mosTemp: Double = 0          // 功率管温度 ℃
    @Published var cellCount: Int = 0
    @Published var lastUpdate: Date? = nil

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txChar: CBCharacteristic?
    private var rxBuf = Data()
    private var timer: Timer?

    static let svcUUID = CBUUID(string: "FFE0")
    static let chrUUID = CBUUID(string: "FFE1")

    // 0x01 实时数据请求帧（CRC 已计算好的恒定帧，每 500ms 发一次）
    static let requestFrame: [UInt8] = [0x7E, 0xA1, 0x01, 0x00, 0x00, 0xBE, 0x18, 0x55, 0xAA, 0x55]

    func start() {
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func rescan() {
        stopTimer()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        rxBuf = Data()
        status = "重新搜索中…"
        central?.scanForPeripherals(withServices: [Self.svcUUID], options: nil)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 中央代理
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "搜索 ANT-BLE 设备中…"
            central.scanForPeripherals(withServices: [Self.svcUUID], options: nil)
        case .poweredOff:
            status = "蓝牙已关闭，请打开蓝牙"
        case .unauthorized:
            status = "没有蓝牙权限（设置→隐私→蓝牙）"
        default:
            status = "蓝牙不可用"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "ANT-BLE"
        if self.peripheral == nil {
            central.stopScan()
            self.peripheral = peripheral
            self.deviceName = name
            status = "已找到 \(name)，连接中…"
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "已连接，读取服务…"
        peripheral.delegate = self
        peripheral.discoverServices([Self.svcUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stopTimer()
        status = "连接断开，正在重连…"
        central.scanForPeripherals(withServices: [Self.svcUUID], options: nil)
    }

    // MARK: - 外设代理
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == Self.svcUUID }) else {
            status = "未找到 FFE0 服务"
            return
        }
        peripheral.discoverCharacteristics([Self.chrUUID], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chr = service.characteristics?.first(where: { $0.uuid == Self.chrUUID }) else {
            status = "未找到 FFE1 特征"
            return
        }
        txChar = chr
        peripheral.setNotifyValue(true, for: chr)
        status = "已连接，等待数据…"
        // 每 500ms 请求一次实时数据
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.requestData()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func requestData() {
        guard let p = peripheral, let c = txChar else { return }
        p.writeValue(Data(Self.requestFrame), for: c, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        rxBuf.append(data)
        parseBuffer()
    }

    // MARK: - 帧解析（新协议 7E A1 … AA 55）
    private func parseBuffer() {
        while let header = rxBuf.findHeader() {
            // 至少要有 10 字节固定部分（7E A1 cmd addr_lo addr_hi len crc_hi crc_lo）
            let headerIdx = header.offset
            if rxBuf.count - headerIdx < 10 { break }
            let len = Int(rxBuf[headerIdx + 5])
            let total = 10 + len
            if rxBuf.count - headerIdx < total { break }
            let frame = rxBuf.subdata(in: headerIdx..<(headerIdx + total))
            rxBuf.removeSubrange(0..<(headerIdx + total))
            handleFrame(frame)
        }
        if rxBuf.count > 2048 { rxBuf = Data() } // 防呆
    }

    private func handleFrame(_ f: Data) {
        let cmd = f[2]
        guard cmd == 0x11 else { return } // 只关心实时数据
        guard f.count > 40 else { return }
        let tempNum = Int(f[8])
        let cellCnt = Int(f[9])
        var p = 34
        guard p + 2 * cellCnt + 2 * tempNum + 8 <= f.count else { return }

        var cells: [Double] = []
        for _ in 0..<cellCnt {
            let v = u16(f, p) / 1000.0
            cells.append(v)
            p += 2
        }
        var temps: [Double] = []
        for _ in 0..<tempNum {
            temps.append(Double(s16(f, p)))
            p += 2
        }
        let mTemp = Double(s16(f, p)); p += 2
        let bTemp = Double(s16(f, p)); p += 2
        let volt = Double(u16(f, p)) / 100.0; p += 2
        let curr = Double(s16(f, p)) / 10.0; p += 2
        let socV = Int(u16(f, p))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cellVoltages = cells
            self.temperatures = temps
            self.mosTemp = mTemp
            self.packVoltage = volt
            self.current = curr
            self.soc = socV
            self.cellCount = cellCnt
            self.power = volt * curr  // V × A = W，物理上最稳
            self.lastUpdate = Date()
            self.status = "已连接 · \(self.deviceName)"
        }
    }

    private func u16(_ d: Data, _ i: Int) -> UInt16 {
        UInt16(d[i]) | (UInt16(d[i + 1]) << 8)
    }
    private func s16(_ d: Data, _ i: Int) -> Int16 {
        let v = u16(d, i)
        return Int16(bitPattern: v)
    }
}

extension Data {
    func findHeader() -> (offset: Int)? {
        let b = [UInt8](self)
        for i in 0..<(b.count - 1) where b[i] == 0x7E && b[i + 1] == 0xA1 {
            return (offset: i)
        }
        return nil
    }
}
