import SwiftUI

/// Port of Dashboard.jsx + Dashboard.css — same dark theme, same card
/// layout (team/bookmaker logos, Set At -> Target pills, date line) as
/// the web dashboard, instead of a default system List.
struct DashboardView: View {
    @EnvironmentObject var auth: AuthManager
    var onAddStock: () -> Void = {}
    var onAddBet: () -> Void = {}
    @State private var alerts: [Alert] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var showSettings = false

    // Bell icon: mirrors what a push notification would have told you,
    // without needing the Apple Developer Program setup push needs. Only
    // shown when the user has actually turned Push on in Settings (same
    // @AppStorage key SettingsView writes to) -- if they don't want to be
    // notified, there's no reason to add a second inbox for it.
    @AppStorage("lt_wantsPush") private var wantsPush = false
    @AppStorage("lt_lastBellCheck") private var lastBellCheckInterval: Double = 0
    @State private var recentTriggered: [Alert] = []
    @State private var showBell = false

    private var lastBellCheck: Date { Date(timeIntervalSince1970: lastBellCheckInterval) }

    private var unseenTriggeredCount: Int {
        recentTriggered.filter { alert in
            guard let iso = alert.triggeredAt, let date = Formatting.parseFlexibleISO(iso) else { return false }
            return date > lastBellCheck
        }.count
    }

    private var active: [Alert] { alerts.filter { !$0.triggered } }

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if loading {
                        ProgressView("Loading alerts…")
                            .tint(Color.ltAccent)
                            .foregroundStyle(Color.ltTextSecondary)
                            .frame(maxWidth: .infinity)
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "Couldn't load alerts",
                            systemImage: "wifi.slash",
                            description: Text(errorMessage)
                        )
                        .foregroundStyle(Color.ltTextPrimary)
                        .frame(maxWidth: .infinity)
                    } else if alerts.isEmpty {
                        ContentUnavailableView(
                            "No alerts yet",
                            systemImage: "bell.slash",
                            description: Text("Track a stock's price or a betting line — you'll get an email the moment it crosses your target.")
                        )
                        .foregroundStyle(Color.ltTextPrimary)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Text("ACTIVE")
                                    .font(.system(size: 13, weight: .semibold))
                                    .tracking(1.2)
                                    .foregroundStyle(Color.ltTextSecondary)
                                Text("\(active.count)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.ltTextPrimary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(Color.ltSurfaceRaised, in: Capsule())
                            }

                            LazyVStack(spacing: 10) {
                                ForEach(active) { alert in
                                    AlertCard(alert: alert, onDelete: { delete(alert) })
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await load() }
        }
        // The title is drawn as ordinary content above (the `header`
        // view), same as StockSearchView's "Track a stock" — not the
        // system's automatic large title. A NavigationStack's large
        // title inside a TabView + toolbarBackground combo like this
        // one has a well-known rendering glitch where it silently
        // fails to draw on some appearances ("Your Alerts" going
        // blank); drawing it ourselves sidesteps that entirely.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ltBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if wantsPush {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBell = true
                        lastBellCheckInterval = Date().timeIntervalSince1970
                    } label: {
                        Image(systemName: unseenTriggeredCount > 0 ? "bell.badge.fill" : "bell")
                            .foregroundStyle(Color.ltTextPrimary)
                            .overlay(alignment: .topTrailing) {
                                if unseenTriggeredCount > 0 {
                                    Text("\(min(unseenTriggeredCount, 9))\(unseenTriggeredCount > 9 ? "+" : "")")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .background(Color.ltDanger, in: Circle())
                                        .offset(x: 9, y: -8)
                                }
                            }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.ltTextPrimary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showBell) {
            NavigationStack { RecentAlertsView(alerts: recentTriggered) }
        }
        .task {
            await load()
            if wantsPush { await loadRecentTriggered() }
        }
        .onChange(of: wantsPush) { _, isOn in
            if isOn { Task { await loadRecentTriggered() } }
        }
    }

    // Port of Dashboard.jsx's .dashboard-head: title on the leading edge,
    // "+ Stock" / "+ Bet" quick-add buttons on the trailing edge.
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Your Alerts")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.ltTextPrimary)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button(action: onAddStock) {
                    Text("+ Stock")
                }
                .buttonStyle(DashboardActionButtonStyle(kind: .ghost))

                Button(action: onAddBet) {
                    Text("+ Bet")
                }
                .buttonStyle(DashboardActionButtonStyle(kind: .primary))
            }
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            alerts = try await APIClient.shared.getAlerts()
        } catch {
            errorMessage = "Could not reach the backend. Is it running?"
        }
        loading = false
    }

    private func loadRecentTriggered() async {
        recentTriggered = (try? await APIClient.shared.getRecentTriggeredAlerts()) ?? recentTriggered
    }

    private func delete(_ alert: Alert) {
        alerts.removeAll { $0.id == alert.id }
        Task { try? await APIClient.shared.deleteAlert(id: alert.id) }
    }
}

