import AppKit
import SwiftUI

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Keep SwiftUI at its fully expanded size. Window geometry changes only at
/// transition boundaries; Charts and the calendar never reflow on every frame.
private final class IslandCanvas: NSView {
    let hosting: NSHostingView<IslandView>
    var canvasSize: NSSize = .zero { didSet { needsLayout = true } }
    init(store: IslandStore) {
        hosting = NSHostingView(rootView: IslandView(store: store))
        super.init(frame: .zero)
        hosting.sizingOptions = []
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(hosting)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        hosting.frame = NSRect(x: (bounds.width - canvasSize.width) / 2,
                               y: bounds.height - canvasSize.height,
                               width: canvasSize.width, height: canvasSize.height)
    }
}

@MainActor final class IslandPanelController {
    let store: IslandStore
    private let panel: FloatingPanel
    private let canvas: IslandCanvas
    private var collapseTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private let transitionDuration = 0.18

    init(store: IslandStore) {
        self.store = store
        canvas = IslandCanvas(store: store)
        panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.contentView = canvas
        store.onExpansionChange = { [weak self] expanded in self?.transition(to: expanded) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateScreen() }
        }
        updateScreen()
    }
    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }
    private func updateScreen() {
        collapseTask?.cancel()
        guard let screen = targetScreen else { return }
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            store.notchWidth = max(0, right.minX - left.maxX)
            store.headerHeight = max(30, screen.safeAreaInsets.top)
        } else { store.notchWidth = 0; store.headerHeight = 28 }
        store.detailHeight = min(680, max(360, screen.frame.height - store.headerHeight - 24))
        canvas.canvasSize = NSSize(width: store.expandedWidth, height: store.expandedHeight)
        resizeWindow(expanded: store.expanded)
        canvas.layoutSubtreeIfNeeded()
    }
    func show() { panel.orderFrontRegardless() }
    func reveal() { store.setExpanded(true); panel.orderFrontRegardless() }

    private func resizeWindow(expanded: Bool) {
        guard let screen = targetScreen else { return }
        let width = expanded ? store.expandedWidth : store.compactWidth
        let height = expanded ? store.expandedHeight : store.headerHeight
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height), display: true)
        canvas.layoutSubtreeIfNeeded()
    }
    private func transition(to expanded: Bool) {
        collapseTask?.cancel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if expanded { resizeWindow(expanded: true) }
        withAnimation(reduceMotion ? nil : .easeOut(duration: transitionDuration)) {
            store.expanded = expanded
        }
        if !expanded {
            if reduceMotion { resizeWindow(expanded: false); return }
            collapseTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
                guard let self, !self.store.expanded else { return }
                self.resizeWindow(expanded: false)
            }
        }
    }
    func close() {
        collapseTask?.cancel()
        store.onExpansionChange = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.close()
    }
}
