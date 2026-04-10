import Dependencies
import Foundation
import HexCore

private let aiLogger = HexLog.transcription

// MARK: - Result type

struct AIResult: Sendable {
	let text: String
	let duration: TimeInterval
	let inputTokens: Int?
	let outputTokens: Int?
}

// MARK: - Provider detection

enum AIProvider {
	case gemini
	case openai

	static func from(model: String) -> AIProvider {
		if model.hasPrefix("gpt-") || model.hasPrefix("o3") || model.hasPrefix("o4") {
			return .openai
		}
		return .gemini
	}
}

// MARK: - Client Interface

struct GeminiClient: Sendable {
	var postProcess: @Sendable (_ text: String, _ prompt: String, _ apiKey: String, _ model: String, _ thinkingBudget: Int, _ imageData: Data?, _ openaiDetail: String) async throws -> AIResult
	var transcribeAudio: @Sendable (_ audioURL: URL, _ prompt: String, _ apiKey: String, _ model: String, _ thinkingBudget: Int, _ imageData: Data?, _ openaiDetail: String) async throws -> AIResult

	init(
		postProcess: @escaping @Sendable (String, String, String, String, Int, Data?, String) async throws -> AIResult = { _, _, _, _, _, _, _ in AIResult(text: "", duration: 0, inputTokens: nil, outputTokens: nil) },
		transcribeAudio: @escaping @Sendable (URL, String, String, String, Int, Data?, String) async throws -> AIResult = { _, _, _, _, _, _, _ in AIResult(text: "", duration: 0, inputTokens: nil, outputTokens: nil) }
	) {
		self.postProcess = postProcess
		self.transcribeAudio = transcribeAudio
	}
}

