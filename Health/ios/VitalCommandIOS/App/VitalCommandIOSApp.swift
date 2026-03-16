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
            // Teal gradient background matching the MAI brand
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.58, blue: 0.55),
                    Color(red: 0.10, green: 0.48, blue: 0.46),
                    Color(red: 0.06, green: 0.42, blue: 0.40)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App logo — uses the icon from the asset catalog
                Image("SplashLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)

                // Loading dots
                HStack(spacing: 6) {
                    ForEach(0..<3) { _ in
                        Circle()
                            .fill(.white.opacity(0.5))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 24)

                // Title
                Text("Health AI")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.top, 20)

                // Subtitle
                Text("你的个性化健康助理")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 6)

                Spacer()

                // Bottom sparkle icon
                Image(systemName: "sparkle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 40)
            }
        }
    }
}
