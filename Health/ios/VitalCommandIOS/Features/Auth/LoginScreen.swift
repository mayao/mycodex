import SwiftUI
import VitalCommandMobileCore

struct LoginScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var authManager: AuthManager

    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var didAttemptAutoLogin = false
    @State private var showServerConfig = false
    @State private var serverReachable: Bool?
    @State private var isCheckingServer = false

    private let tealColor = Color(hex: "#0f766e") ?? .teal
    private let darkText = Color(red: 0.05, green: 0.13, blue: 0.2)

    var body: some View {
        ZStack {
            loginBackground
            VStack(spacing: 0) {
                serverConfigBar
                Spacer().frame(height: 60)
                logoSection
                    .padding(.bottom, 56)
                loginCard
                    .padding(.horizontal, 24)
                Spacer()
                bottomInfo
            }
        }
        .task {
            guard !didAttemptAutoLogin else { return }
            didAttemptAutoLogin = true
            await checkServerReachability()
            if serverReachable == true {
                await loginWithBiometrics()
            }
        }
        .onChange(of: settings.serverURLString) {
            serverReachable = nil
            errorMessage = nil
            Task { await checkServerReachability() }
        }
        .sheet(isPresented: $showServerConfig) {
            LoginServerConfigSheet(serverReachable: $serverReachable)
                .environmentObject(settings)
        }
    }

    // MARK: - Sub-views

    private var loginBackground: some View {
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
    }

    private var serverConfigBar: some View {
        HStack {
            Spacer()
            Button {
                showServerConfig = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(serverStatusColor)
                        .frame(width: 8, height: 8)
                    Image(systemName: "server.rack")
                        .font(.subheadline)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.trailing, 20)
            .padding(.top, 12)
        }
    }

    private var logoSection: some View {
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
    }

    private var loginCard: some View {
        VStack(spacing: 24) {
            welcomeSection
            serverStatusBanner
            errorBanner
            biometricButton
            skipButton
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tealColor.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 20, y: 10)
    }

    private var welcomeSection: some View {
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
    }

    @ViewBuilder
    private var serverStatusBanner: some View {
        if let reachable = serverReachable {
            HStack(spacing: 8) {
                Circle()
                    .fill(reachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(reachable ? "服务器已连接" : "服务器无法连接")
                    .font(.caption)
                    .foregroundStyle(reachable ? Color.secondary : Color.red.opacity(0.8))
                if !reachable {
                    Button("切换服务器") {
                        showServerConfig = true
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tealColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                (reachable ? Color.green : Color.red).opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.8))
                    Button("切换服务器地址") {
                        showServerConfig = true
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tealColor)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var biometricButton: some View {
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
    }

    private var skipButton: some View {
        Button {
            Task { await directLogin() }
        } label: {
            Text("跳过验证，直接进入")
                .font(.footnote)
                .foregroundStyle(tealColor)
        }
        .disabled(isLoggingIn)
    }

    private var bottomInfo: some View {
        VStack(spacing: 6) {
            Button {
                showServerConfig = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text(settings.trimmedServerURLString)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(.tertiary)
            }

            Text("设备标识: \(String(authManager.deviceId.prefix(8)))...")
                .font(.caption2.monospaced())
                .foregroundStyle(.quaternary)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Server check

    private var serverStatusColor: Color {
        if isCheckingServer { return .orange }
        switch serverReachable {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .gray
        }
    }

    private func checkServerReachability() async {
        isCheckingServer = true
        defer { isCheckingServer = false }

        let urlString = settings.trimmedServerURLString.hasSuffix("/")
            ? settings.trimmedServerURLString + "api/health"
            : settings.trimmedServerURLString + "/api/health"

        guard let url = URL(string: urlString) else {
            serverReachable = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                serverReachable = (200...499).contains(httpResponse.statusCode)
            } else {
                serverReachable = false
            }
        } catch {
            serverReachable = false
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
            serverReachable = false
        }
        isLoggingIn = false
    }
}

// MARK: - Server Config Sheet (accessible from Login screen)

struct LoginServerConfigSheet: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @Binding var serverReachable: Bool?

    @State private var editingURL: String = ""
    @State private var checkingServers: Set<String> = []
    @State private var serverStatuses: [String: Bool] = [:]

    private let tealColor = Color(hex: "#0f766e") ?? .teal

    var body: some View {
        NavigationStack {
            Form {
                currentServerSection
                quickSwitchSection
                checkAllSection
            }
            .navigationTitle("服务器设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                editingURL = settings.trimmedServerURLString
                Task { await checkAllServers() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var currentServerSection: some View {
        Section("当前服务器") {
            HStack {
                TextField("http://10.8.140.209:3000/", text: $editingURL)
                    .appURLTextEntry()

                if checkingServers.contains(editingURL) {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            HStack {
                Button("连接") {
                    settings.serverURLString = editingURL
                    Task { await checkServer(editingURL) }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(tealColor, in: Capsule())

                Button("保存到列表") {
                    settings.serverURLString = editingURL
                    settings.saveCurrentServer()
                }
                .font(.subheadline)
                .foregroundStyle(tealColor)
            }
        }
    }

    private var quickSwitchSection: some View {
        Section("快速切换") {
            serverRow(name: "主服务器", url: "http://10.8.140.209:3000/")
            serverRow(name: "备用服务器", url: "http://10.8.144.16:3001/")

            ForEach(settings.savedServers) { server in
                serverRow(name: server.name, url: server.url)
            }
        }
    }

    private var checkAllSection: some View {
        Section {
            Button("检测所有服务器") {
                Task { await checkAllServers() }
            }
            .font(.subheadline)
        } footer: {
            Text("iPhone 连接开发机时，请使用电脑的局域网 IP；不要填 localhost 或 127.0.0.1。")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private func serverRow(name: String, url: String) -> some View {
        Button {
            editingURL = url
            settings.serverURLString = url
            Task {
                await checkServer(url)
                dismiss()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                serverStatusIndicator(for: url)

                if settings.trimmedServerURLString == url {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tealColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func serverStatusIndicator(for url: String) -> some View {
        if checkingServers.contains(url) {
            ProgressView().scaleEffect(0.7)
        } else if let reachable = serverStatuses[url] {
            HStack(spacing: 4) {
                Circle()
                    .fill(reachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(reachable ? "在线" : "离线")
                    .font(.caption2)
                    .foregroundStyle(reachable ? .green : .red)
            }
        }
    }

    private func checkServer(_ urlString: String) async {
        checkingServers.insert(urlString)
        defer { checkingServers.remove(urlString) }

        let healthURL = urlString.hasSuffix("/")
            ? urlString + "api/health"
            : urlString + "/api/health"

        guard let url = URL(string: healthURL) else {
            serverStatuses[urlString] = false
            if settings.trimmedServerURLString == urlString {
                serverReachable = false
            }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let reachable = (response as? HTTPURLResponse).map { (200...499).contains($0.statusCode) } ?? false
            serverStatuses[urlString] = reachable
            if settings.trimmedServerURLString == urlString {
                serverReachable = reachable
            }
        } catch {
            serverStatuses[urlString] = false
            if settings.trimmedServerURLString == urlString {
                serverReachable = false
            }
        }
    }

    private func checkAllServers() async {
        let urls = Set(
            ["http://10.8.140.209:3000/", "http://10.8.144.16:3001/"]
            + settings.savedServers.map(\.url)
        )
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { await checkServer(url) }
            }
        }
    }
}
