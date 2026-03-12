import SwiftUI
import VitalCommandMobileCore

struct TrendsScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var viewModel = TrendsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("正在加载趋势")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case let .failed(message):
                    EmptyStateCard(
                        title: "趋势图加载失败",
                        message: message,
                        actionTitle: "重试"
                    ) {
                        Task { await reload() }
                    }
                    .padding()

                case let .loaded(payload):
                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(
                                [
                                    payload.charts.lipid,
                                    payload.charts.bodyComposition,
                                    payload.charts.activity,
                                    payload.charts.recovery
                                ],
                                id: \.title
                            ) { chart in
                                NavigationLink {
                                    TrendDetailScreen(chart: chart)
                                } label: {
                                    TrendChartCard(chart: chart)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                    .background(Color.appGroupedBackground)
                }
            }
            .navigationTitle("趋势")
        }
        .task(id: settings.dashboardReloadKey) {
            await reload()
        }
        .onAppear {
            Task {
                await reload()
            }
        }
    }

    private func reload() async {
        do {
            let client = try settings.makeClient()
            await viewModel.load(using: client)
        } catch {
            viewModel.setError(error.localizedDescription)
        }
    }
}
