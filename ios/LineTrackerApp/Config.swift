import Foundation

enum Config {
    // TODO: your deployed Render backend URL — same one VITE_API_URL
    // points to for the Vercel frontend.
    static let apiBaseURL = "https://linetracker.onrender.com"

    // TODO: the iOS OAuth client ID you create in Google Cloud Console
    // (Credentials -> Create Credentials -> OAuth client ID -> iOS).
    // This is DIFFERENT from the web VITE_GOOGLE_CLIENT_ID.
    static let googleIOSClientID = "407667179602-dcukha86sncrj0ssn1dp1mckdjg0v4q1.apps.googleusercontent.com"

    // Logo.dev publishable token, used for the stock-ticker and bookmaker
    // logos. Logokit (which the web app still uses, in frontend/.env's
    // VITE_LOGOKIT_API_TOKEN) blocks all non-browser (programmatic)
    // requests, which breaks image loading in a native app — Logo.dev
    // doesn't have that restriction, so the iOS app uses it instead.
    // A "pk_" token like this is meant to be embedded in client code.
    static let logoDevToken = "pk_Broua1rpRo-c0XB-Grdn1g"

    // Same Financial Modeling Prep key as frontend/.env's VITE_FMP_API_KEY,
    // used for the company-name/ticker-symbol autocomplete search on the
    // "Track a stock" page.
    static let fmpAPIKey = "kIYiw00SOXJVw7tvUehQZx5kkQpvU4mZ"
}
