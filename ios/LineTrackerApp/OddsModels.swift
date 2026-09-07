import Foundation

/// Mirrors the nested JSON shape app.py's /odds route builds:
/// { sport, market, events: [ { id, home_team, away_team, ..., bookmakers: [ { title, markets: [ { key, outcomes: [ { name, price, logo } ] } ] } ] } ] }
struct OddsResponse: Codable {
    let sport: String
    let market: String
    let events: [OddsEvent]
}

struct OddsEvent: Codable, Identifiable {
    let id: String
    let sport: String
    let commenceTime: String?
    let homeTeam: String
    let awayTeam: String
    let homeLogo: String?
    let awayLogo: String?
    let bookmakers: [OddsBookmaker]

    enum CodingKeys: String, CodingKey {
        case id, sport
        case commenceTime = "commence_time"
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case homeLogo = "home_logo"
        case awayLogo = "away_logo"
        case bookmakers
    }

    /// Best-effort parse of commence_time (ISO8601, sometimes with a "Z").
    var commenceDate: Date? {
        guard let commenceTime else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: commenceTime) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: commenceTime)
    }
}

struct OddsBookmaker: Codable {
    let title: String
    let markets: [OddsMarket]
}

struct OddsMarket: Codable {
    let key: String
    let outcomes: [OddsOutcome]
}

struct OddsOutcome: Codable {
    let name: String
    let price: Int?
    let logo: String?
}

/// One flattened, pickable row for the "choose your side" step —
/// equivalent to what getOutcomesForMarket() builds in BetSearch.jsx.
struct OutcomeChoice: Identifiable {
    var id: String { "\(bookmaker)-\(name)-\(price ?? 0)" }
    let name: String
    let price: Int?
    let bookmaker: String
    let logo: String?
}
