import Foundation
import CoreBluetooth

// 蚂蚁保护板 (ANT BMS) BLE 管理器 —— 纯读取
// 协议来源: https://github.com/yosle/ant-bms-ble (MIT)
// 服务 FFE0 / 特征 FFE1，写 0x01 请求帧，收 0x11 实时帧
final class AntBMSManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status: String = "未连接"
    @Published var packVoltage: Double = 0    // V
    @Published var current: Double = 0        // A（负=充电）
    @Published var power: Double = 0          // W
    @Published var soc: Int = 0               // %
    @Published var mosTemp: Double = 0        // ℃ 功率管温度
    @Published var cellVoltages: [Double] = []
    @Published var lastUpdate: Date? = nil

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txChar: CBCharacteristic?
    private var rxBuf = Data()
    private var timer: Timer?
    private var rejected: Set<UUID> = []

    static let svcUUID = CBUUID(string: "FFE0")
    static let chrUUID = CBUUID(string: "FFE1")
    static let requestFrame: [UInt8] = [0x7E, 0xA1, 0x01, 0x00, 0x00, 0xBE, 0x18, 0x55, 0xAA, 0x55]

    func start() {
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func rescan() {
        stopTimer()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        status = "搜索蚂蚁保护板…"
        central?.scanForPeripherals(withServices: [Self.svcUUID], options: nil)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: 中央代理
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            status = "搜索蚂蚁保护板…"
            central.scanForPeripherals(withServices: [Self.svcUUID], options: nil)
        } else {
            status = "蓝牙不可用"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard self.peripheral == nil, !rejected.contains(peripheral.identifier) else { return }
        central.stopScan()
        self.peripheral = peripheral
        status = "发现设备，连接中…"
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "已连接，识别设备类型…"
        peripheral.delegate = self
        peripheral.discoverServices([Self.svcUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stopTimer()
        status = "连接断开，重连中…"
        if !rejected.contains(peripheral.identifier) {
            rejected.insert(peripheral.identifier) // 防止在同一设备上反复失败
        }
        self.peripheral = nil
        central.scanForPeripherals(withServices: [Self.svcUUID], options: nil)
    }

    // MARK: 外设代理
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == Self.svcUUID }) else {
            rejectCurrent()
            return
        }
        peripheral.discoverCharacteristics([Self.chrUUID], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chr = service.characteristics?.first(where: { $0.uuid == Self.chrUUID }) else {
            // 没有 FFE1 → 不是蚂蚁保护板（可能是远驱），换下一个设备
            rejectCurrent()
            return
        }
        txChar = chr
        peripheral.setNotifyValue(true, for: chr)
        status = "已连接蚂蚁保护板，读取中…"
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.requestData()
        }
        RunLoop.main.add(timer!, forMode: .common)
        requestData()
    }

    private func rejectCurrent() {
        if let p = self.peripheral {
            rejected.insert(p.identifier)
            central?.cancelPeripheralConnection(p)
        }
        self.peripheral = nil
        status = "非蚂蚁设备，继续搜索…"
        central?.scanForPeripherals(withServices: [Self.svcUUID], options: nil)
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

    // MARK: 帧解析
    private func parseBuffer() {
        while let idx = findHeader(rxBuf) {
            if rxBuf.count - idx < 10 { break }
            let len = Int(rxBuf[idx + 5])
            let total = 10 + len
            if rxBuf.count - idx < total { break }
            let frame = rxBuf.subdata(in: idx..<(idx + total))
            rxBuf.removeSubrange(0..<(idx + total))
            handleFrame(frame)
        }
        if rxBuf.count > 2048 { rxBuf = Data() }
    }

    private func findHeader(_ d: Data) -> Int? {
        let b = [UInt8](d)
        for i in 0..<(b.count - 1) where b[i] == 0x7E && b[i + 1] == 0xA1 {
            return i
        }
        return nil
    }

    private func handleFrame(_ f: Data) {
        guard f[2] == 0x11, f.count > 40 else { return }
        let tempNum = Int(f[8])
        let cellCnt = Int(f[9])
        var p = 34
        guard p + 2 * cellCnt + 2 * tempNum + 8 <= f.count else { return }

        var cells: [Double] = []
        for _ in 0..<cellCnt {
            cells.append(Double(u16(f, p)) / 1000.0)
            p += 2
        }
        for _ in 0..<tempNum { p += 2 } // 跳过温度点，只留 MOS 温度
        let mTemp = Double(s16(f, p)); p += 2
        let bTemp = Double(s16(f, p)); p += 2
        let volt = Double(u16(f, p)) / 100.0; p += 2
        let curr = Double(s16(f, p)) / 10.0; p += 2
        let socV = Int(u16(f, p))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cellVoltages = cells
            self.mosTemp = mTemp
            self.packVoltage = volt
            self.current = curr
            self.soc = socV
            self.power = volt * curr
            self.lastUpdate = Date()
            self.status = "蚂蚁保护板已连接"
        }
    }

    private func u16(_ d: Data, _ i: Int) -> UInt16 {
        UInt16(d[i]) | (UInt16(d[i + 1]) << 8)
    }
    private func s16(_ d: Data, _ i: Int) -> Int16 {
        Int16(bitPattern: u16(d, i))
    }
}
