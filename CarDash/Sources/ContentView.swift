import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var far = FardriverManager()
    @StateObject private var ant = AntBMSManager()
    @State private var wheelText: String = ""
    @State private var sync: AnyCancellable?
    private let wheelKey = "wheelCircumference"

    var body: some View {
        NavigationView {
            Form {
                Section("远驱控制器") {
                    statusRow("状态", far.status)
                    infoRow("电压", String(format: "%.1f V", far.voltage))
                    infoRow("母线电流", String(format: "%.1f A", far.lineCurrent))
                    infoRow("功率", String(format: "%.2f kW", abs(far.power) / 1000.0))
                    infoRow("控制器温度", "\(far.controllerTemp) ℃")
                    infoRow("电机温度", "\(far.motorTemp) ℃")
                    infoRow("档位", "\(far.gear)")
                    Button("重连远驱") { far.rescan() }
                }

                Section("蚂蚁保护板") {
                    statusRow("状态", ant.status)
                    infoRow("总电压", String(format: "%.1f V", ant.packVoltage))
                    infoRow("电流", String(format: "%.1f A", ant.current))
                    infoRow("电量", "\(ant.soc) %")
                    infoRow("功率管温度", String(format: "%.0f ℃", ant.mosTemp))
                    Button("重连保护板") { ant.rescan() }
                }

                Section("速度换算") {
                    HStack {
                        Text("后轮周长（米）")
                        Spacer()
                        TextField("1.53", text: $wheelText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    Text("默认 1.53（130/70-12 后轮）。改完点应用。")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Button("应用") { applyWheel() }
                }

                Section("车机显示") {
                    Text("在 CarWithin 中启动 CarPlay 后，仪表会显示：速度、电流、控制器温度、电量。")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("本 App 需保持运行（可退到后台），手机锁屏不影响仪表数据。")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("车机仪表")
        }
        .onAppear {
            wheelText = String(format: "%.2f", UserDefaults.standard.double(forKey: wheelKey) > 0
                ? UserDefaults.standard.double(forKey: wheelKey) : 1.53)
            let w = UserDefaults.standard.double(forKey: wheelKey)
            if w > 0 { far.wheelCircumferenceM = w }
            far.start()
            ant.start()
            startSync()
        }
    }

    func statusRow(_ t: String, _ v: String) -> some View {
        HStack { Text(t); Spacer(); Text(v).foregroundColor(.gray) }
    }
    func infoRow(_ t: String, _ v: String) -> some View {
        HStack { Text(t); Spacer(); Text(v).font(.system(.body, design: .monospaced)) }
    }

    func applyWheel() {
        if let v = Double(wheelText), v > 0.5, v < 3.0 {
            far.wheelCircumferenceM = v
            UserDefaults.standard.set(v, forKey: wheelKey)
        }
    }

    // 把最新数据同步给 CarPlay 仪表
    func startSync() {
        sync = far.objectWillChange
            .merge(with: ant.objectWillChange)
            .sink { [self] in
                CarPlaySceneDelegate.speedText = String(format: "%.0f km/h", self.far.speedKmh)
                CarPlaySceneDelegate.currentText = String(format: "%.1f A", self.far.lineCurrent)
                CarPlaySceneDelegate.ctrlTempText = "\(self.far.controllerTemp) ℃"
                CarPlaySceneDelegate.socText = self.ant.soc > 0 ? "\(self.ant.soc) %" : "\(self.far.soc) %"
                CarPlaySceneDelegate.voltText = String(format: "%.0f V", self.far.voltage > 0 ? self.far.voltage : self.ant.packVoltage)
            }
    }
}
