import Foundation
import XCTest
@testable import PortfolioWorkbenchMobileCore

final class PortfolioWorkbenchAPIClientTests: XCTestCase {
    func testDecodesDashboardPayload() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "generated_at": "2026-03-10T12:00:00.000Z",
              "analysis_date_cn": "2026年3月10日",
              "snapshot_date": "2026-03-08",
              "hero": {
                "title": "个人投资工作台",
                "subtitle": "headline",
                "overview": "overview",
                "snapshot_window": "2026-03-01 至 2026-03-08",
                "live_note": "cache",
                "macro_note": "macro",
                "primary_theme": "港股互联网",
                "primary_broker": "Longbridge"
              },
              "summary_cards": [
                { "label": "净资产", "value": "HK$1,000,000", "detail": "detail", "tone": "up" }
              ],
              "source_health": { "parsed_count": 0, "cached_count": 5, "error_count": 0 },
              "key_drivers": [
                { "title": "driver", "detail": "detail", "tone": "warn" }
              ],
              "risk_flags": [
                { "title": "risk", "detail": "detail", "tone": "down" }
              ],
              "action_center": {
                "headline": "headline",
                "overview": "overview",
                "priority_actions": [
                  { "title": "减仓", "detail": "处理弱势仓位" }
                ],
                "disclaimer": "disclaimer"
              },
              "action_blocks": [
                { "label": "组合", "title": "减仓", "detail": "处理弱势仓位", "badge": "待执行", "tone": "down" }
              ],
              "health_radar": [
                { "label": "质量", "value": 82.1, "summary": "summary" }
              ],
              "allocation_groups": {
                "themes": [
                  { "label": "港股互联网", "value_hkd": 1000, "weight_pct": 40.5, "count": 3, "core_holdings": ["腾讯"], "core_symbols": ["00700.HK"] }
                ],
                "markets": [],
                "brokers": []
              },
              "macro_topics": [
                { "id": "macro-1", "name": "贸易与出口管制", "severity": "高", "summary": "summary", "headline": "headline", "impact_labels": "AI", "score": -2, "source": "Reuters", "published_at": "2026-03-08", "impact_weight_pct": 66.67 }
              ],
              "strategy_views": [
                { "title": "质量复利", "tag": "权重 30%", "tone": "up", "summary": "summary" }
              ],
              "positions": [
                {
                  "symbol": "00700.HK",
                  "name": "腾讯控股",
                  "name_en": "Tencent",
                  "market": "HK",
                  "currency": "HKD",
                  "category_name": "港股互联网",
                  "style_label": "核心资产",
                  "fundamental_label": "强",
                  "weight_pct": 18.69,
                  "statement_value_hkd": 2015718,
                  "statement_pnl_pct": 26.46,
                  "statement_pnl_hkd": 378290.16,
                  "current_price": 519,
                  "change_pct": 3.39,
                  "change_pct_5d": 0.19,
                  "trade_date": "2026-03-08",
                  "signal_score": 58,
                  "signal_zone": "中性跟踪",
                  "trend_state": "弱势下行",
                  "position_label": "区间低位",
                  "macro_signal": "中性",
                  "news_signal": "中性",
                  "account_count": 3,
                  "stance": "持有但控上限",
                  "role": "核心底仓",
                  "summary": "summary",
                  "action": "action",
                  "watch_items": "游戏审批",
                  "sparkline_points": [100, 102, 101]
                }
              ],
              "spotlight_positions": [],
              "accounts": [],
              "recent_trades": [],
              "derivatives": [
                {
                  "symbol": "R1FA00Y49GZMT-C010",
                  "description": "FCN - TSLA US HIMS US",
                  "currency": "USD",
                  "quantity": null,
                  "market_value": null,
                  "unrealized_pnl": null,
                  "estimated_notional": 50000,
                  "estimated_notional_hkd": 390900,
                  "underlyings": ["HIMS"],
                  "broker": "Longbridge",
                  "account_id": "longbridge_h10096545"
                }
              ],
              "statement_sources": [],
              "reference_sources": [],
              "update_guide": ["guide"]
            }
            """
        )
        let client = PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:8008/")!),
            session: session
        )

        let payload = try await client.fetchDashboard()

        XCTAssertEqual(payload.summaryCards.count, 1)
        XCTAssertEqual(payload.positions.first?.symbol, "00700.HK")
        XCTAssertEqual(payload.macroTopics.first?.id, "macro-1")
        XCTAssertNil(payload.derivatives.first?.quantity)
    }

    func testBuildsMultipartUploadRequest() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "message": "uploaded",
              "payload": {
                "generated_at": "2026-03-10T12:00:00.000Z",
                "analysis_date_cn": "2026年3月10日",
                "snapshot_date": "2026-03-08",
                "hero": {
                  "title": "个人投资工作台",
                  "subtitle": "headline",
                  "overview": "overview",
                  "snapshot_window": "2026-03-01 至 2026-03-08",
                  "live_note": "cache",
                  "macro_note": "macro",
                  "primary_theme": "港股互联网",
                  "primary_broker": "Longbridge"
                },
                "summary_cards": [
                  { "label": "净资产", "value": "HK$1,000,000", "detail": "detail", "tone": "up" }
                ],
                "source_health": { "parsed_count": 1, "cached_count": 4, "error_count": 0 },
                "key_drivers": [],
                "risk_flags": [],
                "action_center": {
                  "headline": "headline",
                  "overview": "overview",
                  "priority_actions": [],
                  "disclaimer": "disclaimer"
                },
                "action_blocks": [
                  { "label": "组合", "title": "继续跟踪", "detail": "等待新结单完成同步", "badge": "待执行", "tone": "neutral" }
                ],
                "health_radar": [],
                "allocation_groups": { "themes": [], "markets": [], "brokers": [] },
                "macro_topics": [],
                "strategy_views": [],
                "positions": [],
                "spotlight_positions": [],
                "accounts": [],
                "recent_trades": [],
                "derivatives": [],
                "statement_sources": [],
                "reference_sources": [],
                "update_guide": ["guide"]
              }
            }
            """
        )
        let client = PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:8008/")!),
            session: session
        )

        let response = try await client.uploadStatement(
            accountID: "tiger_1",
            fileName: "statement.pdf",
            mimeType: "application/pdf",
            fileData: Data("pdf".utf8)
        )

        XCTAssertEqual(response.message, "uploaded")
        XCTAssertEqual(response.payload?.sourceHealth.parsedCount, 1)
        XCTAssertNotNil(session.lastRequest)
        XCTAssertTrue((session.lastRequest?.value(forHTTPHeaderField: "Content-Type") ?? "").contains("multipart/form-data"))
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"account_id\""))
        XCTAssertTrue(body.contains("name=\"statement_file\"; filename=\"statement.pdf\""))
    }

    func testDecodesHoldingDetailPayload() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "generated_at": "2026-03-10T12:00:00.000Z",
              "analysis_date_cn": "2026年3月10日",
              "share_mode": false,
              "hero": {
                "symbol": "00700.HK",
                "name": "腾讯控股",
                "category_name": "港股互联网",
                "style_label": "核心资产",
                "fundamental_label": "强",
                "signal_score": 58,
                "signal_zone": "中性跟踪",
                "trend_state": "弱势下行",
                "position_label": "区间低位",
                "macro_signal": "中性",
                "news_signal": "中性",
                "current_price": 519,
                "change_pct": 3.39,
                "change_pct_5d": 0.19,
                "trade_date": "2026-03-08",
                "price_source": "cache",
                "price_source_label": "本地日更快照",
                "news_headline": "headline"
              },
              "source_meta": {
                "price_source_label": "本地日更快照",
                "live_updated_at": "2026-03-08T10:00:00Z",
                "macro_updated_at": "2026-03-08T10:00:00Z",
                "trade_date": "2026-03-08"
              },
              "executive_summary": ["summary"],
              "focus_cards": [
                { "label": "行情状态", "value": "2026-03-08", "detail": "cache" }
              ],
              "signal_rows": [
                { "label": "基本面", "score": 2, "comment": "comment" }
              ],
              "signal_matrix": {
                "columns": [{ "key": "fundamental", "label": "基本面" }],
                "rows": [{
                  "symbol": "00700.HK",
                  "name": "腾讯控股",
                  "is_target": true,
                  "signal_score": 58,
                  "signal_zone": "中性跟踪",
                  "trend_state": "弱势下行",
                  "cells": [{ "label": "基本面", "score": 2 }]
                }]
              },
              "portfolio_context": [
                { "label": "组合定位", "value": "核心底仓" }
              ],
              "price_cards": [
                { "label": "当前价格", "value": "HK$519.00", "delta": "+3.39%" }
              ],
              "account_rows": [
                { "label": "Tiger", "account_id": "tiger_1", "quantity": 100, "statement_value": 51900, "statement_pnl_pct": 5.2 }
              ],
              "related_trades": [
                { "date": "2026-03-06", "side": "买入", "broker": "Tiger", "quantity": 100, "price": 500, "currency": "HKD" }
              ],
              "derivative_rows": [
                { "symbol": "00700.HK", "description": "结构性产品", "estimated_notional_hkd": 50000 }
              ],
              "bull_case": ["bull"],
              "bear_case": ["bear"],
              "watchlist": ["watch"],
              "action_plan": ["action"],
              "peers": [
                {
                  "symbol": "09988.HK",
                  "name": "阿里巴巴-W",
                  "signal_score": 52,
                  "trend_state": "弱势下行",
                  "current_price": 120.5,
                  "change_pct": 1.2,
                  "normalized_history": [
                    { "date": "2026-03-01", "price": 100 },
                    { "date": "2026-03-02", "price": 101 }
                  ],
                  "factor_scores": { "fundamental": 1 },
                  "signal_zone": "中性跟踪"
                }
              ],
              "history": [
                { "date": "2026-03-01", "price": 500 }
              ],
              "comparison_history": [
                {
                  "symbol": "00700.HK",
                  "name": "腾讯控股",
                  "is_target": true,
                  "points": [{ "date": "2026-03-01", "price": 100 }]
                }
              ],
              "holding_note": {
                "symbol": "00700.HK",
                "name": "腾讯控股",
                "weight_pct": 18.69,
                "role": "核心底仓",
                "stance": "持有但控上限",
                "thesis": "thesis",
                "watch_items": "watch",
                "risk": "risk",
                "action": "action",
                "current_price": 519,
                "change_pct": 3.39,
                "position_label": "区间低位",
                "trend_state": "弱势下行",
                "macro_signal": "中性",
                "news_signal": "中性",
                "fundamental_label": "强",
                "signal_score": 58,
                "signal_zone": "中性跟踪",
                "statement_pnl_pct": 26.46,
                "statement_value_hkd": 2015718,
                "category_name": "港股互联网"
              }
            }
            """
        )
        let client = PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:8008/")!),
            session: session
        )

        let payload = try await client.fetchHoldingDetail(symbol: "00700.HK")

        XCTAssertEqual(payload.hero.symbol, "00700.HK")
        XCTAssertEqual(payload.peers.first?.normalizedHistory.count, 2)
        XCTAssertEqual(payload.comparisonHistory.first?.points.first?.price, 100)
    }

    func testSurfacesStringServerErrors() async throws {
        let session = MockSession(
            statusCode: 400,
            body: """
            { "error": "缺少股票代码。" }
            """
        )
        let client = PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:8008/")!),
            session: session
        )

        do {
            _ = try await client.fetchHoldingDetail(symbol: "")
            XCTFail("Expected server error")
        } catch let error as PortfolioWorkbenchAPIClientError {
            guard case let .server(statusCode, message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }

            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(message, "缺少股票代码。")
        }
    }

    func testAddsAuthorizationHeaderToAuthenticatedRequests() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "user": {
                "user_id": "usr_dev_abc123",
                "display_name": "Matt 的账户",
                "phone_number_masked": null,
                "auth_provider": "device",
                "is_owner": false
              }
            }
            """
        )
        let client = PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(
                baseURL: URL(string: "http://localhost:8008/")!,
                sessionToken: "session-token"
            ),
            session: session
        )

        let payload = try await client.fetchCurrentSession()

        XCTAssertEqual(payload.user.userId, "usr_dev_abc123")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/mobile/auth/session")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
    }

    func testAddsAIConfigurationHeaderToRequests() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "generated_at": "2026-03-10T12:00:00.000Z",
              "analysis_date_cn": "2026年3月10日",
              "action_blocks": [],
              "ai_updated_at": "2026-03-10T12:00:00.000Z",
              "ai_engine_label": "Kimi moonshot-v1-8k",
              "ai_status_message": "AI 洞察已刷新。"
            }
            """
        )
        let client = PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(
                baseURL: URL(string: "http://localhost:8008/")!,
                aiRequestConfiguration: AIRequestConfiguration(
                    primaryProvider: .anthropic,
                    enableFallbacks: true,
                    providers: [
                        AIProviderRequestConfiguration(
                            provider: .anthropic,
                            model: "claude-sonnet-4-5-20250929",
                            apiKey: "anthropic-key"
                        ),
                        AIProviderRequestConfiguration(
                            provider: .kimi,
                            model: "moonshot-v1-8k",
                            apiKey: "kimi-key"
                        )
                    ]
                )
            ),
            session: session
        )

        _ = try await client.fetchDashboardAI(refresh: true)

        let encodedHeader = try XCTUnwrap(session.lastRequest?.value(forHTTPHeaderField: "X-MyInvAI-AI-Config"))
        let decodedData = try XCTUnwrap(Data(base64Encoded: encodedHeader))
        let decoded = try JSONDecoder().decode(AIRequestConfiguration.self, from: decodedData)
        XCTAssertEqual(decoded.primaryProvider, .anthropic)
        XCTAssertTrue(decoded.enableFallbacks)
        XCTAssertEqual(decoded.providers.count, 2)
        XCTAssertEqual(decoded.providers.last?.provider, .kimi)
    }

    func testFetchesAIServiceStatus() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "primary_provider": "kimi",
              "enable_fallbacks": true,
              "provider_order": ["kimi", "anthropic", "gemini"],
              "uses_service_config": true,
              "note": "App 端仅切换 provider 与模型，真正的 API Key 由服务端托管。",
              "providers": [
                {
                  "provider": "kimi",
                  "label": "Kimi",
                  "model": "kimi-for-coding",
                  "base_url": "https://api.kimi.com/coding/v1",
                  "preset": "kimi_coding",
                  "credential_source": "service_config",
                  "access_state": "ready",
                  "access_message": "服务端已配置，可发起访问。",
                  "checked_at": null,
                  "latency_ms": null
                }
              ]
            }
            """
        )
        let client = PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:8008/")!),
            session: session
        )

        let payload = try await client.fetchAIServiceStatus()

        XCTAssertEqual(payload.primaryProvider, .kimi)
        XCTAssertEqual(payload.providerOrder.first, .kimi)
        XCTAssertEqual(payload.providers.first?.preset, "kimi_coding")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/mobile/ai-service-status")
    }

    func testBuildsOwnerDevLoginRequest() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "session_token": "owner-token",
              "user": {
                "user_id": "usr_owner_local",
                "display_name": "本机数据拥有者",
                "phone_number_masked": null,
                "auth_provider": "owner",
                "is_owner": true
              },
              "message": "已进入本机 Owner 调试会话。"
            }
            """
        )
        let client = PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:8008/")!),
            session: session
        )

        let payload = try await client.loginAsLocalOwner()

        XCTAssertEqual(payload.user.userId, "usr_owner_local")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/mobile/auth/dev/owner")
        XCTAssertEqual(String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8), "{}")
    }

    func testBuildsDeviceBootstrapRequest() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "session_token": "device-token",
              "user": {
                "user_id": "usr_dev_abc123",
                "display_name": "Matt 的账户",
                "phone_number_masked": null,
                "auth_provider": "device",
                "is_owner": false
              },
              "message": "已为当前设备创建独立账号。",
              "device_credentials": {
                "assigned_user_id": "usr_dev_abc123",
                "device_name": "Matt 的 iPhone",
                "default_password": "MIA-ABCD123456",
                "is_new_device": true
              }
            }
            """
        )
        let client = PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:8008/")!),
            session: session
        )

        let payload = try await client.bootstrapDeviceAccount(
            deviceID: "dev_1234567890abcdef",
            deviceName: "Matt 的 iPhone"
        )

        XCTAssertEqual(payload.user.authProvider, "device")
        XCTAssertEqual(payload.deviceCredentials?.defaultPassword, "MIA-ABCD123456")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/mobile/auth/device/bootstrap")
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("device_id"))
        XCTAssertTrue(body.contains("Matt 的 iPhone"))
    }

    func testLocalMockPhoneSessionProvidesEmbeddedDashboard() async throws {
        let session = PortfolioWorkbenchLocalMock.makePhoneSession()
        let client = PortfolioWorkbenchLocalMock.makeClient(
            currentUser: session.user,
            sessionToken: session.sessionToken
        )

        let dashboard = try await client.fetchDashboard()
        let detail = try await client.fetchHoldingDetail(symbol: "NVDA")
        let importCenter = try await client.fetchImportCenter()

        XCTAssertEqual(dashboard.hero.title, "MyInvAI")
        XCTAssertEqual(dashboard.positions.first?.symbol, "NVDA")
        XCTAssertEqual(detail.hero.symbol, "NVDA")
        XCTAssertEqual(importCenter.user?.userId, session.user.userId)
    }

    func testLocalMockRejectsUnexpectedPhoneCredentials() async throws {
        let client = PortfolioWorkbenchLocalMock.makeClient(currentUser: nil, sessionToken: nil)

        do {
            _ = try await client.loginWithPhone(
                phoneNumber: "13900000000",
                code: PortfolioWorkbenchLocalMock.mockVerificationCode
            )
            XCTFail("Expected local mock credential validation failure")
        } catch let error as PortfolioWorkbenchAPIClientError {
            guard case let .server(statusCode, message) = error else {
                XCTFail("Unexpected error \(error)")
                return
            }

            XCTAssertEqual(statusCode, 400)
            XCTAssertTrue(message.contains(PortfolioWorkbenchLocalMock.mockPhoneNumber))
        }
    }
}

private final class MockSession: URLSessioning, @unchecked Sendable {
    private let statusCode: Int
    private let body: String
    var lastRequest: URLRequest?

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return (
            Data(body.utf8),
            HTTPURLResponse(
                url: request.url ?? URL(string: "http://localhost")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}
