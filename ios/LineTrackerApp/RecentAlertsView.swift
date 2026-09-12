import SwiftUI

/// The bell icon's sheet — everything that's fired since the user last
/// opened it (see DashboardView's showBell/lastBellCheckInterval). This
/// is the "mimic a push notification without needing the Apple Developer
/// Program" screen: same data a push would have shown, just pulled from
/// GET /alerts?status=triggered instead of delivered by APNs.
struct RecentAlertsView: View {
    @Environment(\.dismiss) private var dismiss
    let alerts: [Alert]

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            if alerts.isEmpty {
                ContentUnavailableView(
                    "Nothing fired recently",
                    systemImage: "bell.slash",
                    description: Text("You'll see it here the moment one of your alerts hits its target.")
                )
                .foregroundStyle(Color.ltTextPrimary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(alerts) { alert in
                            RecentAlertRow(alert: alert)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Recent Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ltBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.ltTextPrimary)
                }
            }
        }
    }
}

private struct RecentAlertRow: View {
    let alert: Alert

    private var isStock: Bool { alert.alertType == "Stock 🌱" }

    private var title: String {
        isStock ? (alert.ticker ?? "—") : (alert.outcomeName ?? "\(alert.homeTeam ?? "") vs \(alert.awayTeam ?? "")")
    }

    // ABOVE/BELOW called out in caps + color (green/red) so the direction
    // reads at a glance instead of blending into the rest of the line --
    // Text values keep their own .foregroundColor when concatenated with
    // +, even though the row below also sets a default color for the
    // rest of the sentence.
    private var hitText: Text {
        let target = isStock ? Formatting.dollars(alert.targetValue) : Formatting.odds(alert.targetValue)
        let isAbove = alert.direction == "above"
        return Text("Crossed ")
            + Text(isAbove ? "ABOVE" : "BELOW")
                .fontWeight(.bold)
                .foregroundColor(isAbove ? Color.ltSuccess : Color.ltDanger)
            + Text(" \(target)")
    }

    /// Same lookup as AlertCard's leadingLogoURL (DashboardView.swift) --
    /// the ticker's logo via Logokit for a stock, the outcome's own team
    /// crest for a bet.
    private var leadingLogoURL: URL? {
        if isStock, let ticker = alert.ticker {
            return URL(string: "https://img.logo.dev/ticker/\(ticker)?token=\(Config.logoDevToken)")
        }
        guard let home = alert.homeTeam else { return nil }
        let logo = alert.outcomeName == home ? alert.homeLogo : alert.awayLogo
        return logo.flatMap(URL.init(string:))
    }

    private var fallbackIcon: some View {
        Image(systemName: isStock ? "chart.line.uptrend.xyaxis" : "sportscourt.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.ltTextPrimary)
            .frame(width: 30, height: 30)
            .background(Color.ltSurface, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let leadingLogoURL {
            RemoteImage(url: leadingLogoURL) { image in
                image.resizable().scaledToFit()
            } fallback: {
                fallbackIcon
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
        } else {
            fallbackIcon
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ltTextPrimary)
                hitText
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ltTextSecondary)
            }

            Spacer()

            Text(Formatting.timeAgo(alert.triggeredAt))
                .font(.system(size: 12))
                .foregroundStyle(Color.ltTextTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.ltSurfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ltBorder, lineWidth: 1))
    }
}

#Preview {
    NavigationStack { RecentAlertsView(alerts: []) }
}
