import Foundation
import CoreBluetooth

// 远驱(Fardriver)控制器 BLE 管理器
// 协议来源: ESP32-Fardriver-BLE-Reader (开源, 已验证)
// 服务 FFE0 / 特征 FFEC，订阅通知即可收到 16 字节状态包（无需写命令）
final class FardriverManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status: String = "未连接"
    @Published var voltage: Double = 0        // V
    @Published var lineCurrent: Double = 0    // A（负=能量回收）
    @Published var power: Double = 0          // W
    @Published var rpm: Int = 0               // 轮速 RPM
    @Published var speedKmh: Double = 0       // km/h（按轮周长换算）
    @Published var gear: Int = 0              // 档位
    @Published var controllerTemp: Int = 0    // ℃ 控制器温度
    @Published var motorTemp: Int = 0         // ℃ 电机温度
    @Published var soc: Int = 0               // %（控制器侧电量）
    @Published var lastUpdate: Date? = nil

    var wheelCircumferenceM: Double = 1.53    // 默认 130/70-12 后轮周长，可在设置里改

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var notifyChar: CBCharacteristic?
    private var rejected: Set<UUID> = []

    static let svcUUID = CBUUID(string: "FFE0")
    static let chrUUID = CBUUID(string: "FFEC")

    // 远驱数据地址映射表（与 ESP32 参考实现一致）
    static let flashReadAddr: [UInt8] = [
        0xE2, 0xE8, 0xEE, 0xE4, 0x06, 0x0C, 0x12, 0xE2, 0xE8, 0xEE, 0x18, 0x1E, 0x24, 0x2A,
        0xE2, 0xE8, 0xEE, 0x30, 0x5D, 0x63, 0x69, 0xE2, 0xE8, 0xEE, 0x7C, 0x82, 0x88, 0x8E,
        0xE2, 0xE8, 0xEE, 0x94, 0x9A, 0xA0, 0xA6, 0xE2, 0xE8, 0xEE, 0xAC, 0xB2, 0xB8, 0xBE,
        0xE2, 0xE8, 0xEE, 0xC4, 0xCA, 0xD0, 0xE2, 0xE8, 0xEE, 0xD6, 0xDC, 0xF4, 0xFA
    ]
    private static let polePairs = 20.0

    func start() {
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func rescan() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        status = "搜索远驱控制器…"
        central?.scanForPeripherals(withServices: [Self.svcUUID], options: nil)
    }

    // MARK: 中央代理
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            status = "搜索远驱控制器…"
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
        status = "发现控制器，连接中…"
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "已连接，识别设备类型…"
        peripheral.delegate = self
        peripheral.discoverServices([Self.svcUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        status = "连接断开，重连中…"
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
            // 没有 FFEC → 不是远驱（可能是蚂蚁保护板），拉黑并换下一个设备
            rejectCurrent()
            return
        }
        notifyChar = chr
        peripheral.setNotifyValue(true, for: chr)
        status = "已连接远驱，等待数据…"
    }

    private func rejectCurrent() {
        if let p = self.peripheral {
            rejected.insert(p.identifier)
            central?.cancelPeripheralConnection(p)
        }
        self.peripheral = nil
        status = "非远驱设备，继续搜索…"
        central?.scanForPeripherals(withServices: [Self.svcUUID], options: nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        parsePacket([UInt8](data))
    }

    // MARK: 16 字节状态包解析
    private func parsePacket(_ b: [UInt8]) {
        guard b.count == 16, verifyCRC(b) else { return }
        let id = Int(b[1] & 0x3F)
        guard id < Self.flashReadAddr.count else { return }
        let addr = Self.flashReadAddr[id]
        let p = Array(b[2...])

        var newVoltage = voltage
        var newCurrent = lineCurrent
        var newGear = gear
        var newRpmRaw: Int = rpm
        var newCtrlTemp = controllerTemp
        var newMotorTemp = motorTemp
        var newSoc = soc

        switch addr {
        case 0xE2:
            newGear = ((Int(p[0]) >> 2) & 0b11) + 1
            newRpmRaw = Int(Int16(bitPattern: UInt16(p[6]) | (UInt16(p[7]) << 8)))
        case 0xE8:
            let v = Double(UInt16(p[0]) | (UInt16(p[1]) << 8)) / 10.0
            if v >= 0 && v <= 100 { newVoltage = v }
            let c = Double(Int16(bitPattern: UInt16(p[4]) | (UInt16(p[5]) << 8))) / 4.0
            if c >= -100 && c <= 300 { newCurrent = c }
        case 0xD6:
            let t = Int(Int16(bitPattern: UInt16(p[10]) | (UInt16(p[11]) << 8)))
            if t > -20 && t < 100 { newCtrlTemp = t }
        case 0xF4:
            let mt = Int(Int16(bitPattern: UInt16(p[0]) | (UInt16(p[1]) << 8)))
            if mt > -20 && mt < 200 { newMotorTemp = mt }
            newSoc = Int(p[3])
        default:
            break
        }

        let rpmVal = max(0, newRpmRaw)
        let wheelRpm = Double(rpmVal) * 4.0 / Self.polePairs
        let spd = wheelRpm * wheelCircumferenceM * 60.0 / 1000.0

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voltage = newVoltage
            self.lineCurrent = newCurrent
            self.power = newVoltage * newCurrent
            self.rpm = rpmVal
            self.speedKmh = spd
            self.gear = newGear
            self.controllerTemp = newCtrlTemp
            self.motorTemp = newMotorTemp
            self.soc = newSoc
            self.lastUpdate = Date()
            self.status = "远驱已连接"
        }
    }

    // CRC-16/MODBUS，初值 0x7F3C（与参考实现一致）
    private func verifyCRC(_ data: [UInt8]) -> Bool {
        var crc: UInt16 = 0x7F3C
        for i in 0..<14 {
            crc ^= UInt16(data[i])
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        let expected = (UInt16(data[15]) << 8) | UInt16(data[14])
        return crc == expected
    }
}
