import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var discovery = ServerDiscoveryService()
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

                Button("保存当前服务器") {
                    settings.saveCurrentServer()
                }

                Text("iPhone 连接开发机时，请使用电脑的局域网 IP；不要填 localhost。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !settings.savedServers.isEmpty {
                Section("已保存的服务器") {
                    ForEach(settings.savedServers) { server in
                        Button {
                            settings.serverURLString = server.url
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(server.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(server.url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.trimmedServerURLString == server.url {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            settings.removeSavedServer(settings.savedServers[index])
                        }
                    }
                }
            }

            Section("局域网服务发现") {
                if discovery.isScanning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("正在扫描局域网...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(discovery.discoveredServers) { server in
                    Button {
                        settings.serverURLString = server.urlString
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(server.isRecentlyActive ? .green : .orange)
                                        .frame(width: 8, height: 8)
                                    Text(server.name)
                                        .font(.subheadline.weight(.medium))
                                }
                                Text(server.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.serverURLString == server.urlString {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if discovery.discoveredServers.isEmpty && !discovery.isScanning {
                    Text("未发现局域网服务")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    if discovery.isScanning {
                        discovery.stopScanning()
                    } else {
                        discovery.startScanning()
                        Task { await discovery.scanSubnet() }
                    }
                } label: {
                    Label(
                        discovery.isScanning ? "停止扫描" : "扫描局域网",
                        systemImage: discovery.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right"
                    )
                }
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
        .onAppear { discovery.startScanning() }
        .onDisappear { discovery.stopScanning() }
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
