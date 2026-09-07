import SwiftUI

struct SportOption: Identifiable {
    let key: String
    let label: String
    var id: String { key }
}

private let allSports: [SportOption] = [
    SportOption(key: "basketball_nba", label: "NBA"),
    SportOption(key: "americanfootball_nfl", label: "NFL"),
    SportOption(key: "icehockey_nhl", label: "NHL"),
    SportOption(key: "baseball_mlb", label: "MLB"),
    SportOption(key: "soccer_mls", label: "MLS"),
]

/// Port of BetSearch.jsx's step wizard (moneyline/h2h only — that's the
/// only market the current web UI actually exposes a picker for).
/// Steps: 0 Sport -> 1 Game -> 2 Team/outcome -> 3 Set target & save.
struct BetSearchView: View {
    var onSaved: () -> Void = {}

    @State private var step = 0

    @State private var activeSports: [(sport: SportOption, count: Int)] = []
    @State private var loadingSports = true

    @State private var sport: SportOption?
    @State private var events: [OddsEvent] = []
    @State private var loadingEvents = false
    @State private var loadError: String?

    @State private var event: OddsEvent?
    @State private var chosenOutcome: OutcomeChoice?

    @State private var targetOdds: Int = 0
    @State private var minOdds: Int = -2000
    @State private var maxOdds: Int = 2000
    @State private var saving = false
    @State private var saveError: String?

    private var direction: String {
        guard let chosenOutcome, let price = chosenOutcome.price else { return "above" }
        return targetOdds >= price ? "above" : "below"
    }

