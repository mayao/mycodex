import SwiftUI

struct BiometricUnlockScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var isUnlocking = false
    @State private var statusMessage = "请完成本机验证…"
    @State private var hasAttemptedAutoUnlock = false
    @State private var showManualBypass = false

    var body: some View {
        ZStack {
            BootBrandBackdrop()

            VStack {
                BootBrandWordmark(logoSize: 86, titleSize: 33, subtitleSize: 11)

                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(0.78))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 2)
            }
            .offset(y: -112)

            VStack(spacing: 12) {
                Spacer()

                if isUnlocking {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.14)
                }

                Text(displayStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.90))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                if shouldShowRetryActions {
                    VStack(spacing: 10) {
                        Button {
                            Task { await unlock() }
                        } label: {
                            Text("重新验证")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrokerPalette.cyan)
                        .foregroundStyle(Color.black)
                        .disabled(isUnlocking)

                        Button {
                            Task { await continueWithoutBiometric() }
                        } label: {
                            Text("继续进入首页")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrokerPalette.gold)
                        .disabled(isUnlocking)

                        Button {
                            settings.logoutCurrentSession()
                        } label: {
                            Text("退出当前账号")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrokerPalette.red)
                        .disabled(isUnlocking)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await autoUnlockIfNeeded()
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if settings.requiresBiometricUnlock {
                showManualBypass = true
            }
        }
        .onChange(of: settings.connectionStatusMessage) { _, newValue in
            guard let newValue, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            statusMessage = newValue
        }
    }

    private var shouldShowRetryActions: Bool {
        let lowered = displayStatusMessage.lowercased()
        return showManualBypass
            || lowered.contains("失败")
            || lowered.contains("错误")
            || lowered.contains("重试")
            || lowered.contains("未通过")
            || lowered.contains("取消")
    }

    private var displayStatusMessage: String {
        if let message = settings.connectionStatusMessage,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        return statusMessage
    }

    private func autoUnlockIfNeeded() async {
        guard !hasAttemptedAutoUnlock else {
            return
        }
        hasAttemptedAutoUnlock = true
        await unlock()
    }

    private func unlock() async {
        isUnlocking = true
        defer { isUnlocking = false }

        do {
            try await settings.unlockActiveSession()
            showManualBypass = false
            statusMessage = "验证通过，正在进入首页…"
        } catch {
            statusMessage = friendlyErrorMessage(error)
        }
    }

    private func continueWithoutBiometric() async {
        isUnlocking = true
        defer { isUnlocking = false }

        do {
            try await settings.proceedIntoActiveSessionWithoutBiometric()
            showManualBypass = false
            statusMessage = "已进入首页，稍后仍可使用面容 ID。"
        } catch {
            statusMessage = friendlyErrorMessage(error)
        }
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return "连接超时，请稍后重试。"
        }
        if lowered.contains("could not connect")
            || lowered.contains("offline")
            || lowered.contains("network")
            || lowered.contains("connection") {
            return "网络连接异常，请检查网络后重试。"
        }
        return error.localizedDescription
    }
}
