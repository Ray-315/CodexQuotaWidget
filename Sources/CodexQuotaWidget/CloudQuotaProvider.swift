import Foundation

protocol QuotaProvider {
    func fetchQuota() async throws -> QuotaSnapshot?
}

struct LocalQuotaProvider: QuotaProvider {
    private let parser: SessionLogParser
    private let sessionsRootURL: URL

    init(
        parser: SessionLogParser = SessionLogParser(),
        sessionsRootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true)
    ) {
        self.parser = parser
        self.sessionsRootURL = sessionsRootURL
    }

    func fetchQuota() async throws -> QuotaSnapshot? {
        try parser.loadLatestSnapshot(from: sessionsRootURL)
    }
}

enum QuotaSourceStatus: Equatable {
    case cloud
    case localFallback
    case cloudUnavailable
    case unauthenticated
}

enum CloudQuotaError: Error, Equatable {
    case unauthenticated
    case tokenExpired
    case refreshFailed
    case privateAPIUnavailable(Int)
    case networkUnavailable
    case invalidResponse
    case malformedPayload
}

struct CloudFetchResult {
    let snapshot: QuotaSnapshot?
    let status: QuotaSourceStatus
    let recoverableError: CloudQuotaError?
}

final class CloudQuotaProvider {
    private let backendClient: ChatGPTBackendClient
    private let sessionResolver: SessionResolver
    private let authClient: ChatGPTAuthClient

    init(
        backendClient: ChatGPTBackendClient = ChatGPTBackendClient(),
        sessionResolver: SessionResolver,
        authClient: ChatGPTAuthClient
    ) {
        self.backendClient = backendClient
        self.sessionResolver = sessionResolver
        self.authClient = authClient
    }

    func fetchQuota() async -> CloudFetchResult {
        guard let session = await sessionResolver.resolveSession() else {
            return CloudFetchResult(snapshot: nil, status: .unauthenticated, recoverableError: .unauthenticated)
        }

        do {
            let snapshot = try await backendClient.fetchUsage(session: session)
            return CloudFetchResult(snapshot: snapshot, status: .cloud, recoverableError: nil)
        } catch let error as CloudQuotaError {
            switch error {
            case .tokenExpired:
                return await refreshAndRetry(session: session)
            case .unauthenticated:
                return CloudFetchResult(snapshot: nil, status: .unauthenticated, recoverableError: error)
            default:
                return CloudFetchResult(snapshot: nil, status: .cloudUnavailable, recoverableError: error)
            }
        } catch {
            return CloudFetchResult(snapshot: nil, status: .cloudUnavailable, recoverableError: .invalidResponse)
        }
    }

    private func refreshAndRetry(session: ChatGPTSession) async -> CloudFetchResult {
        guard session.canRefresh else {
            return CloudFetchResult(snapshot: nil, status: .cloudUnavailable, recoverableError: .refreshFailed)
        }

        do {
            let refreshed = try await authClient.refresh(session: session)
            try await sessionResolver.persistAppSession(refreshed)
            let snapshot = try await backendClient.fetchUsage(session: refreshed)
            return CloudFetchResult(snapshot: snapshot, status: .cloud, recoverableError: nil)
        } catch let error as CloudQuotaError {
            return CloudFetchResult(snapshot: nil, status: .cloudUnavailable, recoverableError: error)
        } catch {
            return CloudFetchResult(snapshot: nil, status: .cloudUnavailable, recoverableError: .refreshFailed)
        }
    }
}

struct ChatGPTBackendClient {
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let userAgent = "CodexQuotaWidget/1.0 (darwin; arm64)"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(session authSession: ChatGPTSession) async throws -> QuotaSnapshot {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(authSession.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudQuotaError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let payload = try JSONDecoder().decode(UsageEnvelope.self, from: data)
                return try payload.makeSnapshot(sourceURL: usageURL)
            case 401:
                throw CloudQuotaError.tokenExpired
            case 403, 404:
                throw CloudQuotaError.privateAPIUnavailable(httpResponse.statusCode)
            case 500 ... 599:
                throw CloudQuotaError.privateAPIUnavailable(httpResponse.statusCode)
            default:
                throw CloudQuotaError.privateAPIUnavailable(httpResponse.statusCode)
            }
        } catch let error as CloudQuotaError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
                throw CloudQuotaError.networkUnavailable
            case .userAuthenticationRequired:
                throw CloudQuotaError.unauthenticated
            default:
                throw CloudQuotaError.invalidResponse
            }
        } catch {
            throw CloudQuotaError.invalidResponse
        }
    }
}

private struct UsageEnvelope: Decodable {
    let planType: String?
    let rateLimit: UsageRateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    func makeSnapshot(sourceURL: URL) throws -> QuotaSnapshot {
        guard let rateLimit else {
            throw CloudQuotaError.malformedPayload
        }

        return QuotaSnapshot(
            primary: QuotaWindow(
                usedPercent: rateLimit.primaryWindow?.usedPercent,
                windowMinutes: rateLimit.primaryWindow?.windowMinutes,
                resetsAtEpoch: rateLimit.primaryWindow?.resetsAt
            ),
            secondary: QuotaWindow(
                usedPercent: rateLimit.secondaryWindow?.usedPercent,
                windowMinutes: rateLimit.secondaryWindow?.windowMinutes,
                resetsAtEpoch: rateLimit.secondaryWindow?.resetsAt
            ),
            planType: planType,
            capturedAt: Date(),
            sourceFile: sourceURL
        )
    }
}

private struct UsageRateLimit: Decodable {
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct UsageWindow: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Int?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetsAt = "reset_at"
    }

    var windowMinutes: Int? {
        guard let limitWindowSeconds else {
            return nil
        }

        return limitWindowSeconds / 60
    }
}
