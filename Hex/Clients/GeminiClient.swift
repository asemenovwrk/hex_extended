import Dependencies
import Foundation
import HexCore

private let geminiLogger = HexLog.transcription

// MARK: - Result type

struct GeminiResult: Sendable {
	let text: String
	let duration: TimeInterval
}

// MARK: - Client Interface

struct GeminiClient: Sendable {
	var postProcess: @Sendable (_ text: String, _ prompt: String, _ apiKey: String, _ model: String, _ thinkingBudget: Int) async throws -> GeminiResult
	var transcribeAudio: @Sendable (_ audioURL: URL, _ prompt: String, _ apiKey: String, _ model: String, _ thinkingBudget: Int) async throws -> GeminiResult

	init(
		postProcess: @escaping @Sendable (String, String, String, String, Int) async throws -> GeminiResult = { _, _, _, _, _ in GeminiResult(text: "", duration: 0) },
		transcribeAudio: @escaping @Sendable (URL, String, String, String, Int) async throws -> GeminiResult = { _, _, _, _, _ in GeminiResult(text: "", duration: 0) }
	) {
		self.postProcess = postProcess
		self.transcribeAudio = transcribeAudio
	}
}

extension GeminiClient: DependencyKey {
	static var liveValue: Self {
		Self(
			postProcess: { text, prompt, apiKey, model, thinkingBudget in
				try await GeminiClientLive.postProcess(text: text, prompt: prompt, apiKey: apiKey, model: model, thinkingBudget: thinkingBudget)
			},
			transcribeAudio: { audioURL, prompt, apiKey, model, thinkingBudget in
				try await GeminiClientLive.transcribeAudio(audioURL: audioURL, prompt: prompt, apiKey: apiKey, model: model, thinkingBudget: thinkingBudget)
			}
		)
	}

	static var testValue: Self {
		Self()
	}
}

extension DependencyValues {
	var gemini: GeminiClient {
		get { self[GeminiClient.self] }
		set { self[GeminiClient.self] = newValue }
	}
}

// MARK: - Live Implementation

private enum GeminiClientLive {
	static func postProcess(text: String, prompt: String, apiKey: String, model: String, thinkingBudget: Int) async throws -> GeminiResult {
		let start = Date()
		let body: [String: Any] = [
			"systemInstruction": [
				"parts": [["text": prompt]]
			],
			"contents": [
				["parts": [["text": text]]]
			]
		]
		let resultText = try await sendRequest(body: body, apiKey: apiKey, model: model, timeout: 15, thinkingBudget: thinkingBudget)
		return GeminiResult(text: resultText, duration: Date().timeIntervalSince(start))
	}

	static func transcribeAudio(audioURL: URL, prompt: String, apiKey: String, model: String, thinkingBudget: Int) async throws -> GeminiResult {
		let start = Date()
		let audioData = try Data(contentsOf: audioURL)
		let base64Audio = audioData.base64EncodedString()

		let body: [String: Any] = [
			"systemInstruction": [
				"parts": [["text": prompt]]
			],
			"contents": [
				["parts": [
					["inlineData": ["mimeType": "audio/wav", "data": base64Audio]],
				]]
			]
		]
		let resultText = try await sendRequest(body: body, apiKey: apiKey, model: model, timeout: 30, thinkingBudget: thinkingBudget)
		return GeminiResult(text: resultText, duration: Date().timeIntervalSince(start))
	}

	private static func sendRequest(body bodyInput: [String: Any], apiKey: String, model: String, timeout: TimeInterval, thinkingBudget: Int) async throws -> String {
		var body = bodyInput
		body["generationConfig"] = [
			"thinkingConfig": ["thinkingBudget": thinkingBudget]
		]
		let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = timeout
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw GeminiError.invalidResponse
		}

		guard httpResponse.statusCode == 200 else {
			let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
			geminiLogger.error("Gemini API error \(httpResponse.statusCode): \(errorBody)")
			throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
		}

		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let candidates = json["candidates"] as? [[String: Any]],
			  let firstCandidate = candidates.first,
			  let content = firstCandidate["content"] as? [String: Any],
			  let parts = content["parts"] as? [[String: Any]],
			  let firstPart = parts.first,
			  let resultText = firstPart["text"] as? String
		else {
			throw GeminiError.parsingFailed
		}

		return resultText.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

// MARK: - Errors

enum GeminiError: LocalizedError {
	case invalidResponse
	case apiError(statusCode: Int, message: String)
	case parsingFailed

	var errorDescription: String? {
		switch self {
		case .invalidResponse:
			return "Invalid response from Gemini API"
		case let .apiError(statusCode, message):
			return "Gemini API error (\(statusCode)): \(message)"
		case .parsingFailed:
			return "Failed to parse Gemini API response"
		}
	}
}
