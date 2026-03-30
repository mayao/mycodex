import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        TabView(selection: $settings.selectedTab) {
            HomeScreen()
                .tag(AppTab.home)
                .tabItem {
                    Label("健康", systemImage: "heart.fill")
                }

            HealthPlanScreen()
                .tag(AppTab.plan)
                .tabItem {
                    Label("计划", systemImage: "list.clipboard.fill")
                }

            ReportsScreen()
                .tag(AppTab.reports)
                .tabItem {
                    Label("报告", systemImage: "doc.text.image")
                }

            DataHubScreen()
                .tag(AppTab.data)
                .tabItem {
                    Label("数据", systemImage: "square.and.arrow.down.on.square")
                }
        }
    }
}