    var body: some View {
        List {
            switch step {
            case 0: sportStep
            case 1: gameStep
            case 2: outcomeStep
            default: targetStep
            }
        }
        .navigationTitle("Track a betting line")
        .toolbar {
            if step > 0 {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { goBack() }
                }
            }
        }
        .task {
            if activeSports.isEmpty { await loadActiveSports() }
        }
    }

    // MARK: - Step 0: sport

    private var sportStep: some View {
        Section("Pick a sport") {
            if loadingSports {
                ProgressView("Loading…")
            } else if activeSports.isEmpty {
                Text("No active sports found right now.").foregroundStyle(.secondary)
            } else {
                ForEach(activeSports, id: \.sport.id) { entry in
                    Button {
                        Task { await selectSport(entry.sport) }
                    } label: {
                        HStack {
                            Text(entry.sport.label)
                            Spacer()
                            Text("\(entry.count) games").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func loadActiveSports() async {
        loadingSports = true
        var results: [(SportOption, Int)] = []
        await withTaskGroup(of: (SportOption, Int)?.self) { group in
            for s in allSports {
                group.addTask {
                    guard let resp = try? await APIClient.shared.getOdds(sport: s.key, market: "h2h") else { return nil }
                    return resp.events.isEmpty ? nil : (s, resp.events.count)
                }
            }
            for await result in group {
                if let result { results.append(result) }
            }
        }
        activeSports = results.sorted { $0.1 > $1.1 }
        loadingSports = false
    }

    // MARK: - Step 1: game

    private var gameStep: some View {
        Group {
            if loadingEvents {
                ProgressView("Loading…")
            } else if let loadError {
                Text(loadError).foregroundStyle(.red)
            } else if events.isEmpty {
                Text("No games found for \(sport?.label ?? "this sport") right now.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { e in
                    Button {
                        event = e
                        step = 2
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(e.homeTeam) vs \(e.awayTeam)")
                                if let date = e.commenceDate {
                                    HStack(spacing: 4) {
                                        Text(date, style: .date)
                                        Text("·")
                                        Text(date, style: .time)
                                    }
                                }
                            }
                            .font(.subheadline)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func selectSport(_ s: SportOption) async {
        sport = s
        step = 1
        loadingEvents = true
        loadError = nil
        do {
            let resp = try await APIClient.shared.getOdds(sport: s.key, market: "h2h")
            events = resp.events
        } catch {
            loadError = "Could not load games for this sport. Try another."
        }
        loadingEvents = false
    }

    // MARK: - Step 2: outcome

    private var outcomeChoices: [String: [OutcomeChoice]] {
        guard let event else { return [:] }
        var grouped: [String: [OutcomeChoice]] = [:]
        for bm in event.bookmakers {
            guard let mkt = bm.markets.first(where: { $0.key == "h2h" }) else { continue }
            for o in mkt.outcomes {
                if sport?.key == "icehockey_nhl", o.name.trimmingCharacters(in: .whitespaces).lowercased() == "tie" {
                    continue
                }
                grouped[bm.title, default: []].append(OutcomeChoice(name: o.name, price: o.price, bookmaker: bm.title, logo: o.logo))
            }
        }
        return grouped
    }

    private var outcomeStep: some View {
        ForEach(Array(outcomeChoices.keys.sorted()), id: \.self) { bookmaker in
            Section(bookmaker) {
                ForEach(outcomeChoices[bookmaker] ?? []) { choice in
                    Button {
                        selectOutcome(choice)
                    } label: {
                        HStack {
                            Text(choice.name)
                            Spacer()
                            Text(Formatting.odds(choice.price)).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func selectOutcome(_ choice: OutcomeChoice) {
        chosenOutcome = choice
        let price = choice.price ?? 100
        targetOdds = price
        minOdds = Formatting.addPoints(price, -2000)
        maxOdds = Formatting.addPoints(price, 2000)
        saveError = nil
        step = 3
    }

    // MARK: - Step 3: target & save

    private var opponent: String? {
        guard let event, let chosenOutcome else { return nil }
        return chosenOutcome.name == event.homeTeam ? event.awayTeam : event.homeTeam
    }

    private var targetStep: some View {
        Group {
            if let chosenOutcome, let event {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chosenOutcome.bookmaker).font(.caption).foregroundStyle(.secondary)
                        Text(chosenOutcome.name).font(.headline)
                        if let opponent {
                            Text("vs \(opponent)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(Formatting.odds(chosenOutcome.price)).font(.title3.monospacedDigit())
                    }
                }

                Section("Set target odds") {
                    HStack {
                        Text(direction == "above" ? "▲" : "▼")
                            .foregroundStyle(direction == "above" ? .green : .red)
                        Text(Formatting.odds(targetOdds))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(direction == "above" ? .green : .red)
                    }
                    Slider(
                        value: Binding(
                            get: { Formatting.toSliderPosition(odds: targetOdds, min: minOdds, max: maxOdds) },
                            set: { targetOdds = Formatting.fromSliderPosition($0, min: minOdds, max: maxOdds) }
                        ),
                        in: 0...200
                    )
                    HStack {
                        Text(Formatting.odds(minOdds)).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("Current: \(Formatting.odds(chosenOutcome.price))").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatting.odds(maxOdds)).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Or type odds:")
                        TextField("odds", value: $targetOdds, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let saveError { Text(saveError).foregroundStyle(.red).font(.footnote) }

                Section {
                    Button(saving ? "Saving…" : "Set alert") { Task { await save(event: event, outcome: chosenOutcome) } }
                        .disabled(saving)
                }
            }
        }
    }

    private func save(event: OddsEvent, outcome: OutcomeChoice) async {
        guard let sport else { return }
        saving = true
        saveError = nil
        do {
            _ = try await APIClient.shared.createAlert(NewAlertRequest(
                alertType: "Bet 🎟️",
                ticker: nil, companyName: nil,
                sport: sport.key,
                eventId: event.id,
                homeTeam: event.homeTeam,
                awayTeam: event.awayTeam,
                homeLogo: event.homeLogo ?? "",
                awayLogo: event.awayLogo ?? "",
                market: "h2h",
                outcomeName: outcome.name,
                bookmaker: outcome.bookmaker,
                targetValue: Double(targetOdds),
                currentValue: outcome.price.map(Double.init),
                direction: direction,
                commenceTime: event.commenceTime
            ))
            saving = false
            onSaved()
        } catch {
            saveError = (error as? APIClient.APIError)?.errorDescription ?? "Could not save the alert. Try again."
            saving = false
        }
    }

    private func goBack() {
        switch step {
        case 1: step = 0; sport = nil; events = []
        case 2: step = 1; event = nil
        case 3: step = 2; chosenOutcome = nil
        default: break
        }
    }
}

#Preview {
    NavigationStack { BetSearchView() }
}
