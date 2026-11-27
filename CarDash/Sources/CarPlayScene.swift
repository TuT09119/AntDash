import CarPlay
import UIKit

// CarPlay 场景：用最稳定的列表模板（CPListTemplate）显示仪表数据，
// 每秒刷新一次，兼容 CarWithin 与所有 CarPlay 环境。
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    static let shared = CarPlaySceneDelegate()
    var interfaceController: CPInterfaceController?
    private var timer: Timer?
    private var items: [CPListItem] = []

    // 供手机端同步的最新数据
    static var speedText: String = "0 km/h"
    static var currentText: String = "0.0 A"
    static var ctrlTempText: String = "0 ℃"
    static var socText: String = "0 %"
    static var voltText: String = "0 V"

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        let speed = CPListItem(text: "速度", detailText: CarPlaySceneDelegate.speedText)
        let current = CPListItem(text: "母线电流", detailText: CarPlaySceneDelegate.currentText)
        let temp = CPListItem(text: "控制器温度", detailText: CarPlaySceneDelegate.ctrlTempText)
        let soc = CPListItem(text: "电量", detailText: CarPlaySceneDelegate.socText)
        let volt = CPListItem(text: "电压", detailText: CarPlaySceneDelegate.voltText)
        items = [speed, current, temp, soc, volt]

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "车机仪表", sections: [section])
        interfaceController.setRootTemplate(template, animated: false)

        startTimer()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        timer?.invalidate()
        timer = nil
        self.interfaceController = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateItems()
        }
        if let t = timer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func updateItems() {
        guard items.count >= 5 else { return }
        items[0].setDetailText(CarPlaySceneDelegate.speedText)
        items[1].setDetailText(CarPlaySceneDelegate.currentText)
        items[2].setDetailText(CarPlaySceneDelegate.ctrlTempText)
        items[3].setDetailText(CarPlaySceneDelegate.socText)
        items[4].setDetailText(CarPlaySceneDelegate.voltText)
    }
}
