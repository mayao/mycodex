import SwiftUI
import PortfolioWorkbenchMobileCore

struct LoginScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var isSubmitting = false
    @State private var statusMessage: String?

    var body: some View {
        AppBackdrop {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    serverSection
                    deviceAccountSection
                }
                .padding(16)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MyInvAI")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(BrokerPalette.ink)
            Text("使用当前设备登录，直接进入你的个人投资数据。首次启用会自动完成账户绑定，后续可用本机解锁继续进入。")
                .font(.subheadline)
                .foregroundStyle(BrokerPalette.muted)

            HStack(spacing: 8) {
                TagBadge(text: "设备登录", tint: BrokerPalette.cyan)
                TagBadge(text: settings.supportsBiometricUnlock ? settings.biometryType.displayName : "本机解锁", tint: BrokerPalette.teal)
                TagBadge(text: "个人数据", tint: BrokerPalette.gold)
            }
        }
    }

    private var serverSection: some View {
        SectionPanel(title: "服务地址", subtitle: "请填写当前可访问的数据服务地址。真机使用时建议填写局域网地址。") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("http://192.168.1.10:8008/", text: $settings.serverURLString)
                    .appURLTextEntry()
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("如果无法同步数据，请确认这里填写的是可访问地址，并且数据服务已经启动。")
                    .font(.footnote)
                    .foregroundStyle(BrokerPalette.muted)
            }
        }
    }

    private var deviceAccountSection: some View {
        SectionPanel(
            title: "进入应用",
            subtitle: settings.hasProvisionedDeviceAccount
                ? "当前 iPhone 已绑定你的设备账户，可直接继续。"
                : "首次使用时会自动为当前设备完成登录绑定。"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LabelValueRow(label: "设备名称", value: settings.deviceAccountProfile.deviceLabel)
                if let assignedUserID = settings.deviceAccountProfile.assignedUserID, !assignedUserID.isEmpty {
                    LabelValueRow(label: "账户编号", value: assignedUserID)
                }
                if let defaultPassword = settings.deviceAccountProfile.defaultPassword, !defaultPassword.isEmpty {
                    LabelValueRow(label: "备用密码", value: defaultPassword)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await loginWithDevice(requireLocalAuthentication: false) }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(Color.black)
                            } else {
                                Image(systemName: settings.hasProvisionedDeviceAccount ? "iphone.gen3" : "person.crop.rectangle.stack")
                            }
                            Text(deviceLoginButtonTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrokerPalette.cyan)
                    .foregroundStyle(Color.black)
                    .disabled(isSubmitting)

                    if settings.supportsBiometricUnlock && settings.hasProvisionedDeviceAccount {
                        Button {
                            Task { await loginWithDevice(requireLocalAuthentication: true) }
                        } label: {
                            Text("\(settings.biometryType.displayName) 登录")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BrokerPalette.teal)
                        .disabled(isSubmitting)
                    }
                }

                Text(biometricHint)
                    .font(.footnote)
                    .foregroundStyle(BrokerPalette.muted)

                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(statusMessage.contains("失败") || statusMessage.contains("无效") ? BrokerPalette.red : BrokerPalette.teal)
                }
            }
        }
    }

    private var deviceLoginButtonTitle: String {
        settings.hasProvisionedDeviceAccount ? "继续进入" : "启用并进入"
    }

    private var biometricHint: String {
        if settings.supportsBiometricUnlock {
            return settings.biometricUnlockEnabled
                ? "已开启 \(settings.biometryType.displayName) 本机解锁。"
                : "登录成功后可直接启用 \(settings.biometryType.displayName) 本机解锁。"
        }
        return "当前设备未检测到可用的 Face ID / Touch ID，仍可直接使用设备登录。"
    }

    private func loginWithDevice(requireLocalAuthentication: Bool) async {
        await withBusyState {
            let response = try await settings.loginWithDeviceAccount(requireLocalAuthentication: requireLocalAuthentication)
            let isNewDevice = response.deviceCredentials?.isNewDevice == true
            let hasPassword = !(settings.deviceAccountProfile.defaultPassword ?? "").isEmpty
            statusMessage = isNewDevice
                ? "设备已完成绑定。\(hasPassword ? "备用密码已保存，可在设置页查看。" : "")"
                : (requireLocalAuthentication ? "已通过 \(settings.biometryType.displayName) 登录。" : (response.message ?? "登录成功。"))
        }
    }

    private func withBusyState(_ operation: @escaping () async throws -> Void) async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