// MARK: - Alert card

/// Same lookup Dashboard.jsx's BOOKMAKER_DOMAINS uses, so the same
/// bookmakers resolve to the same logos on both platforms.
let bookmakerDomains: [String: String] = [
    "Draftkings": "draftkings.com",
    "FanDuel": "fanduelracing.com",
    "BetMGM": "betmgm.com",
    "BetRivers": "betrivers.com",
    "Bovada": "bovada.lv",
    "MyBookie.ag": "mybookie.ag",
    "BetOnline.ag": "betonline.ag",
    "LowVig.ag": "lowvig.ag",
    "BetUS": "betus.com.pa",
    "Caesars": "caesars.com",
    "PointsBet": "pointsbet.com",
    "Unibet": "unibet.com",
    "bet365": "bet365.com",
    "William Hill": "williamhill.com",
    "Betway": "betway.com",
    "Hard Rock Bet": "hardrock.com",
]

private struct AlertCard: View {
    let alert: Alert
    let onDelete: () -> Void

    private var isStock: Bool { alert.alertType == "Stock 🌱" }
    private var isAbove: Bool { alert.direction == "above" }

    private var title: String {
        isStock ? (alert.ticker ?? "—") : (alert.outcomeName ?? "\(alert.homeTeam ?? "") vs \(alert.awayTeam ?? "")")
    }

    private var opponentName: String? {
        guard !isStock, let home = alert.homeTeam, let away = alert.awayTeam else { return nil }
        return alert.outcomeName == home ? away : home
    }

    private var opponentLogoURL: URL? {
        guard !isStock, let home = alert.homeTeam else { return nil }
        let logo = alert.outcomeName == home ? alert.awayLogo : alert.homeLogo
        return logo.flatMap(URL.init(string:))
    }

    /// The big leading logo: the outcome's own team crest for a bet, the
    /// ticker's logo (via Logokit) for a stock — same as alert-team-logo.
    private var leadingLogoURL: URL? {
        if isStock, let ticker = alert.ticker {
            return URL(string: "https://img.logo.dev/ticker/\(ticker)?token=\(Config.logoDevToken)")
        }
        guard let home = alert.homeTeam else { return nil }
        let logo = alert.outcomeName == home ? alert.homeLogo : alert.awayLogo
        return logo.flatMap(URL.init(string:))
    }

    private var setValue: String {
        isStock ? Formatting.dollars(alert.currentValue) : Formatting.odds(alert.currentValue)
    }

    private var targetValueText: String {
        isStock ? Formatting.dollars(alert.targetValue) : Formatting.odds(alert.targetValue)
    }

    private var dateLine: String? {
        Formatting.alertDateLine(createdAt: alert.createdAt, commenceTime: alert.commenceTime, isStock: isStock)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                if let leadingLogoURL {
                    RemoteImage(url: leadingLogoURL) { image in
                        image.resizable().scaledToFit()
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    // Nudge down from the top of the card so the logo
                    // sits beside the ticker/company lines instead of
                    // the "Stock" type row above them.
                    .padding(.top, 18)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(alert.alertType)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Color(hex: 0x5EA8FF))

                        if isStock, let live = alert.liveValue {
                            LiveBadge(text: Formatting.dollars(live))
                        } else if let bookmaker = alert.bookmaker {
                            BookmakerBadge(bookmaker: bookmaker, domain: bookmakerDomains[bookmaker])
                        }
                    }

                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ltTextPrimary)
                        .lineLimit(1)

