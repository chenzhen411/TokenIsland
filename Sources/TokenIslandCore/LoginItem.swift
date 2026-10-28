import Foundation
import Combine

public enum LoginItemStatus: Equatable {
    case notRegistered, enabled, requiresApproval, notFound

    public var isRegistered: Bool { self == .enabled || self == .requiresApproval }
    public var title: String { self == .requiresApproval ? "开机自启（等待系统允许）" : "开机自启" }
}

@MainActor public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

/// The operating system is the source of truth; never restore a disabled login
/// item from a saved preference or silently register one during app startup.
@MainActor public final class LoginItemController: ObservableObject {
    @Published public private(set) var status: LoginItemStatus
    @Published public private(set) var lastError: String?
    private let service: any LoginItemService

    public init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }
    public func refresh() { status = service.status }
    public func setEnabled(_ enabled: Bool) {
        lastError = nil
        refresh()
        guard enabled != status.isRegistered else { return }
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
            refresh()
        } catch {
            refresh()
            // A successfully registered item can still need the user's approval.
            if enabled && status == .requiresApproval { return }
            lastError = error.localizedDescription
        }
    }
    public func toggle() { refresh(); setEnabled(!status.isRegistered) }
    public func openSettings() { service.openSettings() }
    public func clearError() { lastError = nil }
}
