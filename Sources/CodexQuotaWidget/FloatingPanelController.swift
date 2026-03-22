import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private let quotaStore: QuotaStore
    private let modeStore: DisplayModeStore
    private let bindingManager: CodexBindingManager
    private let actions: AppActions

    private var panel: NSPanel?

    init(quotaStore: QuotaStore, modeStore: DisplayModeStore, bindingManager: CodexBindingManager, actions: AppActions) {
        self.quotaStore = quotaStore
        self.modeStore = modeStore
        self.bindingManager = bindingManager
        self.actions = actions
    }

    func show() {
        let panel = panel ?? makePanel()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 252, height: 82),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = QuotaDashboardView(
            quotaStore: quotaStore,
            modeStore: modeStore,
            bindingManager: bindingManager,
            actions: actions
        )
        panel.contentView = NSHostingView(rootView: rootView)

        self.panel = panel
        return panel
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
