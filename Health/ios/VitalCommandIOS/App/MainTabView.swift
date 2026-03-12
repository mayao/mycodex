import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeScreen()
                .tabItem {
                    Label("健康", systemImage: "heart.fill")
                }

            HealthPlanScreen()
                .tabItem {
                    Label("计划", systemImage: "list.clipboard.fill")
                }

            ReportsScreen()
                .tabItem {
                    Label("报告", systemImage: "doc.text.image")
                }

            DataHubScreen()
                .tabItem {
                    Label("数据", systemImage: "square.and.arrow.down.on.square")
                }
        }
    }
}
