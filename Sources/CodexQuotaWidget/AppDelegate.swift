import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionResolver = SessionResolver()
    private lazy var authClient = ChatGPTAuthClient()
    private lazy var loginCoordinator = OAuthLoginCoordinator(authClient: authClient, sessionResolver: sessionResolver)
    private lazy var quotaStore = QuotaStore(
        localProvider: LocalQuotaProvider(),
        cloudProvider: CloudQuotaProvider(sessionResolver: sessionResolver, authClient: authClient),
        sessionResolver: sessionResolver,
        loginCoordinator: loginCoordinator
    )
    private let modeStore = DisplayModeStore()

    private var statusItemController: StatusItemController?
    private var floatingPanelController: FloatingPanelController?
    private var watcher: SessionLogWatcher?
    private var pollingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let actions = AppActions(
            onLogin: { [weak self] in self?.quotaStore.beginCloudLogin() },
            onLogout: { [weak self] in self?.quotaStore.logoutCloudSession() },
            onRefresh: { [weak self] in self?.quotaStore.triggerReload() },
            onQuit: { NSApp.terminate(nil) }
        )

        statusItemController = StatusItemController(quotaStore: quotaStore, modeStore: modeStore, actions: actions)
        floatingPanelController = FloatingPanelController(quotaStore: quotaStore, modeStore: modeStore, actions: actions)

        quotaStore.onChange = { [weak self] in
            self?.statusItemController?.updateTitle()
        }

        modeStore.onChange = { [weak self] in
            self?.applyDisplayMode()
        }

        applyDisplayMode()
        quotaStore.start()
        startPollingTimer()

        watcher = SessionLogWatcher { [weak self] in
            Task { @MainActor in
                self?.quotaStore.triggerReload()
            }
        }
        watcher?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTimer?.invalidate()
        watcher?.stop()
    }

    private func startPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.quotaStore.triggerReload()
            }
        }
    }

    private func applyDisplayMode() {
        switch modeStore.mode {
        case .menuBarOnly:
            statusItemController?.setVisible(true)
            floatingPanelController?.hide()
        case .floatingOnly:
            statusItemController?.setVisible(false)
            floatingPanelController?.show()
        case .both:
            statusItemController?.setVisible(true)
            floatingPanelController?.show()
        }

        statusItemController?.updateTitle()
    }
}
