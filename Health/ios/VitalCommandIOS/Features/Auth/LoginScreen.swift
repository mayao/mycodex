import SwiftUI
import VitalCommandMobileCore

struct LoginScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager

    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var didAttemptAutoLogin = false

    private let tealColor = Color(hex: "#0f766e") ?? .teal
    private let darkText = Color(red: 0.05, green: 0.13, blue: 0.2)

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.99, blue: 0.97),
                    Color(red: 0.93, green: 0.96, blue: 0.94),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 100)

                // Logo & Title
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [tealColor, Color(hex: "#0d5263") ?? .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 90, height: 90)
                            .shadow(color: tealColor.opacity(0.3), radius: 20, y: 10)

                        Image(systemName: "heart.text.clipboard")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 6) {
                        Text("Vital Command")
                            .font(.title.weight(.bold))
                            .foregroundColor(darkText)

                        Text("你的智能健康管理助手")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 56)

                // Login Card
                VStack(spacing: 24) {
                    // Welcome + biometric icon
                    VStack(spacing: 12) {
                        Image(systemName: AuthManager.biometricIcon)
                            .font(.system(size: 44))
                            .foregroundStyle(tealColor)
                            .padding(.bottom, 4)

                        Text("欢迎使用")
                            .font(.headline)
                            .foregroundColor(darkText)

                        Text("首次使用将自动为您创建账号\n数据将绑定到此设备")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Error message
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // Face ID / Touch ID button
                    Button {
                        Task { await loginWithBiometrics() }
                    } label: {
                        HStack(spacing: 10) {
                            if isLoggingIn {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: AuthManager.biometricIcon)
                                    .font(.title3)
                            }
                            Text("使用\(AuthManager.biometricName)登录")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [tealColor, Color(hex: "#0d5263") ?? .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .shadow(color: tealColor.opacity(0.3), radius: 12, y: 6)
                    }
                    .disabled(isLoggingIn)

                    // Skip biometrics — direct login
                    Button {
                        Task { await directLogin() }
                    } label: {
                        Text("跳过验证，直接进入")
                            .font(.footnote)
                            .foregroundStyle(tealColor)
                    }
                    .disabled(isLoggingIn)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white)
                )
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [tealColor.opacity(0.03), Color.clear],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(tealColor.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 20, y: 10)
                .padding(.horizontal, 24)

                Spacer()

                // Device ID hint at bottom
                Text("设备标识: \(String(authManager.deviceId.prefix(8)))...")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 24)
            }
        }
        .task {
            // Auto-trigger biometric login on first appear
            guard !didAttemptAutoLogin else { return }
            didAttemptAutoLogin = true
            await loginWithBiometrics()
        }
    }

    // MARK: - Login methods

    private func loginWithBiometrics() async {
        errorMessage = nil
        isLoggingIn = true

        let passed = await authManager.authenticateWithBiometrics()
        if passed {
            await performDeviceLogin()
        } else {
            // Biometrics not available or user cancelled — don't auto-login, let user tap
            isLoggingIn = false
        }
    }

    private func directLogin() async {
        errorMessage = nil
        isLoggingIn = true
        await performDeviceLogin()
    }

    private func performDeviceLogin() async {
        do {
            try await authManager.deviceAutoLogin(using: settings)
        } catch {
            errorMessage = "连接服务器失败: \(error.localizedDescription)"
        }
        isLoggingIn = false
    }
}
