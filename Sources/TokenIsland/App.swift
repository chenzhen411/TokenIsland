import AppKit
import SwiftUI
import Combine
import TokenIslandCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: IslandStore!
    private var island: IslandPanelController?
    private var statusItem: NSStatusItem?
    private var wakeObserver: NSObjectProtocol?
    private var previewWindow: NSWindow?
    private var loginItemMenuItem: NSMenuItem?
    private var approvalMenuItem: NSMenuItem?
    private var loginItemErrorObserver: AnyCancellable?
    private var activeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        store = IslandStore()
        if CommandLine.arguments.contains("--check-connection") {
            Task {
                let provider = ChatGPTProvider()
                do {
                    if let result = try await provider.fetch() {
                        print("ChatGPT connection OK; plan=\(result.plan); dailyBuckets=\(result.days?.count ?? 0); quotaBuckets=\(result.limits?.buckets.count ?? 0); accountTodayAvailable=\(result.tokens(on: Date(), scope: .account) != nil); localTodayAvailable=\(result.tokens(on: Date(), scope: .local) != nil)")
                        print("Latest daily bucket date: \(result.days?.map(\.startDate).max() ?? "unavailable")")
                        print("Local desktop events: sessions=\(result.localUsage?.sessionCount ?? 0); hourlyBuckets=\(result.localUsage?.hours.count ?? 0)")
                        if let warning = result.warning { print("Warning: \(warning)") }
                    } else { print("ChatGPT sign-in required") }
                } catch { print("Connection failed: \(error.localizedDescription)") }
                provider.stop(); NSApplication.shared.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--render-preview") { store.setDemo(true) }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            renderPreview(to: CommandLine.arguments[index + 1]); NSApplication.shared.terminate(nil); return
        }
        island = IslandPanelController(store: store)
        island?.show()
        if !store.isDemo { store.start() }
        configureMenu()
        loginItemErrorObserver = store.loginItem.$lastError.compactMap { $0 }.sink { [weak self] message in
            Task { @MainActor [weak self] in self?.showLoginItemError(message) }
        }
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.loginItem.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
        if CommandLine.arguments.contains("--expanded") { island?.reveal() }
    }
    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "TokenIsland")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "TokenIsland", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        addItem("展开灵动岛", action: #selector(reveal), to: menu)
        addItem("刷新用量", action: #selector(refresh), to: menu)
        addItem("登录 ChatGPT…", action: #selector(login), to: menu)
        addItem("打开 ChatGPT", action: #selector(openChatGPT), to: menu)
        addItem("查看官方用量", action: #selector(openUsage), to: menu)
        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: "开机自启", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        loginItemMenuItem = loginItem
        let approval = NSMenuItem(title: "在系统设置中允许…", action: #selector(openLoginItemSettings), keyEquivalent: "")
        approval.target = self
        menu.addItem(approval)
        approvalMenuItem = approval
        updateLoginItemMenu()
        menu.addItem(.separator())
        addItem("切换演示数据", action: #selector(toggleDemo), to: menu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 TokenIsland", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem?.menu = menu
    }
    private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }
    @objc private func reveal() { island?.reveal() }
    @objc private func refresh() { Task { await store.refresh() } }
    @objc private func login() { island?.reveal(); store.login() }
    @objc private func openChatGPT() { store.openChatGPT() }
    @objc private func openUsage() { store.openUsage() }
    @objc private func toggleDemo() { store.setDemo(!store.isDemo) }
    @objc private func toggleLoginItem() { store.loginItem.toggle(); updateLoginItemMenu() }
    @objc private func openLoginItemSettings() { store.loginItem.openSettings() }
    func menuWillOpen(_ menu: NSMenu) { store.loginItem.refresh(); updateLoginItemMenu() }
    private func updateLoginItemMenu() {
        let status = store.loginItem.status
        loginItemMenuItem?.title = status.title
        loginItemMenuItem?.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
        approvalMenuItem?.isHidden = status != .requiresApproval
    }
    private func showLoginItemError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "无法修改开机自启"
        alert.informativeText = message + "\n请确认 TokenIsland 已安装到本机应用程序目录，再重试。"
        alert.addButton(withTitle: "好")
        alert.runModal()
        store.loginItem.clearError()
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        store?.stop(); island?.close()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        loginItemErrorObserver?.cancel()
    }
    private func renderPreview(to path: String) {
        let compact = CommandLine.arguments.contains("--compact")
        store.expanded = !compact
        store.detailHeight = 740
        let renderer = ImageRenderer(content: IslandView(store: store, forExport: true)
            .frame(width: compact ? store.compactWidth : store.expandedWidth,
                   height: compact ? store.headerHeight : store.expandedHeight, alignment: .top)
            .clipped())
        renderer.scale = 2
        guard let cg = renderer.cgImage else { print("Preview rendering failed"); return }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        do {
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try png.write(to: URL(fileURLWithPath: path)); print("Preview saved: \(path)")
        } catch { print("Preview export failed: \(error.localizedDescription)") }
    }
}

@main enum TokenIslandApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
