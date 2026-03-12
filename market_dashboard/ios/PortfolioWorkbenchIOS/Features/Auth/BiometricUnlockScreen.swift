import SwiftUI

struct BiometricUnlockScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var isUnlocking = false
    @State private var statusMessage: String?
    @State private var hasAttemptedAutoUnlock = false

    var body: some View {
        AppBackdrop {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 0)

                SectionPanel(
                    title: "\(settings.biometryType.displayName) 解锁",
                    subtitle: "当前 App 已切到设备唯一账号模式，先通过本机生物识别再访问你的持仓、结单和个人数据。"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let currentUser = settings.currentUser {
                            LabelValueRow(label: "当前账户", value: currentUser.displayName)
                            LabelValueRow(label: "用户 ID", value: currentUser.userId)
                        }

                        Button {
                            Task { await unlock() }
                        } label: {
                            HStack {
                                if isUnlocking {
                                    ProgressView()
                                        .tint(Color.black)
                                } else {
                                    Image(systemName: "faceid")
                                }
                                Text(isUnlocking ? "验证中" : "使用 \(settings.biometryType.displayName) 解锁")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrokerPalette.cyan)
                        .foregroundStyle(Color.black)
                        .disabled(isUnlocking)

                        Button {
                            settings.clearAuthentication()
                        } label: {
                            Text("退出当前账号")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrokerPalette.red)
                        .disabled(isUnlocking)

                        if let statusMessage, !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(BrokerPalette.red)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .task {
            await autoUnlockIfNeeded()
        }
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
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
