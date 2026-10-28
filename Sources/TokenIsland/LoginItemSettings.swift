import ServiceManagement
import SwiftUI
import TokenIslandCore

@MainActor final class SystemLoginItemService: LoginItemService {
    private let service = SMAppService.mainApp
    var status: LoginItemStatus {
        switch service.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }
    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

struct LoginItemMenu: View {
    @ObservedObject var controller: LoginItemController
    var body: some View {
        Toggle(controller.status.title, isOn: Binding(
            get: { controller.status.isRegistered },
            set: { controller.setEnabled($0) }
        ))
        .help("启用后，在登录这台 Mac 时自动启动 TokenIsland")
        .onAppear { controller.refresh() }
        if controller.status == .requiresApproval {
            Button("在系统设置中允许…", action: controller.openSettings)
        }
    }
}
