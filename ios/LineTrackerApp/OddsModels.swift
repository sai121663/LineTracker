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

    /// Best-effort parse of commence_time. Uses Formatting.parseFlexibleISO
    /// rather than a bare ISO8601DateFormatter because SharpAPI's
    /// event_start_time isn't guaranteed to carry a "Z"/offset the way
    /// ISO8601DateFormatter strictly requires (see that function's doc
    /// comment) — a naive timestamp here used to make every game's date
    /// fail to parse and fall back to "Date unknown".
    var commenceDate: Date? {
        guard let commenceTime else { return nil }
        return Formatting.parseFlexibleISO(commenceTime)
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