                    if isStock {
                        Text(alert.companyName ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ltTextSecondary)
                            .lineLimit(1)
                    } else if let opponentName {
                        HStack(spacing: 4) {
                            Text("vs")
                            if let opponentLogoURL {
                                RemoteImage(url: opponentLogoURL) { image in
                                    image.resizable().scaledToFit()
                                }
                                .frame(width: 14, height: 14)
                                .clipShape(Circle())
                            }
                            Text(opponentName)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ltTextSecondary)
                        .lineLimit(1)
                    } else {
                        Text("Bet")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ltTextSecondary)
                    }

                    if let dateLine {
                        Text(dateLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.ltTextTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ltTextTertiary)
                }
                .buttonStyle(.plain)
            }

            // Set At -> Target, centered as its own row instead of
            // squeezed onto the same line as the title on a phone-width
            // screen (that's what was crushing "San Diego Padres" down
            // to "San Diego P...").
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 0)
                PillGroup(label: "Set at", value: setValue, style: .neutral)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isAbove ? Color.ltSuccess : Color.ltDanger)
                    .padding(.bottom, 10)
                PillGroup(label: "Target", value: targetValueText, style: isAbove ? .success : .danger)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ltSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ltBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Pieces

private enum PillStyle {
    case neutral, success, danger
}

private struct PillGroup: View {
    let label: String
    let value: String
    let style: PillStyle

    private var background: Color {
        switch style {
        case .neutral: return Color.ltSurfaceRaised
        case .success: return Color.ltSuccessDim
        case .danger: return Color.ltDangerDim
        }
    }
    private var border: Color {
        switch style {
        case .neutral: return Color.ltBorderBright
        case .success: return Color.ltSuccess
        case .danger: return Color.ltDanger
        }
    }
    private var textColor: Color {
        switch style {
        case .neutral: return Color.ltTextPrimary
        case .success: return Color.ltSuccess
        case .danger: return Color.ltDanger
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.ltTextPrimary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .frame(minWidth: 90)
                .background(background, in: Capsule())
                .overlay(Capsule().stroke(border, lineWidth: 1))
        }
    }
}

private struct LiveBadge: View {
    let text: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.ltSuccess)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.6 : 1)
                .opacity(pulse ? 0 : 1)
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
                .onAppear { pulse = true }
            Text(text)
                .tracking(0.3)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color.ltSuccess)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.ltSuccessDim, in: Capsule())
        .fixedSize()
    }
}

/// Same fallback behavior as web's BookmakerBadge: show the bookmaker's
/// logo when we know its domain and the image actually loads, otherwise
/// fall back to a plain initial badge instead of no icon at all.
private struct BookmakerBadge: View {
    let bookmaker: String
    let domain: String?

    var body: some View {
        HStack(spacing: 5) {
            if let domain, let url = URL(string: "https://img.logo.dev/\(domain)?token=\(Config.logoDevToken)") {
                RemoteImage(url: url) { image in
                    image.resizable().scaledToFit()
                } fallback: {
                    initialBadge
                }
                .frame(width: 12, height: 12)
                .clipShape(Circle())
            } else {
                initialBadge
            }
            Text(bookmaker)
                .tracking(0.3)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color.ltTextSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.ltSurfaceRaised, in: Capsule())
        .overlay(Capsule().stroke(Color.ltBorderBright, lineWidth: 1))
        .fixedSize()
    }

    private var initialBadge: some View {
        Circle()
            .fill(Color.ltBorderBright)
            .frame(width: 12, height: 12)
            .overlay(
                Text(bookmaker.prefix(1).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.ltTextSecondary)
            )
    }
}

/// Thin AsyncImage wrapper: renders nothing (rather than a broken-image
/// placeholder) while loading or on failure, same as the web app's
/// onError={() => element hides itself}. An optional fallback view is
/// shown on failure instead, for spots (like BookmakerBadge) that want
/// one.
struct RemoteImage<Content: View, Fallback: View>: View {
    let url: URL
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let fallback: () -> Fallback

    init(
        url: URL,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder fallback: @escaping () -> Fallback = { EmptyView() }
    ) {
        self.url = url
        self.content = content
        self.fallback = fallback
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                content(image)
            case .failure:
                fallback()
            default:
                Color.clear
            }
        }
    }
}

/// Ports .btn-primary and .btn-ghost (as BetSearch.css's site-wide
/// override of it — filled light pill, dark text — actually renders,
/// since plain CSS classes aren't scoped per-component) from
/// index.css/Dashboard.css/BetSearch.css.
private struct DashboardActionButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }

    private var background: Color {
        switch kind {
        case .primary: return Color.ltAccent
        case .ghost: return Color.ltTextPrimary
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Color(hex: 0x1A1304)
        case .ghost: return Color.ltBackground
        }
    }
}

#Preview {
    DashboardView().environmentObject(AuthManager())
}
