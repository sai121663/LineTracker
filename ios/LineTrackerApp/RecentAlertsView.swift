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

    private var hitText: String {
        let target = isStock ? Formatting.dollars(alert.targetValue) : Formatting.odds(alert.targetValue)
        return "Crossed \(alert.direction == "above" ? "above" : "below") \(target)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isStock ? "chart.line.uptrend.xyaxis" : "sportscourt.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ltTextPrimary)
                .frame(width: 30, height: 30)
                .background(Color.ltSurface, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ltTextPrimary)
                Text(hitText)
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
