import Foundation

/// Mirrors backend/models.py Alert.to_dict() exactly — field names and
/// optionality match the Flask response one-to-one so decoding "just works"
/// against the existing API with no backend changes.
struct Alert: Codable, Identifiable {
    let id: Int
    let alertType: String
    let companyName: String?
    let ticker: String?
    let sport: String?
    let eventId: String?
    let homeTeam: String?
    let awayTeam: String?
    let homeLogo: String?
    let awayLogo: String?
    let market: String?
    let outcomeName: String?
    let bookmaker: String?
    let targetValue: Double
    let currentValue: Double?
    let liveValue: Double?
    let direction: String       // "above" or "below"
    let triggered: Bool
    let createdAt: String?
    let triggeredAt: String?
    let userEmail: String
    let commenceTime: String?

    enum CodingKeys: String, CodingKey {
        case id
        case alertType = "alert_type"
        case companyName = "company_name"
        case ticker
        case sport
        case eventId = "event_id"
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case homeLogo = "home_logo"
        case awayLogo = "away_logo"
        case market
        case outcomeName = "outcome_name"
        case bookmaker
        case targetValue = "target_value"
        case currentValue = "current_value"
        case liveValue = "live_value"
        case direction
        case triggered
        case createdAt = "created_at"
        case triggeredAt = "triggered_at"
        case userEmail = "user_email"
        case commenceTime = "commence_time"
    }
}

/// Payload shape for POST /alerts — only the fields create_alert() in
/// app.py actually reads. Everything else it derives server-side.
struct NewAlertRequest: Codable {
    var alertType: String       // "Stock 🌱" or "Bet 🎟️" — matches app.py's exact check
    var ticker: String?
    var companyName: String?
    var sport: String?
    var eventId: String?
    var homeTeam: String?
    var awayTeam: String?
    var homeLogo: String?
    var awayLogo: String?
    var market: String?
    var outcomeName: String?
    var bookmaker: String?
    var targetValue: Double
    var currentValue: Double?
    var direction: String       // "above" or "below"
    var commenceTime: String?

    enum CodingKeys: String, CodingKey {
        case alertType = "alert_type"
        case ticker
        case companyName = "company_name"
        case sport
        case eventId = "event_id"
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case homeLogo = "home_logo"
        case awayLogo = "away_logo"
        case market
        case outcomeName = "outcome_name"
        case bookmaker
        case targetValue = "target_value"
        case currentValue = "current_value"
        case direction
        case commenceTime = "commence_time"
    }
}

struct StockPrice: Codable {
    let ticker: String
    let price: Double
    let currency: String
    let previousClose: Double?

    enum CodingKeys: String, CodingKey {
        case ticker, price, currency
        case previousClose = "previous_close"
    }
}
