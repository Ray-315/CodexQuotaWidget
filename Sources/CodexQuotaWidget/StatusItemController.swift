import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let quotaStore: QuotaStore
    private let modeStore: DisplayModeStore
    private let actions: AppActions

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private lazy var menu: NSMenu = makeMenu()
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private let statusLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "重新登录 ChatGPT", action: #selector(loginToChatGPT), keyEquivalent: "")
    private let logoutItem = NSMenuItem(title: "退出云端登录", action: #selector(logoutCloudSession), keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "")

    init(quotaStore: QuotaStore, modeStore: DisplayModeStore, actions: AppActions) {
        self.quotaStore = quotaStore
        self.modeStore = modeStore
        self.actions = actions
        super.init()

        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentSize = NSSize(width: 236, height: 72)
        popover.contentViewController = NSHostingController(
            rootView: QuotaDashboardView(
                quotaStore: quotaStore,
                modeStore: modeStore,
                actions: actions
            )
        )
    }

    func setVisible(_ visible: Bool) {
        if visible {
            installIfNeeded()
        } else {
            if popover.isShown {
                popover.performClose(nil)
                removePopoverDismissMonitors()
            }
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
        }
    }

    func updateTitle() {
        statusItem?.button?.title = quotaStore.menuBarTitle
        updateMenuState()
    }

    @objc
    func handleStatusItemClick(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        let eventType = NSApp.currentEvent?.type

        switch eventType {
        case .rightMouseUp:
            if popover.isShown {
                popover.performClose(nil)
                removePopoverDismissMonitors()
            }
            updateMenuState()
            statusItem?.menu = menu
            button.performClick(nil)
            statusItem?.menu = nil
        default:
            if popover.isShown {
                popover.performClose(nil)
                removePopoverDismissMonitors()
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                installPopoverDismissMonitors()
            }
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else {
            updateTitle()
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.font = .systemFont(ofSize: 13, weight: .medium)
        self.statusItem = statusItem
        updateTitle()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeModeItem(title: "菜单栏", mode: .menuBarOnly))
        menu.addItem(makeModeItem(title: "悬浮窗", mode: .floatingOnly))
        menu.addItem(makeModeItem(title: "同时显示", mode: .both))
        menu.addItem(.separator())
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)
        menu.addItem(.separator())

        loginItem.target = self
        logoutItem.target = self
        refreshItem.target = self
        menu.addItem(loginItem)
        menu.addItem(logoutItem)
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出软件", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func makeModeItem(title: String, mode: DisplayMode) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode.rawValue
        return item
    }

    private func updateMenuState() {
        for item in menu.items {
            guard let rawValue = item.representedObject as? String, let mode = DisplayMode(rawValue: rawValue) else {
                continue
            }

            item.state = mode == modeStore.mode ? .on : .off
        }

        statusLineItem.title = quotaStore.statusMenuText
        logoutItem.isEnabled = quotaStore.canLogoutCloudSession
        refreshItem.isEnabled = quotaStore.isLoading == false
    }

    private func installPopoverDismissMonitors() {
        removePopoverDismissMonitors()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.popover.isShown else {
                return event
            }

            self.popover.performClose(nil)
            self.removePopoverDismissMonitors()
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
                self.removePopoverDismissMonitors()
            }
        }
    }

    private func removePopoverDismissMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverDismissMonitors()
    }

    @objc
    private func selectMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = DisplayMode(rawValue: rawValue)
        else {
            return
        }

        modeStore.mode = mode
    }

    @objc
    private func quitApp() {
        actions.onQuit()
    }

    @objc
    private func loginToChatGPT() {
        actions.onLogin()
    }

    @objc
    private func logoutCloudSession() {
        actions.onLogout()
    }

    @objc
    private func refreshNow() {
        actions.onRefresh()
    }
}
