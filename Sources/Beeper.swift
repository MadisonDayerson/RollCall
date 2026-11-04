import Foundation
import Network
import CryptoKit
import Security

/// Reads chats through Beeper Desktop's own local API (http://localhost:23373).
/// Nothing leaves the Mac: Beeper and RollCall talk to each other directly.
/// RollCall only asks for the "read" permission, so it can never send, edit or delete messages.
enum Beeper {
    static let base = "http://localhost:23373"
    static let chatLinkPrefix = "beeper-chat:"
    static let feedURLPrefix = "beeper:"

    struct Chat: Decodable {
        var id: String
        var title: String
        var network: String?
        var type: String?
        var isArchived: Bool?
    }

    struct LinkPreview: Decodable { var url: String? }

    struct Message: Decodable {
        var id: String
        var chatID: String
        var senderName: String?
        var timestamp: String
        var type: String?
        var text: String?
        var fullTitle: String?
        var isDeleted: Bool?
        var isHidden: Bool?
        var links: [LinkPreview]?

        var date: Date? { Web.isoDate(timestamp)?.0 }
    }

    private struct Page<T: Decodable>: Decodable {
        var items: [T]
        var hasMore: Bool?
        var oldestCursor: String?
    }

    enum BeeperError: LocalizedError {
        case notRunning, notConnected, http(Int), cancelled, badReply

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "Beeper isn't open, or its Desktop API is off. Open Beeper Desktop → Settings → Developers and switch on Beeper Desktop API."
            case .notConnected:
                return "RollCall isn't connected to Beeper. Choose Settings → Chats → “Connect Beeper…” to connect again."
            case .http(let code):
                return "Beeper answered with error \(code)."
            case .cancelled:
                return "Connecting to Beeper was cancelled or took too long."
            case .badReply:
                return "Beeper sent something RollCall didn't understand."
            }
        }
    }

    // MARK: Requests

    static func isRunning() async -> Bool {
        guard let url = URL(string: base + "/v1/info") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 4)
        req.httpMethod = "GET"
        return ((try? await Net.session.data(for: req))?.1 as? HTTPURLResponse)?.statusCode == 200
    }

    /// Why chats can't be read right now (Beeper closed, or RollCall's permission gone), or nil when they can.
    /// The problems that mean Beeper wasn't reachable, as shown on the Sources page.
    static let connectionMessages: Set<String> = Set([BeeperError.notRunning, .notConnected, .cancelled].compactMap(\.errorDescription))

    static func connectionProblem() async -> BeeperError? {
        guard Keychain.read() != nil else { return .notConnected }
        guard await isRunning() else { return .notRunning }
        do { _ = try await send("/v1/chats", query: ["limit": "1"]); return nil }
        catch let e as BeeperError { return e }
        catch { return .badReply }
    }

    private static func send(_ path: String, query: [String: String] = [:], method: String = "GET", json: [String: String]? = nil) async throws -> Data {
        guard let token = Keychain.read() else { throw BeeperError.notConnected }
        var comps = URLComponents(string: base + path)
        if !query.isEmpty { comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await Net.session.data(for: req)
        } catch {
            throw BeeperError.notRunning
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw BeeperError.notConnected }
        guard (200..<300).contains(code) else { throw BeeperError.http(code) }
        return data
    }

    /// Chat IDs contain "!" and ":", so they need escaping inside a URL path.
    static func pathPart(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }

    /// Recently active chats, most recent first.
    static func chats(limit: Int = 200) async throws -> [Chat] {
        let data = try await send("/v1/chats", query: ["limit": String(limit)])
        do { return try JSONDecoder().decode(Page<Chat>.self, from: data).items } catch { throw BeeperError.badReply }
    }

    /// Messages in a chat newer than `since`, oldest first. Reads back a few pages at most.
    /// Busy group chats post hundreds of messages a week, so this reads back far enough to reach `since`.
    static func messages(chatID: String, since: Date, maxPages: Int = 150) async throws -> [Message] {
        var all: [Message] = []
        var cursor: String?
        for _ in 0..<maxPages {
            var query: [String: String] = [:]
            if let cursor { query["cursor"] = cursor; query["direction"] = "before" }
            let data = try await send("/v1/chats/\(pathPart(chatID))/messages", query: query)
            let page: Page<Message>
            do { page = try JSONDecoder().decode(Page<Message>.self, from: data) } catch { throw BeeperError.badReply }
            all += page.items
            let oldest = page.items.compactMap(\.date).min()
            guard page.hasMore == true, let next = page.oldestCursor, let oldest, oldest > since else { break }
            cursor = next
        }
        var seen = Set<String>()
        return all
            .filter { ($0.date ?? .distantPast) > since && seen.insert($0.id).inserted }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// Brings Beeper to the front with the chat (and message) open.
    static func focus(link: String) async throws {
        let rest = String(link.dropFirst(chatLinkPrefix.count))
        let parts = rest.split(separator: "#", maxSplits: 1).map(String.init)
        var body = ["chatID": parts[0]]
        if parts.count > 1 { body["messageID"] = parts[1] }
        _ = try await send("/v1/focus", method: "POST", json: body)
    }

    static func chatLink(chatID: String, messageID: String? = nil) -> String {
        chatLinkPrefix + chatID + (messageID.map { "#" + $0 } ?? "")
    }

    static func feed(for chat: Chat) -> Feed {
        var name = chat.title
        if let n = chat.network, !n.isEmpty { name += " (\(n) via Beeper)" } else { name += " (Beeper)" }
        return Feed(id: "beeper-" + stableHash(chat.id), name: name, url: feedURLPrefix + chat.id,
                    groupURL: nil, kind: .chat, keywordFilter: true, network: chat.network)
    }

    static func chatID(of feed: Feed) -> String { String(feed.url.dropFirst(feedURLPrefix.count)) }

    // MARK: Connecting (OAuth with PKCE, read permission only)

    /// Opens Beeper's permission page in the browser and waits for the user to click Allow.
    @MainActor
    static func connect(open: (URL) -> Void) async throws {
        let server = LoopbackServer()
        let port = try await server.start()
        defer { server.stop() }
        let redirect = "http://127.0.0.1:\(port)/callback"

        // Register RollCall with Beeper (each connect gets a fresh client; that's how public clients work).
        var reg = URLRequest(url: URL(string: base + "/oauth/register")!, timeoutInterval: 10)
        reg.httpMethod = "POST"
        reg.setValue("application/json", forHTTPHeaderField: "Content-Type")
        reg.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "RollCall", "redirect_uris": [redirect], "scope": "read",
            "grant_types": ["authorization_code"], "response_types": ["code"], "token_endpoint_auth_method": "none",
        ] as [String: Any])
        let regData: Data
        do { regData = try await Net.session.data(for: reg).0 } catch { throw BeeperError.notRunning }
        guard let clientID = (try? JSONSerialization.jsonObject(with: regData) as? [String: Any])?["client_id"] as? String else {
            throw BeeperError.badReply
        }

        let verifier = randomString(48)
        let challenge = base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = randomString(16)
        var auth = URLComponents(string: base + "/oauth/authorize")!
        auth.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect), .init(name: "scope", value: "read"),
            .init(name: "state", value: state), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        open(auth.url!)

        let reply = try await server.waitForCallback(timeout: 300)
        guard reply["state"] == state, let code = reply["code"] else { throw BeeperError.cancelled }

        var tok = URLRequest(url: URL(string: base + "/oauth/token")!, timeoutInterval: 10)
        tok.httpMethod = "POST"
        tok.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = ["grant_type": "authorization_code", "code": code, "code_verifier": verifier,
                    "client_id": clientID, "redirect_uri": redirect]
        tok.httpBody = form.map { "\($0.key)=\(pathPart($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await Net.session.data(for: tok)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let token = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["access_token"] as? String else {
            throw BeeperError.badReply
        }
        Keychain.save(token)
    }

    static func randomString(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64url(data)
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Reads "?code=…&state=…" from the first line of an HTTP request.
    static func callbackQuery(_ request: String) -> [String: String]? {
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first ?? request.split(separator: "\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", parts[1].hasPrefix("/callback"),
              let comps = URLComponents(string: "http://127.0.0.1" + parts[1]) else { return nil }
        var out: [String: String] = [:]
        for item in comps.queryItems ?? [] { out[item.name] = item.value ?? "" }
        return out
    }
}

/// A tiny one-shot web server on 127.0.0.1 that catches Beeper's redirect after the user clicks Allow.
final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "motorides.loopback")
    private var callback: CheckedContinuation<[String: String], Error>?
    private var result: Result<[String: String], Error>?
    private var starting: CheckedContinuation<UInt16, Error>?

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let l = try NWListener(using: params)
        listener = l
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        return try await withCheckedThrowingContinuation { cont in
            // Both handlers run on `queue`, one at a time.
            self.starting = cont
            l.stateUpdateHandler = { [weak self] state in
                guard let self, let c = self.starting else { return }
                switch state {
                case .ready:
                    self.starting = nil
                    c.resume(returning: l.port?.rawValue ?? 0)
                case .failed(let e):
                    self.starting = nil
                    c.resume(throwing: e)
                default: break
                }
            }
            l.start(queue: queue)
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                if let r = self.result { cont.resume(with: r); return }
                self.callback = cont
                self.queue.asyncAfter(deadline: .now() + timeout) { self.finish(.failure(Beeper.BeeperError.cancelled)) }
            }
        }
    }

    func stop() { listener?.cancel() }

    private func finish(_ r: Result<[String: String], Error>) {
        guard result == nil else { return }
        result = r
        callback?.resume(with: r)
        callback = nil
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let query = Beeper.callbackQuery(text)
            let ok = query?["code"] != nil
            let body = query == nil ? "Not found"
                : ok ? "<html><body style=\"font-family:-apple-system;padding:3em\"><h2>RollCall is connected to Beeper</h2><p>You can close this tab.</p></body></html>"
                : "<html><body style=\"font-family:-apple-system;padding:3em\"><h2>RollCall wasn't connected</h2><p>You can close this tab and try again from the RollCall menu.</p></body></html>"
            let status = query == nil ? "404 Not Found" : "200 OK"
            let reply = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            c.send(content: Data(reply.utf8), completion: .contentProcessed { _ in c.cancel() })
            if let query { self.finish(.success(query)) }
        }
    }
}

/// Keeps the Beeper access token in the login keychain rather than a plain file. It's read from the keychain
/// once and then remembered, so drawing Settings or reading a chat never waits on a keychain prompt again.
enum Keychain {
    static let service = "au.madiday.motorides.beeper"
    static let account = "beeper-desktop-api"
    /// nil until the keychain has been read; then the token, or .some(nil) when there isn't one.
    nonisolated(unsafe) private static var remembered: String??

    static func save(_ token: String) {
        delete()
        remembered = token
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(token.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        if let remembered { return remembered }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        let token = status == errSecSuccess ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        // A denied or cancelled keychain prompt isn't remembered, so the next read can ask again.
        if status == errSecSuccess || status == errSecItemNotFound { remembered = .some(token) }
        return token
    }

    static func delete() {
        remembered = .some(nil)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
