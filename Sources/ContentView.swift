import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @StateObject private var gps = SpeedManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // 状态栏
                    HStack {
                        Circle()
                            .fill(ble.lastUpdate != nil ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)
                        Text(ble.status)
                            .font(.footnote)
                            .foregroundColor(.gray)
                        Spacer()
                        Button("重连") { ble.rescan() }
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.3))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)

                    // 功率大字
                    VStack(spacing: 2) {
                        Text(String(format: "%.2f", abs(ble.power) / 1000.0))
                            .font(.system(size: 76, weight: .bold, design: .rounded))
                            .foregroundColor(ble.current >= 0 ? .green : .orange)
                        Text("kW " + (ble.current >= 0 ? "放电" : "充电"))
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)

                    // 速度
                    Text(String(format: "%.0f", gps.speedKmh))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("km/h · GPS")
                        .font(.caption)
                        .foregroundColor(.gray)

                    // 电池数据网格
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        infoBox("总电压", String(format: "%.1f V", ble.packVoltage), .blue)
                        infoBox("电流", String(format: "%.1f A", ble.current), .cyan)
                        infoBox("电量", "\(ble.soc) %", .green)
                        infoBox("功率管温度", String(format: "%.0f ℃", ble.mosTemp), .orange)
                    }
                    .padding(.horizontal)

                    // 每串电压
                    if !ble.cellVoltages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("每串电压（共 \(ble.cellCount) 串）")
                                .font(.caption)
                                .foregroundColor(.gray)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 6) {
                                ForEach(ble.cellVoltages.indices, id: \.self) { i in
                                    VStack(spacing: 1) {
                                        Text(String(format: "%.3f", ble.cellVoltages[i]))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.white)
                                        Text("\(i + 1)")
                                            .font(.system(size: 8))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(3)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // 温度
                    if !ble.temperatures.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("温度")
                                .font(.caption)
                                .foregroundColor(.gray)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 6) {
                                ForEach(ble.temperatures.indices, id: \.self) { i in
                                    Text(String(format: "%.0f℃", ble.temperatures[i]))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(3)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Text("数据来自蚂蚁保护板（只读）· 速度来自手机 GPS")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            ble.start()
            gps.start()
        }
    }

    func infoBox(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }
}
