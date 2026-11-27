import CarPlay
import UIKit

// CarPlay 仪表场景：把远驱 + 蚂蚁保护板数据投到 CarWithin 的 CarPlay 仪表上
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    static let shared = CarPlaySceneDelegate()
    var interfaceController: CPInterfaceController?
    var cluster: CPInstrumentClusterController?

    // 供仪表读取的最新数据（由 PhoneScene 里的管理器持续更新）
    static var speedText: String = "0"
    static var currentText: String = "0A"
    static var ctrlTempText: String = "0℃"
    static var socText: String = "0%"
    static var voltText: String = "0V"

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let cluster = interfaceController.instrumentClusterController
        self.cluster = cluster

        // 四个仪表：速度 / 母线电流 / 控制器温度 / 电量
        let speed = CPGaugeDescription(title: "速度",
                                       gaugeColor: .white,
                                       showBackgroundRing: false,
                                       subtitleTemplate: nil,
                                       attribution: nil,
                                       gaugeProvider: SpeedProvider())
        let current = CPGaugeDescription(title: "电流",
                                         gaugeColor: .systemGreen,
                                         showBackgroundRing: false,
                                         subtitleTemplate: nil,
                                         attribution: nil,
                                         gaugeProvider: CurrentProvider())
        let temp = CPGaugeDescription(title: "控温",
                                      gaugeColor: .systemOrange,
                                      showBackgroundRing: false,
                                      subtitleTemplate: nil,
                                      attribution: nil,
                                      gaugeProvider: TempProvider())
        let soc = CPGaugeDescription(title: "电量",
                                     gaugeColor: .systemBlue,
                                     showBackgroundRing: false,
                                     subtitleTemplate: nil,
                                     attribution: nil,
                                     gaugeProvider: SocProvider())

        cluster?.setGaugeDescriptions([speed, current, temp, soc])
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        self.cluster = nil
    }
}

// 各仪表数值提供者
final class SpeedProvider: NSObject, CPGaugeProvider {
    func gaugeProvider(_ gaugeProvider: CPGaugeProvider,
                       displayTextFor gauge: CPGaugeDescription,
                       in cluster: CPInstrumentClusterController) -> String? {
        return CarPlaySceneDelegate.speedText
    }
}

final class CurrentProvider: NSObject, CPGaugeProvider {
    func gaugeProvider(_ gaugeProvider: CPGaugeProvider,
                       displayTextFor gauge: CPGaugeDescription,
                       in cluster: CPInstrumentClusterController) -> String? {
        return CarPlaySceneDelegate.currentText
    }
}

final class TempProvider: NSObject, CPGaugeProvider {
    func gaugeProvider(_ gaugeProvider: CPGaugeProvider,
                       displayTextFor gauge: CPGaugeDescription,
                       in cluster: CPInstrumentClusterController) -> String? {
        return CarPlaySceneDelegate.ctrlTempText
    }
}

final class SocProvider: NSObject, CPGaugeProvider {
    func gaugeProvider(_ gaugeProvider: CPGaugeProvider,
                       displayTextFor gauge: CPGaugeDescription,
                       in cluster: CPInstrumentClusterController) -> String? {
        return CarPlaySceneDelegate.socText
    }
}
