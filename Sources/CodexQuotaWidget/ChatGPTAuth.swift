import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security

enum ChatGPTSessionSource: String, Codable {
    case codexAuthFile
    case appKeychain
}

struct ChatGPTSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let accountID: String
    let clientID: String
    let idToken: String?
    let source: ChatGPTSessionSource
    let updatedAt: Date

    var canRefresh: Bool {
        guard let refreshToken else {
            return false
        }

        return !refreshToken.isEmpty
    }
}

actor SessionResolver {
    private let authFileURL: URL
    private let keychainStore: SessionKeychainStore
    private var inMemorySession: ChatGPTSession?

    init(
        authFileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json"),
        keychainStore: SessionKeychainStore = SessionKeychainStore()
    ) {
        self.authFileURL = authFileURL
        self.keychainStore = keychainStore
    }

    func resolveSession() -> ChatGPTSession? {
        if let inMemorySession {
            return inMemorySession
        }

        if let keychainSession = try? keychainStore.load() {
            inMemorySession = keychainSession
            return keychainSession
        }

        if let authFileSession = loadCodexAuthSession() {
            return authFileSession
        }

        return nil
    }

    func persistAppSession(_ session: ChatGPTSession) throws {
        let stored = ChatGPTSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            accountID: session.accountID,
            clientID: session.clientID,
            idToken: session.idToken,
            source: .appKeychain,
            updatedAt: Date()
        )

        try keychainStore.save(stored)
        inMemorySession = stored
    }

    func clearAppSession() throws {
        try keychainStore.delete()
        inMemorySession = nil
    }

    func hasStoredAppSession() -> Bool {
        (try? keychainStore.load()) != nil
    }

    private func loadCodexAuthSession() -> ChatGPTSession? {
        guard
            let data = try? Data(contentsOf: authFileURL),
            let payload = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
            let accessToken = payload.tokens.accessToken,
            let accountID = payload.tokens.accountID
        else {
            return nil
        }

        let clientID = JWTClaimsDecoder.clientID(from: payload.tokens.idToken)
            ?? JWTClaimsDecoder.clientID(from: accessToken)
            ?? "app_EMoamEEZ73f0CkXaXp7hrann"

        return ChatGPTSession(
            accessToken: accessToken,
            refreshToken: payload.tokens.refreshToken,
            accountID: accountID,
            clientID: clientID,
            idToken: payload.tokens.idToken,
            source: .codexAuthFile,
            updatedAt: payload.lastRefreshDate ?? Date()
        )
    }
}

struct SessionKeychainStore {
    private let service = "com.codexquotawidget.chatgpt.session"
    private let account = "default"

    func save(_ session: ChatGPTSession) throws {
        let data = try JSONEncoder().encode(session)
        try delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func load() throws -> ChatGPTSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                return nil
            }
            return try JSONDecoder().decode(ChatGPTSession.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

struct ChatGPTAuthClient {
    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refresh(session currentSession: ChatGPTSession) async throws -> ChatGPTSession {
        guard let refreshToken = currentSession.refreshToken else {
            throw CloudQuotaError.refreshFailed
        }

        let body = formEncoded([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": currentSession.clientID
        ])

        let response = try await requestToken(body: body)
        return try response.makeSession(
            fallbackAccountID: currentSession.accountID,
            fallbackClientID: currentSession.clientID,
            source: .appKeychain
        )
    }

    func exchangeCode(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        clientID: String
    ) async throws -> ChatGPTSession {
        let body = formEncoded([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": redirectURI,
            "client_id": clientID
        ])

        let response = try await requestToken(body: body)
        return try response.makeSession(
            fallbackAccountID: nil,
            fallbackClientID: clientID,
            source: .appKeychain
        )
    }

    private func requestToken(body: Data) async throws -> TokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudQuotaError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                return try JSONDecoder().decode(TokenResponse.self, from: data)
            case 400, 401:
                throw CloudQuotaError.refreshFailed
            default:
                throw CloudQuotaError.privateAPIUnavailable(httpResponse.statusCode)
            }
        } catch let error as CloudQuotaError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
                throw CloudQuotaError.networkUnavailable
            default:
                throw CloudQuotaError.invalidResponse
            }
        } catch {
            throw CloudQuotaError.invalidResponse
        }
    }

    private func formEncoded(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .sorted()
            .joined(separator: "&")

        return Data(body.utf8)
    }

    private func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?/"))) ?? value
    }
}

