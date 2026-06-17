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
	/// OpenAI-compatible local server (e.g. LM Studio, Ollama). Uses the OpenAI
	/// request shape against a user-supplied base URL.
	case local

	static func from(model: String) -> AIProvider {
		if model.hasPrefix("gpt-") || model.hasPrefix("o3") || model.hasPrefix("o4") {
			return .openai
		}
		return .gemini
	}
}

// MARK: - Client Interface

struct GeminiClient: Sendable {
	/// Token a user can place inside their post-processing prompt to mark where the
	/// transcription should be injected. Exposed for the prompt-editor UI hint.
	static let transcriptionPlaceholder = "{{transcription}}"

	var postProcess: @Sendable (_ text: String, _ prompt: String, _ apiKey: String, _ model: String, _ thinkingBudget: Int, _ imageData: Data?, _ openaiDetail: String, _ baseURL: String?, _ maxTokens: Int?) async throws -> AIResult
	var transcribeAudio: @Sendable (_ audioURL: URL, _ prompt: String, _ apiKey: String, _ model: String, _ thinkingBudget: Int, _ imageData: Data?, _ openaiDetail: String, _ baseURL: String?, _ maxTokens: Int?) async throws -> AIResult

	init(
		postProcess: @escaping @Sendable (String, String, String, String, Int, Data?, String, String?, Int?) async throws -> AIResult = { _, _, _, _, _, _, _, _, _ in AIResult(text: "", duration: 0, inputTokens: nil, outputTokens: nil) },
		transcribeAudio: @escaping @Sendable (URL, String, String, String, Int, Data?, String, String?, Int?) async throws -> AIResult = { _, _, _, _, _, _, _, _, _ in AIResult(text: "", duration: 0, inputTokens: nil, outputTokens: nil) }
	) {
		self.postProcess = postProcess
		self.transcribeAudio = transcribeAudio
	}
}

