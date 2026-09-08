import SwiftUI
import UserNotifications

/// New: the app's first real Settings/account screen — until now there
/// was no persistent screen for this anywhere (web included), and Sign
/// Out lived inside a small toolbar menu on the Dashboard. This is a
/// first pass meant to be tweaked: Email is the channel the backend
/// already sends (see notifications.py), and its toggle here is a
/// client-side preference only for now — the backend doesn't check it
/// yet, so turning it off won't stop emails from arriving until that's
/// wired up. Push asks for the real iOS permission and reflects the
/// real system status, but isn't wired to the backend either (no
/// device-token endpoint exists yet — see poll_alerts' send_email_func
/// pattern for where a send_push_func would plug in). Text is a UI
/// placeholder only — SMS needs a provider (e.g. Twilio) and phone
/// verification we haven't built.
struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    // Local cache, so the toggle shows something instantly and still
    // works offline — but the backend (loaded in loadEmailPreference())
    // is the real source of truth once it's reachable.
    @AppStorage("lt_notifyEmail") private var notifyEmail = true
    @AppStorage("lt_wantsPush") private var wantsPush = false

    @State private var pushAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var showSignOutConfirm = false
    // Set right before loadEmailPreference() assigns the fetched value to
    // notifyEmail, so that assignment's own onChange doesn't immediately
    // PUT the value we just loaded straight back to the server.
    @State private var suppressNextEmailChange = false
    @State private var emailSettingsError: String?

    var body: some View {
        ZStack {
            Color.ltBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    section(title: "Account") {
                        row {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Signed in as")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.ltTextSecondary)
                                Text(auth.session?.email ?? "—")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.ltTextPrimary)
                            }
                            Spacer()
                        }

                        Divider().overlay(Color.ltBorder)

                        Button {
                            showSignOutConfirm = true
                        } label: {
                            HStack {
                                Text("Sign Out")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            .foregroundStyle(Color.ltDanger)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    section(
                        title: "Notifications",
                        footer: "Choose how you want to hear about a target being hit."
                    ) {
                        toggleRow(
                            icon: "envelope.fill",
                            title: "Email",
                            subtitle: emailSettingsError ?? (auth.session?.email ?? "Always available"),
                            isOn: $notifyEmail
                        )
                        Divider().overlay(Color.ltBorder)
                        pushRow
                        Divider().overlay(Color.ltBorder)
                        textRow
                    }

                    section(title: "About") {
                        row {
                            Text("Version")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.ltTextPrimary)
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(Color.ltTextSecondary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ltBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.ltTextPrimary)
                }
            }
        }
        .task {
            await refreshPushStatus()
            await loadEmailPreference()
        }
        .onChange(of: wantsPush) { _, newValue in
            if newValue { Task { await requestPush() } }
        }
        .onChange(of: notifyEmail) { _, newValue in
            if suppressNextEmailChange {
                suppressNextEmailChange = false
                return
            }
            Task { await saveEmailPreference(newValue) }
        }
        .confirmationDialog(
            "Sign out of LineTracker?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        Text("Settings")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(Color.ltTextPrimary)
    }

    // MARK: - Push

    private var pushSubtitle: String {
        switch pushAuthStatus {
        case .authorized, .provisional, .ephemeral:
            return wantsPush ? "Enabled" : "Allowed by iOS, off in-app"
        case .denied:
            return "Blocked in iOS Settings — tap to open"
        default:
            return "Get a push the moment a target is hit"
        }
    }

    private var pushRow: some View {
        Button {
            if pushAuthStatus == .denied { openSystemSettings() }
        } label: {
            HStack(spacing: 12) {
                iconBadge("bell.badge.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push Notifications")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ltTextPrimary)
                    Text(pushSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(pushAuthStatus == .denied ? Color.ltDanger : Color.ltTextSecondary)
                }
                Spacer()
                if pushAuthStatus == .denied {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.ltTextTertiary)
                } else {
                    Toggle("", isOn: $wantsPush)
                        .labelsHidden()
                        .tint(Color.ltSuccess)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(pushAuthStatus != .denied)
    }

    // MARK: - Text (placeholder — no SMS provider wired up yet)

    private var textRow: some View {
        HStack(spacing: 12) {
            iconBadge("message.fill")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Text Alerts")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ltTextPrimary)
                    Text("COMING SOON")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.ltSurface, in: Capsule())
                        .foregroundStyle(Color.ltTextTertiary)
                }
                Text("Get a text the moment a target is hit")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ltTextSecondary)
            }
            Spacer()
            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .disabled(true)
        }
        .padding(.vertical, 4)
        .opacity(0.55)
    }

    // MARK: - Shared row/section helpers

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconBadge(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ltTextPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ltTextSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.ltSuccess)
        }
        .padding(.vertical, 4)
    }

    private func iconBadge(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.ltTextPrimary)
            .frame(width: 30, height: 30)
            .background(Color.ltSurface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func section<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.ltTextSecondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.ltSurfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ltBorder, lineWidth: 1))

            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ltTextTertiary)
                    .padding(.leading, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack { content() }
            .padding(.vertical, 4)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - Push permission plumbing

    private func refreshPushStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        pushAuthStatus = settings.authorizationStatus
    }

    private func requestPush() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        } catch {
            // Leave wantsPush as-is — refreshPushStatus below reflects
            // whatever the system actually decided.
        }
        await refreshPushStatus()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Email preference (backend-synced)

    private func loadEmailPreference() async {
        do {
            let settings = try await APIClient.shared.getSettings()
            emailSettingsError = nil
            suppressNextEmailChange = true
            notifyEmail = settings.notifyEmail
        } catch {
            // Backend unreachable or not signed in yet — fall back to
            // whatever's cached locally (the @AppStorage default) rather
            // than blocking the screen on a network error.
            emailSettingsError = "Couldn't reach the server — showing your last saved setting"
        }
    }

    private func saveEmailPreference(_ value: Bool) async {
        do {
            try await APIClient.shared.updateSettings(notifyEmail: value)
            emailSettingsError = nil
        } catch {
            emailSettingsError = "Couldn't save — check your connection"
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environmentObject(AuthManager())
}
