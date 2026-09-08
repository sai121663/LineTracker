import SwiftUI

struct SportOption: Identifiable {
    let key: String
    let label: String
    let espnLeague: String
    var id: String { key }
}

private let allSports: [SportOption] = [
    SportOption(key: "basketball_nba", label: "NBA", espnLeague: "nba"),
    SportOption(key: "americanfootball_nfl", label: "NFL", espnLeague: "nfl"),
    SportOption(key: "icehockey_nhl", label: "NHL", espnLeague: "nhl"),
    SportOption(key: "baseball_mlb", label: "MLB", espnLeague: "mlb"),
    SportOption(key: "soccer_mls", label: "MLS", espnLeague: "mls"),
]

private let stepLabels = ["Sport", "Game", "Team", "Alert"]

/// Port of BetSearch.jsx's step wizard (moneyline/h2h only — that's the
/// only market the web UI actually exposes a picker for), styled to
/// match the web app's dark theme instead of a plain iOS List: the step
/// pills, sport grid, date-grouped game list, bookmaker-grouped outcome
/// list, and the bet-result + target-odds slider all mirror the web
/// layout as closely as SwiftUI allows.
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
    @State private var oddsInput = ""
    @State private var minOdds: Int = -2000
    @State private var maxOdds: Int = 2000
    @State private var saving = false
    @State private var saveError: String?

    private var direction: String {
        guard let chosenOutcome, let price = chosenOutcome.price else { return "above" }
        return targetOdds >= price ? "above" : "below"
    }

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    stepsIndicator

                    switch step {
                    case 0: sportStep
                    case 1: gameStep
                    case 2: outcomeStep
                    default: targetStep
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toolbarBackground(Color.ltBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if activeSports.isEmpty { await loadActiveSports() }
        }
    }

    // MARK: - Header / steps

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Track a betting line")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.ltTextPrimary)
            Text("Pick your bet, set a target, get an email when the odds move.")
                .font(.system(size: 14))
                .foregroundStyle(Color.ltTextSecondary)
        }
    }

    private var stepsIndicator: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(stepLabels.enumerated()), id: \.offset) { index, label in
                    stepPill(index: index, label: label)
                }
            }
        }
    }

    private func stepPill(index: Int, label: String) -> some View {
        let isActive = index == step
        let isDone = index < step
        let fg: Color = isActive ? Color.ltAccent : (isDone ? Color.ltSuccess : Color.ltTextTertiary)
        let bg: Color = isActive ? Color.ltAccentDim : Color.ltSurface
        let border: Color = isActive ? Color.ltAccent : (isDone ? Color.ltSuccessDim : Color.ltBorder)
        let numBg: Color = isActive ? Color.ltAccent : (isDone ? Color.ltSuccessDim : Color.ltSurfaceRaised)
        let numFg: Color = isActive ? Color.white : (isDone ? Color.ltSuccess : Color.ltTextPrimary)

        return HStack(spacing: 6) {
            Text(isDone ? "✓" : "\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .frame(width: 16, height: 16)
                .background(numBg, in: Circle())
                .foregroundStyle(numFg)
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(fg)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(bg)
        .overlay(Capsule().stroke(border, lineWidth: 1))
        .clipShape(Capsule())
    }

    private var loadingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Color.ltAccent)
            Text("LOADING...")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color.ltAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func teamLogo(_ urlString: String?, size: CGFloat = 18) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                RemoteImage(url: url) { image in
                    image.resizable().scaledToFit()
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            }
        }
    }

    private func bookmakerSidebar(_ name: String) -> some View {
        VStack(spacing: 6) {
            if let domain = bookmakerDomains[name],
               let url = URL(string: "https://img.logo.dev/\(domain)?token=\(Config.logoDevToken)") {
                RemoteImage(url: url) { image in
                    image.resizable().scaledToFit()
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text(name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.ltTextPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 100)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color.ltSurfaceRaised)
    }

    private var backButton: some View {
        Button {
            goBack()
        } label: {
            Text("⬅️ Back")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Color.ltTextPrimary)
        .foregroundStyle(Color.ltBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.top, 4)
    }

    // MARK: - Step 0: sport

    private var sportStep: some View {
        Group {
            if loadingSports {
                loadingIndicator
            } else if activeSports.isEmpty {
                Text("No active sports found right now.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ltTextSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(activeSports, id: \.sport.id) { entry in
                        Button {
                            Task { await selectSport(entry.sport) }
                        } label: {
                            VStack(spacing: 8) {
                                if let url = URL(string: "https://a.espncdn.com/i/teamlogos/leagues/500/\(entry.sport.espnLeague).png") {
                                    RemoteImage(url: url) { image in
                                        image.resizable().scaledToFit()
                                    }
                                    .frame(width: 24, height: 24)
                                }
                                Text(entry.sport.label)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.ltTextPrimary)
                                Text("\(entry.count) games")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.ltTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                        .buttonStyle(.plain)
                        .background(Color.ltSurface)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ltBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    // MARK: - Step 1: game

    private struct EventGroup: Identifiable {
        let date: String
        let events: [OddsEvent]
        var id: String { date }
    }

    private var groupedEvents: [EventGroup] {
        var order: [String] = []
        var buckets: [String: [OddsEvent]] = [:]
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        for e in events {
            let label = e.commenceDate.map { fmt.string(from: $0) } ?? "Date unknown"
            if buckets[label] == nil {
                buckets[label] = []
                order.append(label)
            }
            buckets[label]?.append(e)
        }
        return order.map { EventGroup(date: $0, events: buckets[$0] ?? []) }
    }

    private var gameStep: some View {
        Group {
            if loadingEvents {
                loadingIndicator
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if let loadError {
                        Text(loadError)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ltDanger)
                    }
                    if events.isEmpty && loadError == nil {
                        Text("No games found for \(sport?.label ?? "this sport") right now — try another sport.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ltTextSecondary)
                    }

                    ForEach(groupedEvents) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.date.uppercased())
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Color.ltTextSecondary)

                            VStack(spacing: 8) {
                                ForEach(group.events) { e in
                                    eventCard(e)
                                }
                            }
                        }
                    }

                    backButton
                }
            }
        }
    }

    private func eventCard(_ e: OddsEvent) -> some View {
        let isLive = (e.commenceDate ?? .distantFuture) <= Date()
        return Button {
            selectEvent(e)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    teamLogo(e.homeLogo)
                    Text(e.homeTeam)
                    Text("vs")
                        .foregroundStyle(Color.ltTextSecondary)
                    teamLogo(e.awayLogo)
                    Text(e.awayTeam)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ltTextPrimary)
                .lineLimit(1)

                Spacer(minLength: 8)

                if isLive {
                    Text("LIVE")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.ltDanger, in: Capsule())
                        .foregroundStyle(.white)
                } else if let date = e.commenceDate {
                    Text(date, style: .time)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.ltSurfaceRaised)
                        .overlay(Capsule().stroke(Color.ltBorderBright, lineWidth: 1))
                        .foregroundStyle(Color.ltTextPrimary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(isLive ? Color.ltDangerDim : Color.ltSuccessDim)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isLive ? Color.ltDanger : Color.ltSuccessDim, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func selectEvent(_ e: OddsEvent) {
        event = e
        step = 2
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(outcomeChoices.keys.sorted()), id: \.self) { bookmaker in
                bookmakerCard(bookmaker: bookmaker, outcomes: outcomeChoices[bookmaker] ?? [])
            }
            backButton
        }
    }

    private func bookmakerCard(bookmaker: String, outcomes: [OutcomeChoice]) -> some View {
        HStack(spacing: 0) {
            bookmakerSidebar(bookmaker)

            Rectangle().fill(Color.ltBorder).frame(width: 1)

            VStack(spacing: 0) {
                ForEach(Array(outcomes.enumerated()), id: \.offset) { index, o in
                    Button {
                        selectOutcome(o)
                    } label: {
                        HStack(spacing: 8) {
                            teamLogo(o.logo)
                            Text(o.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.ltTextPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Formatting.odds(o.price))
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.ltAccent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if index < outcomes.count - 1 {
                        Rectangle().fill(Color.ltBorder).frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ltSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ltBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func selectOutcome(_ choice: OutcomeChoice) {
        chosenOutcome = choice
        let price = choice.price ?? 100
        targetOdds = price
        oddsInput = Formatting.odds(price)
        minOdds = Formatting.addPoints(price, -2000)
        maxOdds = Formatting.addPoints(price, 2000)
        saveError = nil
        step = 3
    }

    // MARK: - Step 3: target & save

    private var targetStep: some View {
        Group {
            if let chosenOutcome, let event {
                VStack(alignment: .leading, spacing: 20) {
                    betResultCard(chosenOutcome, event)
                    targetForm(outcome: chosenOutcome, event: event)
                    backButton
                }
            }
        }
    }

    private func betResultCard(_ outcome: OutcomeChoice, _ event: OddsEvent) -> some View {
        let opponentName = outcome.name == event.homeTeam ? event.awayTeam : event.homeTeam
        let opponentLogo = outcome.name == event.homeTeam ? event.awayLogo : event.homeLogo

        return HStack(spacing: 0) {
            bookmakerSidebar(outcome.bookmaker)

            Rectangle().fill(Color.ltBorder).frame(width: 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    teamLogo(outcome.logo, size: 22)
                    Text(outcome.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ltTextPrimary)
                }
                HStack(spacing: 4) {
                    Text("vs")
                        .foregroundStyle(Color.ltTextSecondary)
                    teamLogo(opponentLogo)
                    Text(opponentName)
                        .foregroundStyle(Color.ltTextPrimary)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 13))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Spacer(minLength: 8)

            Text(Formatting.odds(outcome.price))
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ltAccent)
                .padding(.trailing, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ltSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ltBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func targetForm(outcome: OutcomeChoice, event: OddsEvent) -> some View {
        let currentOdds = outcome.price ?? 100
        let isAbove = targetOdds >= currentOdds
        let sliderColor = isAbove ? Color.ltSuccess : Color.ltDanger

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Target odds:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ltTextSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Text(isAbove ? "▲" : "▼")
                    Text(Formatting.odds(targetOdds))
                }
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(sliderColor)
            }

            HStack(spacing: 10) {
                Text("Or type odds:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ltTextSecondary)
                TextField("odds", text: $oddsInput)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Color.ltTextPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: 110)
                    .background(Color.ltBackground)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.ltBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .onChange(of: oddsInput) { _, newValue in
                        guard let val = Int(newValue) else { return }
                        guard !(val > -100 && val < 100) else { return }
                        guard val >= minOdds && val <= maxOdds else { return }
                        targetOdds = val
                    }
                Spacer()
            }

            VStack(spacing: 8) {
                GradientSlider(
                    value: Binding(
                        get: { Formatting.toSliderPosition(odds: targetOdds, min: minOdds, max: maxOdds) },
                        set: { raw in
                            let odds = Formatting.fromSliderPosition(raw, min: minOdds, max: maxOdds)
                            targetOdds = odds
                            oddsInput = Formatting.odds(odds)
                        }
                    ),
                    range: 0...200,
                    current: Formatting.toSliderPosition(odds: currentOdds, min: minOdds, max: maxOdds)
                )
                HStack {
                    Text(Formatting.odds(minOdds))
                        .foregroundStyle(Color.ltTextTertiary)
                    Spacer()
                    Text("Current: \(Formatting.odds(currentOdds))")
                        .foregroundStyle(Color.ltTextSecondary)
                    Spacer()
                    Text(Formatting.odds(maxOdds))
                        .foregroundStyle(Color.ltTextTertiary)
                }
                .font(.system(size: 11, design: .monospaced))
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ltDanger)
            }

            Button {
                Task { await save(event: event, outcome: outcome) }
            } label: {
                Text(saving ? "Saving…" : "Set alert")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .background(Color.ltAccent)
            .foregroundStyle(Color(hex: 0x1A1304))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(saving ? 0.6 : 1)
            .disabled(saving)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ltSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ltBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            resetToDefault()
            onSaved()
        } catch {
            saveError = (error as? APIClient.APIError)?.errorDescription ?? "Could not save the alert. Try again."
            saving = false
        }
    }

    /// Same idea as StockSearchView's resetToDefault(): SwiftUI keeps
    /// this tab's view alive across tab switches, so without this the
    /// wizard would still be sitting on step 3 (or wherever it was)
    /// the next time the Bets tab is opened.
    private func resetToDefault() {
        step = 0
        sport = nil
        events = []
        loadError = nil
        event = nil
        chosenOutcome = nil
        targetOdds = 0
        oddsInput = ""
        saveError = nil
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