extension GeminiClient: DependencyKey {
	static var liveValue: Self {
		Self(
			postProcess: { text, prompt, apiKey, model, thinkingBudget, imageData, openaiDetail in
				try await AIClientLive.postProcess(text: text, prompt: prompt, apiKey: apiKey, model: model, thinkingBudget: thinkingBudget, imageData: imageData, openaiDetail: openaiDetail)
			},
			transcribeAudio: { audioURL, prompt, apiKey, model, thinkingBudget, imageData, openaiDetail in
				try await AIClientLive.transcribeAudio(audioURL: audioURL, prompt: prompt, apiKey: apiKey, model: model, thinkingBudget: thinkingBudget, imageData: imageData, openaiDetail: openaiDetail)
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

private enum AIClientLive {
	private struct RawResult {
		let text: String
		let inputTokens: Int?
		let outputTokens: Int?
	}

	static func postProcess(text: String, prompt: String, apiKey: String, model: String, thinkingBudget: Int, imageData: Data?, openaiDetail: String) async throws -> AIResult {
		let start = Date()
		let provider = AIProvider.from(model: model)
		let raw: RawResult

		// When a screenshot is included, nudge the model to use it as visual context.
		let effectivePrompt = imageData != nil
			? prompt + "\n\nYou also receive a screenshot of the user's active window for visual context. Use it to better understand what the user is referring to, but output only the corrected transcription text — do not describe the image."
			: prompt

		switch provider {
		case .gemini:
			var userParts: [[String: Any]] = []
			if let imageData {
				let base64 = imageData.base64EncodedString()
				userParts.append(["inlineData": ["mimeType": "image/jpeg", "data": base64]])
			}
			userParts.append(["text": text])
			raw = try await geminiRequest(
				systemPrompt: effectivePrompt,
				userParts: userParts,
				apiKey: apiKey, model: model, timeout: 20, thinkingBudget: thinkingBudget
			)
		case .openai:
			if let imageData {
				let base64 = imageData.base64EncodedString()
				let userContent: [[String: Any]] = [
					["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)", "detail": openaiDetail]],
					["type": "text", "text": text]
				]
				raw = try await openaiRequest(
					systemPrompt: effectivePrompt,
					userContentParts: userContent,
					apiKey: apiKey, model: model, timeout: 20, thinkingBudget: thinkingBudget
				)
			} else {
				raw = try await openaiRequest(
					systemPrompt: effectivePrompt,
					userContent: text,
					apiKey: apiKey, model: model, timeout: 15, thinkingBudget: thinkingBudget
				)
			}
		}

		return AIResult(text: raw.text, duration: Date().timeIntervalSince(start), inputTokens: raw.inputTokens, outputTokens: raw.outputTokens)
	}

	static func transcribeAudio(audioURL: URL, prompt: String, apiKey: String, model: String, thinkingBudget: Int, imageData: Data?, openaiDetail: String) async throws -> AIResult {
		let start = Date()
		let provider = AIProvider.from(model: model)
		let raw: RawResult

		let effectivePrompt = imageData != nil
			? prompt + "\n\nYou also receive a screenshot of the user's active window for visual context. Use it to better understand what the user is referring to while transcribing the audio."
			: prompt

		switch provider {
		case .gemini:
			let audioData = try Data(contentsOf: audioURL)
			let base64Audio = audioData.base64EncodedString()
			var userParts: [[String: Any]] = []
			if let imageData {
				let base64Image = imageData.base64EncodedString()
				userParts.append(["inlineData": ["mimeType": "image/jpeg", "data": base64Image]])
			}
			userParts.append(["inlineData": ["mimeType": "audio/wav", "data": base64Audio]])
			raw = try await geminiRequest(
				systemPrompt: effectivePrompt,
				userParts: userParts,
				apiKey: apiKey, model: model, timeout: 30, thinkingBudget: thinkingBudget
			)
		case .openai:
			let audioData = try Data(contentsOf: audioURL)
			let base64Audio = audioData.base64EncodedString()
			var userContent: [[String: Any]] = []
			if let imageData {
				let base64Image = imageData.base64EncodedString()
				userContent.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)", "detail": openaiDetail]])
			}
			userContent.append(["type": "input_audio", "input_audio": ["data": base64Audio, "format": "wav"]])
			raw = try await openaiRequest(
				systemPrompt: effectivePrompt,
				userContentParts: userContent,
				apiKey: apiKey, model: model, timeout: 30, thinkingBudget: thinkingBudget
			)
		}

		return AIResult(text: raw.text, duration: Date().timeIntervalSince(start), inputTokens: raw.inputTokens, outputTokens: raw.outputTokens)
	}

	// MARK: - Gemini API

	private static func geminiRequest(
		systemPrompt: String,
		userParts: [[String: Any]],
		apiKey: String, model: String, timeout: TimeInterval, thinkingBudget: Int
	) async throws -> RawResult {
		let body: [String: Any] = [
			"systemInstruction": ["parts": [["text": systemPrompt]]],
			"contents": [["parts": userParts]],
			"generationConfig": ["thinkingConfig": ["thinkingBudget": thinkingBudget]]
		]
		let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = timeout
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)
		try validateHTTPResponse(response, data: data)

		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let candidates = json["candidates"] as? [[String: Any]],
			  let firstCandidate = candidates.first,
			  let content = firstCandidate["content"] as? [String: Any],
			  let parts = content["parts"] as? [[String: Any]],
			  let firstPart = parts.first,
			  let resultText = firstPart["text"] as? String
		else { throw AIError.parsingFailed }

		// Parse usage: usageMetadata.promptTokenCount / candidatesTokenCount
		let usage = json["usageMetadata"] as? [String: Any]
		let inputTokens = usage?["promptTokenCount"] as? Int
		let outputTokens = usage?["candidatesTokenCount"] as? Int

		return RawResult(text: resultText.trimmingCharacters(in: .whitespacesAndNewlines), inputTokens: inputTokens, outputTokens: outputTokens)
	}

	// MARK: - OpenAI API

	private static func openaiRequest(
		systemPrompt: String,
		userContent: String,
		apiKey: String, model: String, timeout: TimeInterval, thinkingBudget: Int
	) async throws -> RawResult {
		return try await openaiRequestInternal(
			systemPrompt: systemPrompt, userContent: userContent,
			apiKey: apiKey, model: model, timeout: timeout, thinkingBudget: thinkingBudget
		)
	}

	private static func openaiRequest(
		systemPrompt: String,
		userContentParts: [[String: Any]],
		apiKey: String, model: String, timeout: TimeInterval, thinkingBudget: Int
	) async throws -> RawResult {
		return try await openaiRequestInternal(
			systemPrompt: systemPrompt, userContent: userContentParts,
			apiKey: apiKey, model: model, timeout: timeout, thinkingBudget: thinkingBudget
		)
	}

	private static func openaiRequestInternal(
		systemPrompt: String, userContent: Any,
		apiKey: String, model: String, timeout: TimeInterval, thinkingBudget: Int
	) async throws -> RawResult {
		let reasoningEffort: String = switch thinkingBudget {
		case 0: "none"
		case 1...1024: "low"
		case 1025...4096: "medium"
		default: "high"
		}
		let body: [String: Any] = [
			"model": model,
			"messages": [
				["role": "developer", "content": systemPrompt],
				["role": "user", "content": userContent]
			],
			"reasoning_effort": reasoningEffort
		]
		let url = URL(string: "https://api.openai.com/v1/chat/completions")!

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = timeout
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)
		try validateHTTPResponse(response, data: data)

		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let choices = json["choices"] as? [[String: Any]],
			  let firstChoice = choices.first,
			  let message = firstChoice["message"] as? [String: Any],
			  let resultText = message["content"] as? String
		else { throw AIError.parsingFailed }

		// Parse usage: usage.prompt_tokens / completion_tokens
		let usage = json["usage"] as? [String: Any]
		let inputTokens = usage?["prompt_tokens"] as? Int
		let outputTokens = usage?["completion_tokens"] as? Int

		return RawResult(text: resultText.trimmingCharacters(in: .whitespacesAndNewlines), inputTokens: inputTokens, outputTokens: outputTokens)
	}

	// MARK: - Shared

	private static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
		guard let httpResponse = response as? HTTPURLResponse else {
			throw AIError.invalidResponse
		}
		guard httpResponse.statusCode == 200 else {
			let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
			aiLogger.error("AI API error \(httpResponse.statusCode): \(errorBody)")
			throw AIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
		}
	}
}

// MARK: - Errors

enum AIError: LocalizedError {
	case invalidResponse
	case apiError(statusCode: Int, message: String)
	case parsingFailed

	var errorDescription: String? {
		switch self {
		case .invalidResponse:
			return "Invalid response from AI API"
		case let .apiError(statusCode, message):
			return "AI API error (\(statusCode)): \(message)"
		case .parsingFailed:
			return "Failed to parse AI API response"
		}
	}
}
