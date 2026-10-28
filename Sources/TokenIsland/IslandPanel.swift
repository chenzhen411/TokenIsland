import AppKit
import SwiftUI
import QuartzCore

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class IslandPanelController {
    let store: IslandStore
    private let panel: FloatingPanel
    private var hoverTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    init(store: IslandStore) {
        self.store = store
        panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: IslandView(store: store, onHover: { [weak self] inside in self?.hover(inside) }))
        store.onResize = { [weak self] in self?.resize(animated: true) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateScreen() }
        }
        updateScreen()
    }
    private var targetScreen: NSScreen? {
        // Prefer the built-in notched display, then the main display.
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }
    private func updateScreen() {
        guard let screen = targetScreen else { return }
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            store.notchWidth = max(0, right.minX - left.maxX)
            store.headerHeight = max(38, screen.safeAreaInsets.top + 3)
        } else { store.notchWidth = 0; store.headerHeight = 38 }
        store.detailHeight = min(680, max(360, screen.frame.height - store.headerHeight - 24))
        resize(animated: false)
    }
    func show() { panel.orderFrontRegardless() }
    func reveal() { store.setExpanded(true); panel.orderFrontRegardless() }
    private func resize(animated: Bool) {
        guard let screen = targetScreen else { return }
        let width = store.expanded ? store.expandedWidth : store.compactWidth
        let height = store.expanded ? store.expandedHeight : store.headerHeight
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else { panel.setFrame(frame, display: true) }
    }
    private func hover(_ inside: Bool) {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: inside ? 160_000_000 : 450_000_000) } catch { return }
            guard let self else { return }
            if inside { self.store.setExpanded(true) }
            else if !self.store.pinned { self.store.setExpanded(false) }
        }
    }
    func close() {
        hoverTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.close()
    }
}
