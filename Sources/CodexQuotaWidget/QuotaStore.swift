import Combine
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var now = Date()
    @Published private(set) var isLoading = false
    @Published private(set) var sourceStatus: QuotaSourceStatus = .unauthenticated
    @Published private(set) var canLogoutCloudSession = false

    var onChange: (() -> Void)?

    private let localProvider: QuotaProvider
    private let cloudProvider: CloudQuotaProvider
    private let sessionResolver: SessionResolver
    private let loginCoordinator: OAuthLoginCoordinator
    private var freshnessTimer: Timer?
    private var lastCloudSnapshot: QuotaSnapshot?
    private var cloudError: CloudQuotaError?

    init(
        localProvider: QuotaProvider,
        cloudProvider: CloudQuotaProvider,
        sessionResolver: SessionResolver,
        loginCoordinator: OAuthLoginCoordinator
    ) {
        self.localProvider = localProvider
        self.cloudProvider = cloudProvider
        self.sessionResolver = sessionResolver
        self.loginCoordinator = loginCoordinator
    }

    deinit {
        freshnessTimer?.invalidate()
    }

    func start() {
        startFreshnessTimer()
        triggerReload()
    }

    func triggerReload() {
        Task {
            await reload()
        }
    }

    func reload() async {
        isLoading = true
        onChange?()

        let cloudResult = await cloudProvider.fetchQuota()
        if cloudResult.status == .cloud, let cloudSnapshot = cloudResult.snapshot {
            lastCloudSnapshot = cloudSnapshot
        }

        let localSnapshot = try? await localProvider.fetchQuota()

        switch cloudResult.status {
        case .cloud:
            snapshot = cloudResult.snapshot ?? localSnapshot ?? lastCloudSnapshot
            sourceStatus = .cloud
            cloudError = nil
        case .unauthenticated:
            snapshot = localSnapshot ?? lastCloudSnapshot
            sourceStatus = .unauthenticated
            cloudError = cloudResult.recoverableError
        case .localFallback, .cloudUnavailable:
            snapshot = localSnapshot ?? lastCloudSnapshot
            sourceStatus = localSnapshot == nil && lastCloudSnapshot != nil ? .cloudUnavailable : .localFallback
            cloudError = cloudResult.recoverableError
        }

        canLogoutCloudSession = await sessionResolver.hasStoredAppSession()
        isLoading = false
        now = Date()
        onChange?()
    }

    func beginCloudLogin() {
        Task { @MainActor in
            isLoading = true
            onChange?()

            do {
                try await loginCoordinator.login()
                canLogoutCloudSession = await sessionResolver.hasStoredAppSession()
                await reload()
            } catch let error as CloudQuotaError {
                cloudError = error
                canLogoutCloudSession = await sessionResolver.hasStoredAppSession()
                isLoading = false
                now = Date()
                onChange?()
            } catch {
                cloudError = .invalidResponse
                canLogoutCloudSession = await sessionResolver.hasStoredAppSession()
                isLoading = false
                now = Date()
                onChange?()
            }
        }
    }

    func logoutCloudSession() {
        Task { @MainActor in
            try? await sessionResolver.clearAppSession()
            canLogoutCloudSession = false
            await reload()
        }
    }

    var menuBarTitle: String {
        let primaryText = snapshot?.primary.map { "\($0.roundedRemainingPercent)%" } ?? "--"
        let secondaryText = snapshot?.secondary.map { "\($0.roundedRemainingPercent)%" } ?? "--"
        return "5h:\(primaryText)    7d:\(secondaryText)"
    }

    var statusMenuText: String {
        switch sourceStatus {
        case .cloud:
            return "当前数据源：云端"
        case .unauthenticated:
            return "当前数据源：本地（未登录）"
        case .localFallback:
            return "当前数据源：本地（云端失效）"
        case .cloudUnavailable:
            if case .networkUnavailable? = cloudError {
                return "当前数据源：本地（云端网络失败）"
            }
            return "当前数据源：本地（云端不可用）"
        }
    }

    var compactRows: [CompactQuotaRow] {
        [
            compactRow(label: "5h", window: snapshot?.primary),
            compactRow(label: "7d", window: snapshot?.secondary)
        ]
    }

    func compactRow(label: String, window: QuotaWindow?) -> CompactQuotaRow {
        guard let window else {
            return CompactQuotaRow(
                label: label,
                progress: 0,
                remainingText: "--"
            )
        }

        return CompactQuotaRow(
            label: label,
            progress: window.remainingPercent / 100,
            remainingText: "\(window.roundedRemainingPercent)%"
        )
    }

    private func startFreshnessTimer() {
        freshnessTimer?.invalidate()
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.onChange?()
            }
        }
    }
}

struct CompactQuotaRow {
    let label: String
    let progress: Double
    let remainingText: String
}
