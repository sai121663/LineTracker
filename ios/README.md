# LineTracker iOS — setup steps

All the Swift code is written and sitting in `LineTrackerApp/`. This is the
checklist to get it running in Xcode — no Swift knowledge needed, just
following steps and pasting back whatever Xcode complains about.

## Files (all done, ported from the web app)

| File | Ports |
|---|---|
| `Alert.swift` | `models.py`'s `Alert.to_dict()` |
| `OddsModels.swift` | the nested `/odds` JSON shape from `app.py` |
| `Formatting.swift` | odds/price formatting + the American-odds slider math from `BetSearch.jsx` |
| `AuthManager.swift` | session storage (Keychain instead of `localStorage`) |
| `APIClient.swift` | `frontend/src/api.js` |
| `SignInView.swift` | `SignIn.jsx` (native Google Sign-In instead of the web SDK) |
| `DashboardView.swift` | `Dashboard.jsx` |
| `StockSearchView.swift` | `StockSearch.jsx` (skips the FMP autocomplete dropdown for now — plain ticker search) |
| `BetSearchView.swift` | `BetSearch.jsx`'s step wizard (moneyline/h2h only, matching what the web UI actually exposes) |
| `RootView.swift` | the sign-in-vs-app-shell switch + tab bar (replaces the web's nav links) |
| `Config.swift` | **fill this in** — your backend URL + iOS Google client ID |
| `LineTrackerApp.swift` | app entry point |

## Setup steps, in order

1. **Install Xcode** from the Mac App Store (large download — start this first).

2. **Create a Google iOS OAuth client ID** (separate from the web one):
   Google Cloud Console → same project as `VITE_GOOGLE_CLIENT_ID` → Credentials
   → Create Credentials → OAuth client ID → **iOS**. It'll ask for a Bundle ID —
   pick one now (e.g. `com.saithan.linetracker`) and reuse it in the next step.
   Copy the client ID it gives you and the "reversed client ID" shown with it.

3. **Create the Xcode project**: File → New → Project → iOS → App.
   - Product Name: `LineTrackerApp`
   - Interface: SwiftUI, Language: Swift
   - Bundle Identifier: the same one from step 2

4. **Delete the auto-generated files** Xcode creates (`ContentView.swift`
   and the `LineTrackerAppApp.swift` file with `@main` in it) — we're
   using the ones already written instead, and Swift won't allow two
   `@main` entry points.

5. **Add the GoogleSignIn package**: File → Add Package Dependencies →
   paste `https://github.com/google/GoogleSignIn-iOS` → Add Package →
   check both `GoogleSignIn` and `GoogleSignInSwift`.

6. **Register the URL scheme**: select the project in the navigator → your
   target → Info tab → URL Types → add one, paste the "reversed client ID"
   from step 2 into the URL Schemes field.

7. **Drag all 12 files from `ios/LineTrackerApp/`** (in this folder) into
   the Xcode project navigator — check "Copy items if needed" and make
   sure the app target is checked.

8. **Fill in `Config.swift`**: replace the two placeholder strings with
   your actual Render backend URL and the iOS client ID from step 2.

9. **Build and run** (▶ button, or Cmd+R) with an iPhone simulator selected.

## When something breaks

Since I can't see your screen, just paste back:
- the exact red error text from Xcode (click the error to expand it), or
- a screenshot of what's on screen if it's a runtime/UI thing rather than
  a build error

and I'll fix the file directly — I can edit anything in `ios/LineTrackerApp/`
straight from here, you'll just need to re-drag or let Xcode pick up the
change (it usually notices automatically since these are real files on disk).
