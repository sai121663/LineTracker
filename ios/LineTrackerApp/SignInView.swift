import SwiftUI
import GoogleSignIn
import AuthenticationServices

/// Port of SignIn.jsx — swaps the web's Google Identity Services button
/// for the native GoogleSignIn-iOS SDK, then hands the ID token to the
/// exact same POST /auth/google endpoint the web app uses. Styled to
/// match SignIn.css / index.css's dark card design.
struct SignInView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var errorMessage: String?
    @State private var signingIn = false

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text("LINE")
                        .foregroundStyle(Color.ltTextPrimary)
                    Text("TRACKER")
                        .foregroundStyle(Color.ltAccent)
                }
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .tracking(1)
                .padding(.bottom, 8)

                Text("Sign in to continue")
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(Color.ltTextPrimary)

                Text("Sign in to see your alerts and get notified the moment they hit.")
                    .font(.subheadline)
                    .foregroundStyle(Color.ltTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.bottom, 20)

                // Apple requires Sign in with Apple whenever a third-party
                // login (Google, here) is offered as an equivalent option
                // — App Store Review Guideline 4.8.
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(Capsule())
                .disabled(signingIn)
                .padding(.bottom, 10)

                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        if signingIn {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "globe")
                            Text("Continue with Google")
                                .fontWeight(.medium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .background(Color.ltSurfaceRaised)
                .foregroundStyle(Color.ltTextPrimary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.ltBorderBright, lineWidth: 1))
                .disabled(signingIn)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.ltDanger)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .padding(32)
            .background(Color.ltSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ltBorder, lineWidth: 1))
            .padding(.horizontal, 24)
            .frame(maxWidth: 420)
        }
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func signIn() async {
        errorMessage = nil
        signingIn = true
        defer { signingIn = false }

        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController else {
            errorMessage = "Couldn't find a window to present sign-in from."
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google didn't return an ID token."
                return
            }
            let session = try await APIClient.shared.signInWithGoogle(idToken: idToken)
            auth.signIn(token: session.token, email: session.email)
        } catch {
            // Surface the REAL error instead of a generic message — this
            // is what actually tells us whether it's Google's SDK, the
            // network, or the backend rejecting the token.
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            print("[SignIn] error: \(error)")
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple didn't return an identity token."
                return
            }
            Task { await signInWithApple(identityToken: identityToken) }
        case .failure(let error):
            // The user tapping "Cancel" on Apple's own sheet comes through
            // here too -- that's not a real error, so don't show one.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            print("[SignIn] Apple error: \(error)")
        }
    }

    @MainActor
    private func signInWithApple(identityToken: String) async {
        errorMessage = nil
        signingIn = true
        defer { signingIn = false }
        do {
            let session = try await APIClient.shared.signInWithApple(identityToken: identityToken)
            auth.signIn(token: session.token, email: session.email)
        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
            print("[SignIn] Apple backend error: \(error)")
        }
    }
}

#Preview {
    SignInView().environmentObject(AuthManager())
}
