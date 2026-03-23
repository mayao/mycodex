import SwiftUI

struct BootBrandBackdrop: View {
    private let baseColor = Color(red: 22.0 / 255.0, green: 46.0 / 255.0, blue: 80.0 / 255.0)

    var body: some View {
        baseColor
            .ignoresSafeArea()
    }
}

struct BootBrandWordmark: View {
    var logoSize: CGFloat = 88
    var titleSize: CGFloat = 34
    var subtitleSize: CGFloat = 11

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 22.0 / 255.0, green: 46.0 / 255.0, blue: 80.0 / 255.0))
                    .frame(width: logoSize, height: logoSize)

                Image("BootLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
            }
            .shadow(color: Color.black.opacity(0.24), radius: 14, y: 6)

            Text("MyInvAI")
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Color.white)

            Text("YOUR BEST INVESTMENT PARTNER")
                .font(.system(size: subtitleSize, weight: .medium, design: .rounded))
                .tracking(2.6)
                .foregroundStyle(Color.white.opacity(0.82))
        }
    }
}
