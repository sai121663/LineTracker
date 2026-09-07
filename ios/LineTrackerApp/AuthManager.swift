import Foundation
import Combine
import Security

/// The signed-in session: token + email. Mirrors what App.jsx keeps in
/// localStorage under "linetracker_session", but stored in the iOS
/// Keychain instead — Keychain is the standard place for anything that
/// authenticates you (localStorage has no real iOS equivalent for secrets).
struct Session: Codable {
    let token: String
    let email: String
}

/// Posted when APIClient gets a 401, same role as the
/// "linetracker:auth-expired" window event in api.js — tells the rest of
/// the app to drop back to the sign-in screen.
extension Notification.Name {
    static let authExpired = Notification.Name("linetracker.authExpired")
}

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var session: Session?

    private let service = "com.linetracker.app"
    private let account = "session"

    init() {
        session = Self.loadFromKeychain(service: service, account: account)
        // Lets the plain-class APIClient read the current token without
        // holding a direct reference to this @MainActor object.
        AuthManagerBridge.tokenProvider = { [weak self] in self?.session?.token }
        NotificationCenter.default.addObserver(
            forName: .authExpired, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.signOut()
            }
        }
    }

    func signIn(token: String, email: String) {
        let next = Session(token: token, email: email)
        session = next
        guard let data = try? JSONEncoder().encode(next) else { return }
        Self.saveToKeychain(data, service: service, account: account)
    }

    func signOut() {
        session = nil
        Self.deleteFromKeychain(service: service, account: account)
    }

    // MARK: - Keychain plumbing
    // Deliberately minimal — just enough to save/load/delete one Data
    // blob under a service+account key. No third-party dependency needed
    // for a single token like this.

    private static func saveToKeychain(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary) // replace any existing entry
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func loadFromKeychain(service: String, account: String) -> Session? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private static func deleteFromKeychain(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
