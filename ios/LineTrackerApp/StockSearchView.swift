import SwiftUI

/// One FMP search result — either a company-name match ("search-name") or
/// a ticker-symbol match ("search-symbol"), both endpoints return the
/// same shape. Extra fields FMP sends back are ignored by the decoder.
private struct StockSuggestion: Codable, Identifiable {
    let symbol: String
    let name: String
    var id: String { symbol }
}

/// A price slider whose filled track segment runs only between the
/// current price (always the midpoint of `range`, same as the web's
/// slider) and the thumb — instead of a plain Slider's built-in tint,
/// which fills the whole track from the minimum. Mirrors StockSearch.jsx's
/// hand-built CSS gradient background on its <input type="range">.
struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let current: Double

    private var color: Color {
        value >= current ? Color.ltSuccess : Color.ltDanger
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let currentPct = percent(current, in: range)
            let targetPct = percent(value, in: range)
            let leftPct = min(currentPct, targetPct)
            let rightPct = max(currentPct, targetPct)
            let thumbDiameter: CGFloat = 18

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.ltBorder)
                    .frame(height: 6)

                Capsule()
                    .fill(color)
                    .frame(width: max(0, (rightPct - leftPct) * width), height: 6)
                    .offset(x: leftPct * width)

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.ltBorderBright, lineWidth: 2))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: targetPct * width - thumbDiameter / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let pct = min(max(drag.location.x / width, 0), 1)
                        value = range.lowerBound + pct * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: 24)
    }

    private func percent(_ v: Double, in range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(max((v - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }
}

/// Port of StockSearch.jsx, styled to match the web app's dark theme
/// instead of a plain iOS Form: the Company/Ticker toggle, live
/// autocomplete dropdown (via FMP), dark result card, and the
/// target-price slider all mirror the web layout as closely as SwiftUI
/// allows.
struct StockSearchView: View {
    var onSaved: () -> Void = {}

    private enum SearchMode {
        case name, symbol
    }

    @State private var searchMode: SearchMode = .name
    @State private var query = ""
    @State private var suggestions: [StockSuggestion] = []
    @State private var showDropdown = false
    @State private var suggestionTask: Task<Void, Never>?
    // Set right before we programmatically assign `query` ourselves (after
    // picking a suggestion), so the onChange below doesn't treat that as
    // the user typing and immediately re-open the dropdown it just closed.
    @State private var suppressNextQueryChange = false

    @State private var stock: StockPrice?
    @State private var companyName: String?
    @State private var searchedTicker = ""
    @State private var searching = false
    @State private var searchError: String?

    @State private var targetValue: Double = 0
    @State private var priceInput = ""
    @State private var saving = false
    @State private var saveError: String?

    @FocusState private var searchFocused: Bool

    private var direction: String {
        guard let stock else { return "above" }
        return targetValue >= stock.price ? "above" : "below"
    }

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    searchSection

                    if let searchError {
                        Text(searchError)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ltDanger)
                    }

                    if searching {
                        ProgressView()
                            .tint(Color.ltAccent)
                            .frame(maxWidth: .infinity)
                    }

                    if let stock {
                        resultCard(stock)
                        alertForm(stock)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbarBackground(Color.ltBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Track a stock")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.ltTextPrimary)
            Text("Look up a ticker, set your target, get an email when it hits.")
                .font(.system(size: 14))
                .foregroundStyle(Color.ltTextSecondary)
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                modeButton("Company", mode: .name)
                modeButton("Ticker", mode: .symbol)
            }

            ZStack(alignment: .topLeading) {
                TextField("", text: $query, prompt: Text("Search").foregroundStyle(Color.ltTextTertiary))
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(searchMode == .symbol ? .characters : .words)
                    .submitLabel(.search)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Color.ltTextPrimary)
                    .padding(12)
                    .background(Color.ltSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(searchFocused ? Color.ltAccent : Color.ltBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .onChange(of: query) { _, newValue in
                        searchError = nil
                        if suppressNextQueryChange {
                            suppressNextQueryChange = false
                            return
                        }
                        scheduleSuggestions(for: newValue)
                    }
                    .onSubmit { submitSearch() }

                if showDropdown && !suggestions.isEmpty {
                    dropdown.offset(y: 52)
                }
            }
        }
        .zIndex(1)
    }

    private func modeButton(_ label: String, mode: SearchMode) -> some View {
        let isActive = searchMode == mode
        return Button {
            searchMode = mode
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                scheduleSuggestions(for: query, immediate: true)
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.ltAccentDim : Color.ltBackground)
        .foregroundStyle(isActive ? Color.ltAccent : Color.ltTextSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isActive ? Color.ltAccent : Color.ltBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var dropdown: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, s in
                Button {
                    selectSuggestion(s)
                } label: {
                    HStack(spacing: 10) {
                        Text(s.symbol)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.ltTextPrimary)
                            .frame(minWidth: 52, alignment: .leading)
                        Text(s.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ltTextSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Rectangle().fill(Color.ltBorder).frame(height: 1)
                }
            }
        }
        .background(Color.ltSurfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ltBorderBright, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Result card

    private func resultCard(_ stock: StockPrice) -> some View {
        HStack(spacing: 12) {
            if let url = URL(string: "https://img.logo.dev/ticker/\(searchedTicker)?token=\(Config.logoDevToken)") {
                RemoteImage(url: url) { image in
                    image.resizable().scaledToFit()
                } fallback: {
                    Circle().fill(Color.ltBorderBright)
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stock.ticker)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ltTextPrimary)

                Text("Closed at \(stock.previousClose.map { Formatting.dollars($0) } ?? "—")")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.white)
                    .foregroundStyle(.black)
                    .overlay(Capsule().stroke(Color.ltBorderBright, lineWidth: 1))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 8)

            Text(Formatting.dollars(stock.price))
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ltTextPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ltSurface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ltBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Alert form

    private func alertForm(_ stock: StockPrice) -> some View {
        let isAbove = targetValue >= stock.price
        let sliderColor = isAbove ? Color.ltSuccess : Color.ltDanger

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Target Price:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ltTextSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Text(isAbove ? "▲" : "▼")
                    Text(Formatting.dollars(targetValue))
                }
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(sliderColor)
            }

            HStack(spacing: 10) {
                Text("Or type price:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ltTextSecondary)
                TextField("price", text: $priceInput)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Color.ltTextPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: 110)
                    .background(Color.ltBackground)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.ltBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .onChange(of: priceInput) { _, newValue in
                        if let val = Double(newValue), val > 0 {
                            targetValue = val
                        }
                    }
                Spacer()
            }

            VStack(spacing: 8) {
                GradientSlider(
                    value: $targetValue,
                    range: (stock.price * 0.5)...(stock.price * 1.5),
                    current: stock.price
                )
                .onChange(of: targetValue) { _, newValue in
                    priceInput = String(format: "%.2f", newValue)
                }
                HStack {
                    Text(Formatting.dollars(stock.price * 0.5))
                        .foregroundStyle(Color.ltTextTertiary)
                    Spacer()
                    Text("Current: \(Formatting.dollars(stock.price))")
                        .foregroundStyle(Color.ltTextSecondary)
                    Spacer()
                    Text(Formatting.dollars(stock.price * 1.5))
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
                Task { await save() }
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

    // MARK: - Search / suggestions

    private func scheduleSuggestions(for text: String, immediate: Bool = false) {
        suggestionTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            suggestions = []
            showDropdown = false
            return
        }
        suggestionTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else { return }
            await fetchSuggestions(trimmed)
        }
    }

    private func fetchSuggestions(_ query: String) async {
        let path = searchMode == .name ? "search-name" : "search-symbol"
        var components = URLComponents(string: "https://financialmodelingprep.com/stable/\(path)")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "apikey", value: Config.fmpAPIKey),
        ]
        guard let url = components?.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            let decoded = try JSONDecoder().decode([StockSuggestion].self, from: data)
            suggestions = decoded
            showDropdown = true
        } catch {
            suggestions = []
        }
    }

    private func selectSuggestion(_ s: StockSuggestion) {
        suggestionTask?.cancel()
        suppressNextQueryChange = true
        query = s.symbol
        showDropdown = false
        suggestions = []
        searchError = nil
        searchFocused = false
        Task { await performSearch(ticker: s.symbol, companyName: s.name) }
    }

    private func submitSearch() {
        if let first = suggestions.first {
            selectSuggestion(first)
            return
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        showDropdown = false
        Task { await performSearch(ticker: trimmed.uppercased(), companyName: nil) }
    }

    private func performSearch(ticker: String, companyName: String?) async {
        searching = true
        searchError = nil
        stock = nil
        do {
            let result = try await APIClient.shared.getStockPrice(ticker: ticker)
            stock = result
            self.companyName = companyName
            searchedTicker = ticker
            targetValue = result.price
            priceInput = String(format: "%.2f", result.price)
        } catch {
            searchError = "Could not find that ticker. Double check the symbol."
        }
        searching = false
    }

    // MARK: - Save

    private func save() async {
        guard let stock else { return }
        saving = true
        saveError = nil
        do {
            _ = try await APIClient.shared.createAlert(NewAlertRequest(
                alertType: "Stock 🌱",
                ticker: stock.ticker,
                companyName: companyName,
                sport: nil, eventId: nil, homeTeam: nil, awayTeam: nil,
                homeLogo: nil, awayLogo: nil, market: nil, outcomeName: nil, bookmaker: nil,
                targetValue: targetValue,
                currentValue: stock.price,
                direction: direction,
                commenceTime: nil
            ))
            saving = false
            resetToDefault()
            onSaved()
        } catch {
            saveError = (error as? APIClient.APIError)?.errorDescription ?? "Could not save the alert. Try again."
            saving = false
        }
    }

    /// Puts the page back to its just-opened state — empty search, no
    /// result card — once an alert has been saved, instead of leaving
    /// the last searched stock sitting there the next time this tab
    /// is opened (SwiftUI keeps the tab's view alive across switches,
    /// so nothing does this for free).
    private func resetToDefault() {
        query = ""
        suggestions = []
        showDropdown = false
        suggestionTask?.cancel()

        stock = nil
        companyName = nil
        searchedTicker = ""
        searchError = nil

        targetValue = 0
        priceInput = ""
        saveError = nil
    }
}

#Preview {
    NavigationStack { StockSearchView() }
}
