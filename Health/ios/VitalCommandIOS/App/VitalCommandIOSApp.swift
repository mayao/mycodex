import SwiftUI

@main
struct VitalCommandIOSApp: App {
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var authManager = AuthManager()
    @StateObject private var autoSync = AutoSyncCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isLoading {
                    launchScreen
                } else if authManager.isAuthenticated {
                    MainTabView()
                        .environmentObject(settings)
                        .environmentObject(authManager)
                        .environmentObject(autoSync)
                } else {
                    LoginScreen()
                        .environmentObject(settings)
                        .environmentObject(authManager)
                }
            }
            .preferredColorScheme(.light)
            .onChange(of: authManager.token) {
                settings.authToken = authManager.token
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active, authManager.isAuthenticated {
                    autoSync.syncIfNeeded(settings: settings)
                }
            }
            .task {
                settings.authToken = authManager.token
                await authManager.validateSession(using: settings)
                // Auto-sync on first launch
                if authManager.isAuthenticated {
                    autoSync.syncIfNeeded(settings: settings)
                }
            }
        }
    }

    private var launchScreen: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.99, blue: 0.97),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#0f766e") ?? .teal, Color(hex: "#0d5263") ?? .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "heart.text.clipboard")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                }

                ProgressView()
                    .tint(Color(hex: "#0f766e") ?? .teal)
            }
        }
    }
}
