import Foundation

enum Formatting {
    /// American odds display: "+150" / "-110" / "—" for nil.
    static func odds(_ price: Double?) -> String {
        guard let price else { return "—" }
        return price > 0 ? "+\(Int(price))" : "\(Int(price))"
    }

    static func odds(_ price: Int?) -> String {
        guard let price else { return "—" }
        return price > 0 ? "+\(price)" : "\(price)"
    }

    static func dollars(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "$%.2f", value)
    }

    /// Ports BetSearch.jsx's addPoints(): walks American odds "points"
    /// away from a starting value, correctly stepping over the dead zone
    /// between -99 and +99 that American odds never actually use. Used
    /// to build the ±2000-point slider range around the odds you picked.
    static func addPoints(_ odds: Int, _ points: Int) -> Int {
        if points >= 0 {
            if odds >= 100 { return odds + points }
            let toEdge = -odds - 100
            if points <= toEdge { return odds + points }
            let remaining = points - toEdge
            return 100 + remaining
        } else {
            let absPoints = abs(points)
            if odds <= -100 { return odds - absPoints }
            let toEdge = odds - 100
            if absPoints <= toEdge { return odds - absPoints }
            let remaining = absPoints - toEdge
            return -100 - remaining
        }
    }

    /// American-odds-to-linear and back, so a plain SwiftUI Slider (which
    /// only understands a continuous range) can move through odds values
    /// while still skipping the -99...+99 dead zone — same trick as
    /// BetSearch.jsx's oddsToLinear/toSlider/fromSlider.
    static func oddsToLinear(_ odds: Int) -> Int { odds >= 100 ? odds - 200 : odds }

    static func toSliderPosition(odds: Int, min minOdds: Int, max maxOdds: Int) -> Double {
        let linear = Double(oddsToLinear(odds))
        let minLinear = Double(oddsToLinear(minOdds))
        let maxLinear = Double(oddsToLinear(maxOdds))
        guard maxLinear != minLinear else { return 0 }
        return ((linear - minLinear) / (maxLinear - minLinear)) * 200
    }

    static func fromSliderPosition(_ raw: Double, min minOdds: Int, max maxOdds: Int) -> Int {
        let minLinear = Double(oddsToLinear(minOdds))
        let maxLinear = Double(oddsToLinear(maxOdds))
        let linear = Int((minLinear + (raw / 200) * (maxLinear - minLinear)).rounded())
        if linear > -100 && linear < 100 { return linear >= 0 ? 100 : -100 }
        return linear >= 100 ? linear + 200 : linear
    }

    /// Port of Dashboard.jsx's alertDateLine(): "Sep 7, Created @ 6:03 PM"
    /// for a stock (or a bet whose game already started / has no
    /// commence_time), "Sep 7, Starts @ 7:10 PM" for a bet later today,
    /// "Sep 7, Scheduled for Sep 9" for one further out.
    static func alertDateLine(createdAt: String?, commenceTime: String?, isStock: Bool) -> String? {
        guard let createdAt, let created = parseUTCNaive(createdAt) else { return nil }

        let dateFmt = DateFormatter()
        dateFmt.setLocalizedDateFormatFromTemplate("MMMd")
        let timeFmt = DateFormatter()
        timeFmt.setLocalizedDateFormatFromTemplate("hm")

        let createdLine = "\(dateFmt.string(from: created)), Created @ \(timeFmt.string(from: created))"

        if isStock { return createdLine }

        guard let commenceTime, let commenceDate = parseISO(commenceTime) else { return createdLine }

        if commenceDate <= Date() { return createdLine }

        if Calendar.current.isDate(commenceDate, inSameDayAs: Date()) {
            return "\(dateFmt.string(from: created)), Starts @ \(timeFmt.string(from: commenceDate))"
        }

        return "\(dateFmt.string(from: created)), Scheduled for \(dateFmt.string(from: commenceDate))"
    }

    /// backend/models.py stores created_at as a naive UTC datetime
    /// (datetime.utcnow().isoformat(), no "Z"/offset) — same as
    /// Dashboard.jsx appending "Z" itself before parsing.
    private static func parseUTCNaive(_ iso: String) -> Date? {
        parseISO(iso + "Z")
    }

    private static func parseISO(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: iso) { return date }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    static func relativeDate(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? {
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: iso)
        }()
        guard let date else { return nil }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
