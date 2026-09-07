import SwiftUI

/// Port of StockSearch.jsx. Skips the FMP company-name autocomplete
/// dropdown for v1 — plain ticker search still hits the same
/// /stocks/price endpoint and covers the core "track a stock" flow.
struct StockSearchView: View {
    var onSaved: () -> Void = {}

    @State private var tickerInput = ""
    @State private var stock: StockPrice?
    @State private var searching = false
    @State private var searchError: String?

    @State private var targetValue: Double = 0
    @State private var saving = false
    @State private var saveError: String?

    private var direction: String {
        guard let stock else { return "above" }
        return targetValue >= stock.price ? "above" : "below"
    }

    var body: some View {
        Form {
            Section("Look up a ticker") {
                HStack {
                    TextField("e.g. AAPL", text: $tickerInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Search") { Task { await search() } }
                        .disabled(tickerInput.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                }
                if searching { ProgressView() }
                if let searchError { Text(searchError).foregroundStyle(.red).font(.footnote) }
            }

            if let stock {
                Section("Result") {
                    HStack {
                        Text(stock.ticker).font(.headline)
                        Spacer()
                        Text(Formatting.dollars(stock.price)).font(.title3.monospacedDigit())
                    }
                    if let prev = stock.previousClose {
                        Text("Closed at \(Formatting.dollars(prev))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Set your target") {
                    HStack {
                        Text(direction == "above" ? "▲" : "▼")
                            .foregroundStyle(direction == "above" ? .green : .red)
                        Text(Formatting.dollars(targetValue))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(direction == "above" ? .green : .red)
                    }
                    Slider(value: $targetValue, in: (stock.price * 0.5)...(stock.price * 1.5))
                    HStack {
                        Text(Formatting.dollars(stock.price * 0.5)).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("Current: \(Formatting.dollars(stock.price))").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatting.dollars(stock.price * 1.5)).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Or type price:")
                        TextField("price", value: $targetValue, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let saveError { Text(saveError).foregroundStyle(.red).font(.footnote) }

                Section {
                    Button(saving ? "Saving…" : "Set alert") { Task { await save() } }
                        .disabled(saving)
                }
            }
        }
        .navigationTitle("Track a stock")
    }

    private func search() async {
        searching = true
        searchError = nil
        stock = nil
        do {
            let result = try await APIClient.shared.getStockPrice(ticker: tickerInput.trimmingCharacters(in: .whitespaces).uppercased())
            stock = result
            targetValue = result.price
        } catch {
            searchError = "Could not find that ticker. Double check the symbol."
        }
        searching = false
    }

    private func save() async {
        guard let stock else { return }
        saving = true
        saveError = nil
        do {
            _ = try await APIClient.shared.createAlert(NewAlertRequest(
                alertType: "Stock 🌱",
                ticker: stock.ticker,
                companyName: nil,
                sport: nil, eventId: nil, homeTeam: nil, awayTeam: nil,
                homeLogo: nil, awayLogo: nil, market: nil, outcomeName: nil, bookmaker: nil,
                targetValue: targetValue,
                currentValue: stock.price,
                direction: direction,
                commenceTime: nil
            ))
            saving = false
            onSaved()
        } catch {
            saveError = (error as? APIClient.APIError)?.errorDescription ?? "Could not save the alert. Try again."
            saving = false
        }
    }
}

#Preview {
    NavigationStack { StockSearchView() }
}