extension GeminiClient: DependencyKey {
	static var liveValue: Self {
		Self(
			postProcess: { text, prompt, apiKey, model, thinkingBudget, imageData, openaiDetail, baseURL, maxTokens in
				try await AIClientLive.postProcess(text: text, prompt: prompt, apiKey: apiKey, model: model, thinkingBudget: thinkingBudget, imageData: imageData, openaiDetail: openaiDetail, baseURL: baseURL, maxTokens: maxTokens)
			},
			transcribeAudio: { audioURL, prompt, apiKey, model, thinkingBudget, imageData, openaiDetail, baseURL, maxTokens in
				try await AIClientLive.transcribeAudio(audioURL: audioURL, prompt: prompt, apiKey: apiKey, model: model, thinkingBudget: thinkingBudget, imageData: imageData, openaiDetail: openaiDetail, baseURL: baseURL, maxTokens: maxTokens)
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

	static func postProcess(text: String, prompt: String, apiKey: String, model: String, thinkingBudget: Int, imageData: Data?, openaiDetail: String, baseURL: String?, maxTokens: Int?) async throws -> AIResult {
		let start = Date()
		// A non-nil baseURL means a local OpenAI-compatible server; otherwise infer
		// the cloud provider from the model name.
		let provider: AIProvider = baseURL != nil ? .local : AIProvider.from(model: model)
		let raw: RawResult

		// Two prompt modes:
		//  - Placeholder mode: the prompt contains `{{transcription}}`. We substitute
		//    the transcription inline; the combined text is the user message and there
		//    is no system instruction.
		//  - Legacy mode: no placeholder. The prompt passes through verbatim as the
		//    system instruction and the transcription is sent as the user message.
		let hasPlaceholder = prompt.contains(GeminiClient.transcriptionPlaceholder)
		let systemPrompt = hasPlaceholder ? "" : prompt
		let userText = hasPlaceholder
			? prompt.replacingOccurrences(of: GeminiClient.transcriptionPlaceholder, with: text)
			: text

		// When a screenshot is present, a neutral marker is added to the user message
		// so the model knows what the image is, without overriding the user's own
		// instructions.
		let imageNote = "(Screenshot of the user's currently active window, provided as visual context for the text below.)"

		switch provider {
		case .gemini:
			var userParts: [[String: Any]] = []
			if let imageData {
				let base64 = imageData.base64EncodedString()
				userParts.append(["inlineData": ["mimeType": "image/jpeg", "data": base64]])
				userParts.append(["text": imageNote])
			}
			userParts.append(["text": userText])
			raw = try await geminiRequest(
				systemPrompt: systemPrompt,
				userParts: userParts,
				apiKey: apiKey, model: model, timeout: 20, thinkingBudget: thinkingBudget
			)
		case .openai, .local:
			let endpoint = provider == .local ? (baseURL ?? "") : openaiCloudBaseURL
			let timeout: TimeInterval = provider == .local ? 120 : (imageData != nil ? 20 : 15)
			if let imageData {
				let base64 = imageData.base64EncodedString()
				// Keep the screenshot note and the user text as separate parts so the
				// user's prompt (which in placeholder mode is the entire instruction)
				// isn't prefixed/diluted by the note. Mirrors the Gemini branch.
				let userContent: [[String: Any]] = [
					["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)", "detail": openaiDetail]],
					["type": "text", "text": imageNote],
					["type": "text", "text": userText]
				]
				raw = try await openaiRequest(
					systemPrompt: systemPrompt,
					userContentParts: userContent,
					apiKey: apiKey, model: model, timeout: timeout, thinkingBudget: thinkingBudget,
					baseURL: endpoint, maxTokens: maxTokens
				)
			} else {
				raw = try await openaiRequest(
					systemPrompt: systemPrompt,
					userContent: userText,
					apiKey: apiKey, model: model, timeout: timeout, thinkingBudget: thinkingBudget,
					baseURL: endpoint, maxTokens: maxTokens
				)
			}
		}

		return AIResult(text: raw.text, duration: Date().timeIntervalSince(start), inputTokens: raw.inputTokens, outputTokens: raw.outputTokens)
	}

	static func transcribeAudio(audioURL: URL, prompt: String, apiKey: String, model: String, thinkingBudget: Int, imageData: Data?, openaiDetail: String, baseURL: String?, maxTokens: Int?) async throws -> AIResult {
		let start = Date()
		// Direct-audio mode is gated to Google in the UI; local OpenAI-compatible
		// servers don't accept audio input, so reject it explicitly here.
		if baseURL != nil {
			throw AIError.localAudioUnsupported
		}
		let provider = AIProvider.from(model: model)
		let raw: RawResult

		// Same approach as postProcess: user's prompt passes through verbatim, neutral
		// marker added alongside the image in the user message when one is present.
		let imageNote = "(Screenshot of the user's currently active window, provided as visual context for the audio below.)"

		switch provider {
		case .local:
			throw AIError.localAudioUnsupported
		case .gemini:
			let audioData = try Data(contentsOf: audioURL)
			let base64Audio = audioData.base64EncodedString()
			var userParts: [[String: Any]] = []
			if let imageData {
				let base64Image = imageData.base64EncodedString()
				userParts.append(["inlineData": ["mimeType": "image/jpeg", "data": base64Image]])
				userParts.append(["text": imageNote])
			}
			userParts.append(["inlineData": ["mimeType": "audio/wav", "data": base64Audio]])
			raw = try await geminiRequest(
				systemPrompt: prompt,
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
				userContent.append(["type": "text", "text": imageNote])
			}
			userContent.append(["type": "input_audio", "input_audio": ["data": base64Audio, "format": "wav"]])
			raw = try await openaiRequest(
				systemPrompt: prompt,
				userContentParts: userContent,
				apiKey: apiKey, model: model, timeout: 30, thinkingBudget: thinkingBudget,
				baseURL: openaiCloudBaseURL, maxTokens: nil
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
		var body: [String: Any] = [
			"contents": [["parts": userParts]],
			"generationConfig": ["thinkingConfig": ["thinkingBudget": thinkingBudget]]
		]
		// Omit systemInstruction in placeholder mode (the whole prompt lives in the
		// user message); only send it when a separate system instruction exists.
		if !systemPrompt.isEmpty {
			body["systemInstruction"] = ["parts": [["text": systemPrompt]]]
		}
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

	/// Base URL for the OpenAI cloud API (without the `/chat/completions` suffix).
	static let openaiCloudBaseURL = "https://api.openai.com/v1"

	private static func openaiRequest(
		systemPrompt: String,
		userContent: String,
		apiKey: String, model: String, timeout: TimeInterval, thinkingBudget: Int,
		baseURL: String, maxTokens: Int?
	) async throws -> RawResult {
		return try await openaiRequestInternal(
			systemPrompt: systemPrompt, userContent: userContent,
			apiKey: apiKey, model: model, timeout: timeout, thinkingBudget: thinkingBudget,
			baseURL: baseURL, maxTokens: maxTokens
		)
	}

	private static func openaiRequest(
		systemPrompt: String,
		userContentParts: [[String: Any]],
		apiKey: String, model: String, timeout: TimeInterval, thinkingBudget: Int,
		baseURL: String, maxTokens: Int?
	) async throws -> RawResult {
		return try await openaiRequestInternal(
			systemPrompt: systemPrompt, userContent: userContentParts,
			apiKey: apiKey, model: model, timeout: timeout, thinkingBudget: thinkingBudget,
			baseURL: baseURL, maxTokens: maxTokens
		)
	}

	private static func openaiRequestInternal(
		systemPrompt: String, userContent: Any,
		apiKey: String, model: String, timeout: TimeInterval, thinkingBudget: Int,
		baseURL: String, maxTokens: Int?
	) async throws -> RawResult {
		let reasoningEffort: String = switch thinkingBudget {
		case 0: "none"
		case 1...1024: "low"
		case 1025...4096: "medium"
		default: "high"
		}
		// Omit the system/developer message in placeholder mode (the whole prompt is
		// inlined into the user message); only include it when one exists.
		var messages: [[String: Any]] = []
		if !systemPrompt.isEmpty {
			messages.append(["role": "developer", "content": systemPrompt])
		}
		messages.append(["role": "user", "content": userContent])
		var body: [String: Any] = [
			"model": model,
			"messages": messages,
			"reasoning_effort": reasoningEffort
		]
		// Local servers (e.g. LM Studio) need an explicit output cap so reasoning
		// models don't spend the whole budget thinking and return empty content.
		if let maxTokens {
			body["max_tokens"] = maxTokens
		}

		let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
		guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
			throw AIError.invalidBaseURL(baseURL)
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		// LM Studio and similar local servers don't require auth; only send the
		// Authorization header when a key is present.
		if !apiKey.isEmpty {
			request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
		}
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = timeout
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)
		try validateHTTPResponse(response, data: data)

		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let choices = json["choices"] as? [[String: Any]],
			  let firstChoice = choices.first,
			  let message = firstChoice["message"] as? [String: Any]
		else { throw AIError.parsingFailed }

		let resultText = (message["content"] as? String) ?? ""

		// Parse usage: usage.prompt_tokens / completion_tokens
		let usage = json["usage"] as? [String: Any]
		let inputTokens = usage?["prompt_tokens"] as? Int
		let outputTokens = usage?["completion_tokens"] as? Int

		let trimmed = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
		// A reasoning model can hit the token cap before emitting any answer, leaving
		// content empty. Surface a clear, actionable error in that specific case.
		// (Other empty responses fall through to the prior behavior of returning "".)
		if trimmed.isEmpty, (firstChoice["finish_reason"] as? String) == "length" {
			throw AIError.emptyOutputTruncated
		}

		return RawResult(text: trimmed, inputTokens: inputTokens, outputTokens: outputTokens)
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
	case invalidBaseURL(String)
	case localAudioUnsupported
	case emptyOutputTruncated

	var errorDescription: String? {
		switch self {
		case .invalidResponse:
			return "Invalid response from AI API"
		case let .apiError(statusCode, message):
			return "AI API error (\(statusCode)): \(message)"
		case .parsingFailed:
			return "Failed to parse AI API response"
		case let .invalidBaseURL(url):
			return "Invalid local LLM base URL: \(url)"
		case .localAudioUnsupported:
			return "Direct audio mode isn't supported by local LLMs. Disable it or switch to a Google model."
		case .emptyOutputTruncated:
			return "The model hit the output token limit before replying. Increase “Max output tokens” in AI Processing settings."
		}
	}
}
