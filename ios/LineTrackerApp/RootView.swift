import SwiftUI

/// Port of the top of App.jsx: show SignIn until there's a session, then
/// the real app shell — a tab bar here instead of the web's nav links.
struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        if auth.session != nil {
            MainTabView()
        } else {
            SignInView()
        }
    }
}

struct MainTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                DashboardView(
                    onAddStock: { selection = 1 },
                    onAddBet: { selection = 2 },
                    // A cold Render instance means the Dashboard's very
                    // first alerts fetch fails -- rather than leave you
                    // stuck on a dead "Couldn't load alerts" screen,
                    // drop onto the Stock tab instead, where there's
                    // something to actually do while it spins up.
                    onInitialLoadFailed: { selection = 1 }
                )
            }
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { StockSearchView(onSaved: { selection = 0 }) }
                .tabItem { Label("Stocks", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(1)

            NavigationStack { BetSearchView(onSaved: { selection = 0 }) }
                .tabItem { Label("Bets", systemImage: "sportscourt") }
                .tag(2)
        }
    }
}

#Preview {
    RootView().environmentObject(AuthManager())
}