@MainActor
final class OAuthLoginCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let authClient: ChatGPTAuthClient
    private let sessionResolver: SessionResolver
    private let redirectPort: UInt16
    private let clientID: String
    private var webSession: ASWebAuthenticationSession?

    init(
        authClient: ChatGPTAuthClient,
        sessionResolver: SessionResolver,
        redirectPort: UInt16 = 1455,
        clientID: String = "app_EMoamEEZ73f0CkXaXp7hrann"
    ) {
        self.authClient = authClient
        self.sessionResolver = sessionResolver
        self.redirectPort = redirectPort
        self.clientID = clientID
    }

    func login() async throws {
        let verifier = PKCECodeVerifier.generate()
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let redirectURI = "http://127.0.0.1:\(redirectPort)/auth/callback"
        let listener = try OAuthCallbackListener(port: redirectPort, expectedState: state)
        try listener.start()

        let authURL = try makeAuthorizationURL(
            codeChallenge: verifier.codeChallenge,
            state: state,
            redirectURI: redirectURI
        )

        let webSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: nil) { _, _ in }
        webSession.presentationContextProvider = self
        webSession.prefersEphemeralWebBrowserSession = false
        self.webSession = webSession

        if webSession.start() == false {
            NSWorkspace.shared.open(authURL)
        }

        do {
            let callback = try await listener.waitForCallback()
            let session = try await authClient.exchangeCode(
                code: callback.code,
                codeVerifier: verifier.rawValue,
                redirectURI: redirectURI,
                clientID: clientID
            )
            try await sessionResolver.persistAppSession(session)
            webSession.cancel()
            self.webSession = nil
        } catch {
            webSession.cancel()
            self.webSession = nil
            throw error
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    private func makeAuthorizationURL(codeChallenge: String, state: String, redirectURI: String) throws -> URL {
        var components = URLComponents(string: "https://auth.openai.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components?.url else {
            throw CloudQuotaError.invalidResponse
        }

        return url
    }
}

private struct CodexAuthFile: Decodable {
    let lastRefresh: String?
    let tokens: CodexAuthTokens

    enum CodingKeys: String, CodingKey {
        case lastRefresh = "last_refresh"
        case tokens
    }

    var lastRefreshDate: Date? {
        guard let lastRefresh else {
            return nil
        }

        return ISO8601DateFormatter().date(from: lastRefresh)
    }
}

private struct CodexAuthTokens: Decodable {
    let accessToken: String?
    let accountID: String?
    let idToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }

    func makeSession(
        fallbackAccountID: String?,
        fallbackClientID: String,
        source: ChatGPTSessionSource
    ) throws -> ChatGPTSession {
        let accountID = JWTClaimsDecoder.accountID(from: accessToken)
            ?? JWTClaimsDecoder.accountID(from: idToken)
            ?? fallbackAccountID

        guard let accountID else {
            throw CloudQuotaError.invalidResponse
        }

        let clientID = JWTClaimsDecoder.clientID(from: idToken)
            ?? JWTClaimsDecoder.clientID(from: accessToken)
            ?? fallbackClientID

        return ChatGPTSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountID: accountID,
            clientID: clientID,
            idToken: idToken,
            source: source,
            updatedAt: Date()
        )
    }
}

private enum JWTClaimsDecoder {
    static func accountID(from token: String?) -> String? {
        payload(from: token)?["https://api.openai.com/auth.chatgpt_account_id"] as? String
    }

    static func clientID(from token: String?) -> String? {
        if let clientID = payload(from: token)?["client_id"] as? String {
            return clientID
        }

        if let audience = payload(from: token)?["aud"] as? [String] {
            return audience.first
        }

        return payload(from: token)?["aud"] as? String
    }

    private static func payload(from token: String?) -> [String: Any]? {
        guard let token else {
            return nil
        }

        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard
            let data = Data(base64Encoded: base64),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object
    }
}

private struct PKCECodeVerifier {
    let rawValue: String

    var codeChallenge: String {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func generate() -> PKCECodeVerifier {
        let bytes = (0 ..< 32).map { _ in UInt8.random(in: .min ... .max) }
        let rawValue = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return PKCECodeVerifier(rawValue: rawValue)
    }
}

private final class OAuthCallbackListener {
    private let listener: NWListener
    private let expectedState: String
    private var continuation: CheckedContinuation<OAuthCallback, Error>?

    init(port: UInt16, expectedState: String) throws {
        self.listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        self.expectedState = expectedState
    }

    func start() throws {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: DispatchQueue(label: "codex.quota.widget.oauth"))
    }

    func waitForCallback() async throws -> OAuthCallback {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "codex.quota.widget.oauth.connection"))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.finish(with: .failure(error))
                return
            }

            guard
                let data,
                let request = String(data: data, encoding: .utf8),
                let requestLine = request.components(separatedBy: "\r\n").first,
                let path = requestLine.split(separator: " ").dropFirst().first,
                let components = URLComponents(string: "http://127.0.0.1\(path)")
            else {
                self.respond(connection: connection, body: "Invalid request")
                self.finish(with: .failure(CloudQuotaError.invalidResponse))
                return
            }

            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            let state = components.queryItems?.first(where: { $0.name == "state" })?.value

            if state != self.expectedState || code == nil {
                self.respond(connection: connection, body: "Login failed")
                self.finish(with: .failure(CloudQuotaError.invalidResponse))
                return
            }

            self.respond(connection: connection, body: "Login succeeded. You can close this window.")
            self.finish(with: .success(OAuthCallback(code: code!, state: state!)))
        }
    }

    private func respond(connection: NWConnection, body: String) {
        let html = """
        <html><body style="font-family:-apple-system;padding:24px;">\(body)</body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(with result: Result<OAuthCallback, Error>) {
        listener.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}

private struct OAuthCallback {
    let code: String
    let state: String
}
