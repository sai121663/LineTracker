import SwiftUI
import GoogleSignIn

@main
struct LineTrackerAppMain: App {
    @StateObject private var auth = AuthManager()

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Config.googleIOSClientID)

        // Reported: buttons in scrolling screens (Set alert, etc.) needing
        // one tap sometimes, two or three other times. Root cause: every
        // plain ScrollView is backed by a UIScrollView that, by default,
        // holds a touch briefly to decide "is this the start of a scroll,
        // or a tap on something inside me?" before forwarding it. Whether
        // a given tap wins that race is a timing coincidence -- exactly
        // the "sometimes works, sometimes doesn't" pattern reported, not
        // a bug in any specific button. SwiftUI doesn't expose this as
        // its own modifier, so it's set once, app-wide, via the
        // underlying UIKit type.
        UIScrollView.appearance().delaysContentTouches = false
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
