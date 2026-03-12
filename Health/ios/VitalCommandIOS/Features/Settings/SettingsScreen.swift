import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager
    @State private var showLogoutConfirmation = false

    var body: some View {
        Form {
            // User info section
            if let user = authManager.currentUser {
                Section("账号信息") {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#0f766e") ?? .teal, Color(hex: "#0d5263") ?? .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)

                            Text(String(user.displayName.prefix(1)))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.subheadline.weight(.semibold))
                            if let phone = user.phoneNumber {
                                Text(maskPhoneNumber(phone))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text("ID: \(String(user.id.suffix(6)))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("HealthAI") {
                Text("HealthAI 展示首页结论、趋势、报告和数据同步状态。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("服务地址") {
                TextField("http://10.8.140.209:3000/", text: $settings.serverURLString)
                    .appURLTextEntry()

                Button("模拟器使用本机地址 127.0.0.1:3000") {
                    settings.serverURLString = "http://127.0.0.1:3000/"
                }

                Text("iPhone 连接开发机时，请使用电脑的局域网 IP；不要填 localhost。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("使用说明") {
                Text("首页用于快速查看核心结论和行动提示。")
                Text("趋势页可以查看完整图表。")
                Text("报告页用于阅读周报和月报。")
                Text("数据页可以上传文件并同步 Apple 健康。")
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("退出登录")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("设置")
        .alert("确认退出？", isPresented: $showLogoutConfirmation) {
            Button("取消", role: .cancel) {}
            Button("退出登录", role: .destructive) {
                authManager.logout()
            }
        } message: {
            Text("退出后需要重新验证身份登录")
        }
    }

    private func maskPhoneNumber(_ phone: String) -> String {
        guard phone.count >= 7 else { return phone }
        let start = phone.prefix(3)
        let end = phone.suffix(4)
        return "\(start)****\(end)"
    }
}
