import Foundation

enum Config {
    // TODO: your deployed Render backend URL — same one VITE_API_URL
    // points to for the Vercel frontend.
    static let apiBaseURL = "https://linetracker.onrender.com"

    // TODO: the iOS OAuth client ID you create in Google Cloud Console
    // (Credentials -> Create Credentials -> OAuth client ID -> iOS).
    // This is DIFFERENT from the web VITE_GOOGLE_CLIENT_ID.
    static let googleIOSClientID = "407667179602-dcukha86sncrj0ssn1dp1mckdjg0v4q1.apps.googleusercontent.com"

    // Same publishable Logokit token as frontend/.env's VITE_LOGOKIT_API_TOKEN.
    // A "pk_" token like this is meant to be embedded in client code — it's
    // already shipped in plain sight inside the web app's JS bundle, so
    // there's nothing more exposed about it living here too.
    static let logokitToken = "pk_fr7b716a88eb2a3b77a6fb"
}
