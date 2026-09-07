import SwiftUI

/// Port of Dashboard.jsx — list of active alerts with delete.
struct DashboardView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var alerts: [Alert] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading alerts…")
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load alerts", systemImage: "wifi.slash", description: Text(errorMessage))
                } else if alerts.isEmpty {
                    ContentUnavailableView(
                        "No alerts yet",
                        systemImage: "bell.slash",
                        description: Text("Track a stock's price or a betting line — you'll get an email the moment it crosses your target.")
                    )
                } else {
                    List {
                        Section("Active (\(alerts.count))") {
                            ForEach(alerts) { alert in
                                AlertRow(alert: alert)
                            }
                            .onDelete(perform: delete)
                        }
                    }
                }
            }
            .navigationTitle("Your alerts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign out", role: .destructive) { auth.signOut() }
                    } label: {
                        Label(auth.session?.email ?? "", systemImage: "person.crop.circle")
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
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

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { alerts[$0] }
        alerts.remove(atOffsets: offsets)
        Task {
            for alert in toDelete {
                try? await APIClient.shared.deleteAlert(id: alert.id)
            }
        }
    }
}

private struct AlertRow: View {
    let alert: Alert

    private var isStock: Bool { alert.alertType == "Stock 🌱" }

    private var title: String {
        isStock ? (alert.ticker ?? "—") : (alert.outcomeName ?? "\(alert.homeTeam ?? "") vs \(alert.awayTeam ?? "")")
    }

    private var subtitle: String {
        if isStock { return alert.companyName ?? "" }
        guard let home = alert.homeTeam, let away = alert.awayTeam else { return "Bet" }
        let opponent = alert.outcomeName == home ? away : home
        return "vs \(opponent)"
    }

    private var setValue: String {
        isStock ? Formatting.dollars(alert.currentValue) : Formatting.odds(alert.currentValue)
    }

    private var targetValueText: String {
        isStock ? Formatting.dollars(alert.targetValue) : Formatting.odds(alert.targetValue)
    }

    private var isAbove: Bool { alert.direction == "above" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(alert.alertType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isStock, let live = alert.liveValue {
                    Label(Formatting.dollars(live), systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if let bookmaker = alert.bookmaker {
                    Text(bookmaker)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Set at").font(.caption2).foregroundStyle(.secondary)
                    Text(setValue).font(.callout.monospacedDigit())
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(isAbove ? .green : .red)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Target").font(.caption2).foregroundStyle(.secondary)
                    Text(targetValueText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(isAbove ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DashboardView()
}
