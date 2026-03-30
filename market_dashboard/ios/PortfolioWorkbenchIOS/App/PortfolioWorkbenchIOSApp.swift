import SwiftUI

@main
struct PortfolioWorkbenchIOSApp: App {
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var dashboardStore = PortfolioDashboardStore()

    var body: some Scene {
        WindowGroup {
            RootScreen()
                .environmentObject(settings)
                .environmentObject(dashboardStore)
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Group {
            if settings.requiresBiometricUnlock && settings.isAuthenticated {
                BiometricUnlockScreen()
            } else if settings.isAuthenticated || settings.supportsStandaloneAIEntry {
                MainTabView()
            } else {
                LoginScreen()
            }
        }
        .onOpenURL { url in
            Task { await settings.handleLongbridgeOAuthCallback(url: url) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                settings.lockIfNeeded()
            }
        }
    }
}
