import Foundation

/// Mirrors frontend/src/api.js. Same base URL config, same "attach bearer
/// token to every request, sign out on 401" behavior — just expressed as
/// async/await instead of axios interceptors.
final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: Config.apiBaseURL)!
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    enum APIError: LocalizedError {
        case unauthorized
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Session expired, please sign in again"
            case .server(let message): return message
            }
        }
    }

    /// Every call goes through here so the 401 -> sign-out behavior lives
    /// in exactly one place, same as api.js's response interceptor.
    private func request(
        path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: Data? = nil,
        authorized: Bool = true
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized, let token = AuthManager.tokenForRequests {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("No HTTP response")
        }

        if http.statusCode == 401 {
            // Only treat a 401 as "your session expired" for requests that
            // WERE sending a session token. For the sign-in call itself
            // (authorized: false), a 401 means the backend rejected the
            // Google credential for some other reason — show its real
            // error message instead of masking it with a generic one.
            if authorized {
                NotificationCenter.default.post(name: .authExpired, object: nil)
                throw APIError.unauthorized
            } else {
                let message = (try? decoder.decode([String: String].self, from: data))?["error"]
                throw APIError.server(message ?? "Sign-in was rejected (401)")
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode([String: String].self, from: data))?["error"]
            throw APIError.server(message ?? "Request failed (\(http.statusCode))")
        }
        return data
    }

    // MARK: - Auth

    func signInWithGoogle(idToken credential: String) async throws -> Session {
        let body = try encoder.encode(["credential": credential])
        let data = try await request(path: "/auth/google", method: "POST", body: body, authorized: false)
        struct Resp: Codable { let token: String; let email: String }
        let resp = try decoder.decode(Resp.self, from: data)
        return Session(token: resp.token, email: resp.email)
    }

    // MARK: - Alerts

    func getAlerts() async throws -> [Alert] {
        let data = try await request(path: "/alerts")
        return try decoder.decode([Alert].self, from: data)
    }

    func createAlert(_ payload: NewAlertRequest) async throws -> Alert {
        let body = try encoder.encode(payload)
        let data = try await request(path: "/alerts", method: "POST", body: body)
        return try decoder.decode(Alert.self, from: data)
    }

    func deleteAlert(id: Int) async throws {
        _ = try await request(path: "/alerts/\(id)", method: "DELETE")
    }

    // MARK: - Market data

    func getStockPrice(ticker: String) async throws -> StockPrice {
        let data = try await request(path: "/stocks/price", query: ["ticker": ticker], authorized: false)
        return try decoder.decode(StockPrice.self, from: data)
    }

    func getOdds(sport: String, market: String = "h2h") async throws -> OddsResponse {
        let data = try await request(path: "/odds", query: ["sport": sport, "market": market], authorized: false)
        return try decoder.decode(OddsResponse.self, from: data)
    }

    // MARK: - Settings

    func getSettings() async throws -> UserSettingsResponse {
        let data = try await request(path: "/settings")
        return try decoder.decode(UserSettingsResponse.self, from: data)
    }

    @discardableResult
    func updateSettings(notifyEmail: Bool) async throws -> UserSettingsResponse {
        let body = try encoder.encode(["notify_email": notifyEmail])
        let data = try await request(path: "/settings", method: "PUT", body: body)
        return try decoder.decode(UserSettingsResponse.self, from: data)
    }
}

/// Mirrors app.py's /settings GET & PUT response — models.py's
/// UserSettings.to_dict().
struct UserSettingsResponse: Codable {
    let userEmail: String
    let notifyEmail: Bool

    enum CodingKeys: String, CodingKey {
        case userEmail = "user_email"
        case notifyEmail = "notify_email"
    }
}

// Small bridge so APIClient (a plain class) can read the current token
// without a direct reference to the @MainActor AuthManager instance — set
// this once at app launch from your App struct's init().
enum AuthManagerBridge {
    static var tokenProvider: (() -> String?)?
}
extension AuthManager {
    static var tokenForRequests: String? { AuthManagerBridge.tokenProvider?() }
}
