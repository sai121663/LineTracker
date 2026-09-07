import SwiftUI
import GoogleSignIn

@main
struct LineTrackerAppMain: App {
    @StateObject private var auth = AuthManager()

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Config.googleIOSClientID)
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
