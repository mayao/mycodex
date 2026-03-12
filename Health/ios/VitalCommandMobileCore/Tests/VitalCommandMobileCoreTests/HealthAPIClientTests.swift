import Foundation
import Testing
@testable import VitalCommandMobileCore

struct HealthAPIClientTests {
    @Test
    func decodesDashboardPayload() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "generatedAt": "2026-03-10T12:00:00.000Z",
              "disclaimer": "test",
              "overviewHeadline": "概览",
              "overviewNarrative": "说明",
              "overviewDigest": {
                "headline": "概览",
                "summary": "摘要",
                "goodSignals": ["稳定"],
                "needsAttention": ["Lp(a)"],
                "longTermRisks": ["血脂"],
                "actionPlan": ["复查"]
              },
              "overviewFocusAreas": ["血脂"],
              "overviewSpotlights": [
                { "label": "LDL-C", "value": "2.30 mmol/L", "tone": "positive", "detail": "下降" }
              ],
              "sourceDimensions": [
                { "key": "annual_exam", "label": "体检", "latestAt": "2026-03-01", "status": "ready", "summary": "已同步", "highlight": "年度体检" }
              ],
              "dimensionAnalyses": [
                {
                  "key": "integrated",
                  "kicker": "总览",
                  "title": "综合分析",
                  "summary": "摘要",
                  "goodSignals": ["稳定"],
                  "needsAttention": ["Lp(a)"],
                  "longTermRisks": ["血脂"],
                  "actionPlan": ["保持记录"],
                  "metrics": [
                    { "label": "体重", "value": "70kg", "detail": "稳定", "tone": "neutral" }
                  ]
                }
              ],
              "importOptions": [
                { "key": "annual_exam", "title": "体检", "description": "导入体检", "formats": ["csv"], "hints": ["使用模板"] }
              ],
              "overviewCards": [
                { "metricCode": "lipid.ldl_c", "label": "LDL-C", "value": "2.30", "trend": "下降", "status": "improving", "abnormalFlag": "normal", "meaning": "血脂趋势" }
              ],
              "annualExam": null,
              "geneticFindings": [],
              "keyReminders": [
                { "id": "1", "title": "关注 LDL", "severity": "medium", "summary": "需要复查", "suggestedAction": "继续运动", "indicatorMeaning": null, "practicalAdvice": null }
              ],
              "watchItems": [],
              "latestNarrative": {
                "provider": "mock",
                "model": "mock",
                "prompt": { "templateId": "1", "version": "v1", "systemPrompt": "a", "userPrompt": "b" },
                "output": {
                  "periodKind": "day",
                  "headline": "今日摘要",
                  "mostImportantChanges": ["变化"],
                  "possibleReasons": ["原因"],
                  "priorityActions": ["动作"],
                  "continueObserving": ["观察"],
                  "disclaimer": "非医疗诊断"
                }
              },
              "charts": {
                "lipid": {
                  "title": "血脂",
                  "description": "desc",
                  "defaultRange": "90d",
                  "data": [
                    { "date": "2026-03-01", "ldl": 2.3, "lpa": 85 }
                  ],
                  "lines": [
                    { "key": "ldl", "label": "LDL-C", "color": "#ff0000", "unit": "mmol/L", "yAxisId": "left" }
                  ]
                },
                "bodyComposition": { "title": "体脂", "description": "desc", "defaultRange": "30d", "data": [], "lines": [] },
                "activity": { "title": "运动", "description": "desc", "defaultRange": "30d", "data": [], "lines": [] },
                "recovery": { "title": "恢复", "description": "desc", "defaultRange": "30d", "data": [], "lines": [] }
              },
              "latestReports": []
            }
            """
        )
        let client = HealthAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:3000")!),
            session: session
        )

        let payload = try await client.fetchDashboard()

        #expect(payload.overviewSpotlights.count == 1)
        #expect(payload.charts.lipid.data.first?.values["ldl"] == 2.3)
        #expect(payload.importOptions.first?.key == .annualExam)
    }

    @Test
    func buildsMultipartImportRequest() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "accepted": true,
              "task": {
                "importTaskId": "task-1",
                "title": "年度体检导入",
                "importerKey": "annual_exam",
                "taskType": "annual_exam_import",
                "taskStatus": "running",
                "sourceType": "annual_exam_tabular",
                "sourceFile": "annual_exam.csv",
                "startedAt": "2026-03-10T12:00:00.000Z",
                "finishedAt": null,
                "totalRecords": 10,
                "successRecords": 0,
                "failedRecords": 0,
                "parseMode": "tabular"
              }
            }
            """
        )
        let client = HealthAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:3000")!),
            session: session
        )

        let response = try await client.importData(
            importerKey: .annualExam,
            fileName: "annual_exam.csv",
            mimeType: "text/csv",
            fileData: Data("col1,col2".utf8)
        )

        let request = try #require(session.lastRequest)
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(contentType.contains("multipart/form-data"))
        #expect(body.contains("name=\"importerKey\""))
        #expect(body.contains("annual_exam"))
        #expect(response.task.importTaskId == "task-1")
    }

    @Test
    func surfacesServerErrors() async throws {
        let session = MockSession(
            statusCode: 404,
            body: """
            {
              "error": {
                "id": "err-1",
                "message": "未找到对应报告。"
              }
            }
            """
        )
        let client = HealthAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:3000")!),
            session: session
        )

        do {
            _ = try await client.fetchReportDetail(snapshotId: "missing")
            Issue.record("Expected a server error to be thrown")
        } catch let error as HealthAPIClientError {
            guard case let .server(statusCode, message) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }

            #expect(statusCode == 404)
            #expect(message == "未找到对应报告。")
        }
    }

    @Test
    func sendsAIChatRequest() async throws {
        let session = MockSession(
            statusCode: 200,
            body: """
            {
              "reply": {
                "id": "assistant-1",
                "role": "assistant",
                "content": "先把睡眠和恢复节奏稳定下来。",
                "createdAt": "2026-03-11T12:00:00.000Z"
              },
              "provider": "mock",
              "model": "healthai-chat-fallback-v1"
            }
            """
        )
        let client = HealthAPIClient(
            configuration: AppServerConfiguration(baseURL: URL(string: "http://localhost:3000")!),
            session: session
        )

        let response = try await client.chatWithAI(
            AIChatRequest(
                messages: [
                    AIChatMessage(role: .user, content: "最近我最该优先做什么？")
                ]
            )
        )

        let request = try #require(session.lastRequest)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/ai/chat")
        #expect(response.reply.role == .assistant)
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
