import Foundation
import Testing
@testable import TokenIslandCore

@MainActor private final class TestLoginItemService: LoginItemService {
    var status: LoginItemStatus = .notRegistered
    var statusAfterRegister: LoginItemStatus = .enabled
    var registrationError: Error?
    var removalError: Error?
    var registerCount = 0
    var unregisterCount = 0
    var settingsOpenCount = 0
    func register() throws {
        registerCount += 1
        if let registrationError { throw registrationError }
        status = statusAfterRegister
    }
    func unregister() throws {
        unregisterCount += 1
        if let removalError { throw removalError }
        status = .notRegistered
    }
    func openSettings() { settingsOpenCount += 1 }
}

@Test @MainActor func loginItemInitializationNeverChangesSystemSettings() {
    let service = TestLoginItemService()
    let controller = LoginItemController(service: service)
    #expect(controller.status == .notRegistered)
    #expect(service.registerCount == 0)
    #expect(service.unregisterCount == 0)
}

@Test @MainActor func loginItemCanBeEnabledAndDisabledWithoutReregistering() {
    let service = TestLoginItemService()
    let item = LoginItemController(service: service)
    item.setEnabled(true)
    #expect(item.status == .enabled)
    item.setEnabled(true)
    #expect(service.registerCount == 1)
    item.toggle()
    #expect(item.status == .notRegistered)
    #expect(service.unregisterCount == 1)
}

@Test @MainActor func loginItemReflectsExternalSystemChangesWithoutEnablingItAgain() {
    let service = TestLoginItemService()
    service.status = .enabled
    let controller = LoginItemController(service: service)
    service.status = .requiresApproval
    controller.refresh()
    #expect(controller.status == .requiresApproval)
    #expect(service.registerCount == 0)
    controller.setEnabled(false)
    #expect(controller.status == .notRegistered)
    #expect(service.unregisterCount == 1)
}

@Test @MainActor func loginItemPendingApprovalIsDistinctFromEnabledAndCanBeCancelled() {
    let service = TestLoginItemService()
    service.statusAfterRegister = .requiresApproval
    let controller = LoginItemController(service: service)
    controller.setEnabled(true)
    #expect(controller.status == .requiresApproval)
    #expect(controller.lastError == nil)
    #expect(service.settingsOpenCount == 0)
    controller.openSettings()
    #expect(service.settingsOpenCount == 1)
    controller.setEnabled(false)
    #expect(controller.status == .notRegistered)
}

@Test @MainActor func failedLoginItemRegistrationDoesNotPretendItIsEnabled() {
    let service = TestLoginItemService()
    service.registrationError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Register failed"])
    let controller = LoginItemController(service: service)
    controller.setEnabled(true)
    #expect(controller.status == .notRegistered)
    #expect(controller.lastError == "Register failed")
    controller.clearError()
    #expect(controller.lastError == nil)
}

@Test @MainActor func failedLoginItemRemovalKeepsActualEnabledState() {
    let service = TestLoginItemService()
    service.status = .enabled
    service.removalError = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Remove failed"])
    let controller = LoginItemController(service: service)
    controller.setEnabled(false)
    #expect(controller.status == .enabled)
    #expect(controller.lastError == "Remove failed")
}
