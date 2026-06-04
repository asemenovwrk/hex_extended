import Foundation

public enum RecordingAudioBehavior: String, Codable, CaseIterable, Equatable, Sendable {
	case pauseMedia
	case mute
	case doNothing
}

/// User-configurable settings saved to disk.
public struct HexSettings: Codable, Equatable, Sendable {
	public static let defaultPasteLastTranscriptHotkey = HotKey(key: .v, modifiers: [.option, .shift])
	public static let baseSoundEffectsVolume: Double = HexCoreConstants.baseSoundEffectsVolume
	public static let defaultWordRemovals: [WordRemoval] = [
		.init(pattern: "uh+"),
		.init(pattern: "um+"),
		.init(pattern: "er+"),
		.init(pattern: "hm+")
	]

	public static var defaultPasteLastTranscriptHotkeyDescription: String {
		let modifiers = defaultPasteLastTranscriptHotkey.modifiers.sorted.map { $0.stringValue }.joined()
		let key = defaultPasteLastTranscriptHotkey.key?.toString ?? ""
		return modifiers + key
	}

	public var soundEffectsEnabled: Bool
	public var soundEffectsVolume: Double
	public var hotkey: HotKey
	public var openOnLogin: Bool
	public var showDockIcon: Bool
	public var selectedModel: String
	public var useClipboardPaste: Bool
	public var preventSystemSleep: Bool
	public var recordingAudioBehavior: RecordingAudioBehavior
	public var minimumKeyTime: Double
	public var copyToClipboard: Bool
	public var superFastModeEnabled: Bool
	public var useDoubleTapOnly: Bool
	public var doubleTapLockEnabled: Bool
	public var outputLanguage: String?
	public var selectedMicrophoneID: String?
	public var saveTranscriptionHistory: Bool
	public var maxHistoryEntries: Int?
	public var pasteLastTranscriptHotkey: HotKey?
	public var hasCompletedModelBootstrap: Bool
	public var hasCompletedStorageMigration: Bool
	public var wordRemovalsEnabled: Bool
	public var wordRemovals: [WordRemoval]
	public var wordRemappings: [WordRemapping]
	public var transcriptionPrompts: [TranscriptionPrompt]
	public var selectedTranscriptionPromptID: UUID?
	public var geminiApiKey: String?
	public var openaiApiKey: String?
	public var geminiModel: String
	public var geminiPostProcessingEnabled: Bool
	public var geminiPrompts: [TranscriptionPrompt]
	public var selectedGeminiPromptID: UUID?
	public var geminiDirectAudioMode: Bool
	public var geminiThinkingBudget: Int
	public var geminiIncludeScreenshot: Bool
	public var geminiScreenshotMaxDimension: Int
	public var openaiScreenshotDetail: String
	/// Active AI provider: "google", "openai", or "local". Stored explicitly rather than
	/// inferred from the model name, since local model identifiers are arbitrary.
	public var aiProvider: String
	public var localLLMBaseURL: String
	public var localLLMModel: String
	public var localLLMApiKey: String?
	public var localLLMMaxTokens: Int
	/// Screenshot downscale multiplier for local providers (0.1–1.0 of the window's
	/// native resolution). 1.0 = full resolution. Lower values speed up models with
	/// dynamic image resolution by sending fewer pixels (and thus fewer vision tokens).
	public var localLLMScreenshotScale: Double
	/// When true, a light unsharp mask is applied to the downscaled local screenshot so
	/// text stays legible at lower resolutions (lets the scale go lower for more speed).
	public var localLLMSharpenScreenshot: Bool
	/// Debug: when true, the exact JPEG sent to the AI provider is also written to disk
	/// (app container → Application Support/DebugScreenshots/last-sent.jpg).
	public var debugSaveSentScreenshot: Bool

	public var selectedTranscriptionPrompt: TranscriptionPrompt? {
		guard let id = selectedTranscriptionPromptID else { return nil }
		return transcriptionPrompts.first { $0.id == id }
	}

	public var activeAIApiKey: String? {
		switch aiProvider {
		case "openai":
			return openaiApiKey
		case "local":
			return localLLMApiKey
		default:
			return geminiApiKey
		}
	}

	/// True when AI post-processing has everything it needs to make a request.
	/// Cloud providers require an API key; the local provider requires a base URL
	/// and model name (an API key is optional for local servers like LM Studio).
	public var aiPostProcessingConfigured: Bool {
		if aiProvider == "local" {
			return !localLLMBaseURL.isEmpty && !localLLMModel.isEmpty
		}
		return !(activeAIApiKey ?? "").isEmpty
	}

	/// Direct-audio mode is only meaningful for Google models; OpenAI and local
	/// providers go through text post-processing only.
	public var effectiveDirectAudioMode: Bool {
		aiProvider == "google" && geminiDirectAudioMode
	}

	public var selectedGeminiPrompt: TranscriptionPrompt? {
		guard let id = selectedGeminiPromptID else { return nil }
		return geminiPrompts.first { $0.id == id }
	}

	private mutating func normalizeDoubleTapSettings() {
		if !doubleTapLockEnabled {
			useDoubleTapOnly = false
		}
	}

	public init(
		soundEffectsEnabled: Bool = true,
		soundEffectsVolume: Double = HexSettings.baseSoundEffectsVolume,
		hotkey: HotKey = .init(key: nil, modifiers: [.option]),
		openOnLogin: Bool = false,
		showDockIcon: Bool = true,
		selectedModel: String = ParakeetModel.multilingualV3.identifier,
		useClipboardPaste: Bool = true,
		preventSystemSleep: Bool = true,
		recordingAudioBehavior: RecordingAudioBehavior = .doNothing,
		minimumKeyTime: Double = HexCoreConstants.defaultMinimumKeyTime,
		copyToClipboard: Bool = false,
		superFastModeEnabled: Bool = false,
		useDoubleTapOnly: Bool = false,
		doubleTapLockEnabled: Bool = true,
		outputLanguage: String? = nil,
		selectedMicrophoneID: String? = nil,
		saveTranscriptionHistory: Bool = true,
		maxHistoryEntries: Int? = nil,
		pasteLastTranscriptHotkey: HotKey? = HexSettings.defaultPasteLastTranscriptHotkey,
		hasCompletedModelBootstrap: Bool = false,
		hasCompletedStorageMigration: Bool = false,
		wordRemovalsEnabled: Bool = false,
		wordRemovals: [WordRemoval] = HexSettings.defaultWordRemovals,
		wordRemappings: [WordRemapping] = [],
		transcriptionPrompts: [TranscriptionPrompt] = [],
		selectedTranscriptionPromptID: UUID? = nil,
		geminiApiKey: String? = nil,
		openaiApiKey: String? = nil,
		geminiModel: String = "gemini-2.5-flash",
		geminiPostProcessingEnabled: Bool = false,
		geminiPrompts: [TranscriptionPrompt] = [],
		selectedGeminiPromptID: UUID? = nil,
		geminiDirectAudioMode: Bool = false,
		geminiThinkingBudget: Int = 0,
		geminiIncludeScreenshot: Bool = false,
		geminiScreenshotMaxDimension: Int = 512,
		openaiScreenshotDetail: String = "low",
		aiProvider: String = "google",
		localLLMBaseURL: String = "http://localhost:1234/v1",
		localLLMModel: String = "",
		localLLMApiKey: String? = nil,
		localLLMMaxTokens: Int = 2048,
		localLLMScreenshotScale: Double = 1.0,
		localLLMSharpenScreenshot: Bool = false,
		debugSaveSentScreenshot: Bool = false
	) {
		self.soundEffectsEnabled = soundEffectsEnabled
		self.soundEffectsVolume = soundEffectsVolume
		self.hotkey = hotkey
		self.openOnLogin = openOnLogin
		self.showDockIcon = showDockIcon
		self.selectedModel = selectedModel
		self.useClipboardPaste = useClipboardPaste
		self.preventSystemSleep = preventSystemSleep
		self.recordingAudioBehavior = recordingAudioBehavior
		self.minimumKeyTime = minimumKeyTime
		self.copyToClipboard = copyToClipboard
		self.superFastModeEnabled = superFastModeEnabled
		self.useDoubleTapOnly = useDoubleTapOnly
		self.doubleTapLockEnabled = doubleTapLockEnabled
		self.outputLanguage = outputLanguage
		self.selectedMicrophoneID = selectedMicrophoneID
		self.saveTranscriptionHistory = saveTranscriptionHistory
		self.maxHistoryEntries = maxHistoryEntries
		self.pasteLastTranscriptHotkey = pasteLastTranscriptHotkey
		self.hasCompletedModelBootstrap = hasCompletedModelBootstrap
		self.hasCompletedStorageMigration = hasCompletedStorageMigration
		self.wordRemovalsEnabled = wordRemovalsEnabled
		self.wordRemovals = wordRemovals
		self.wordRemappings = wordRemappings
		self.transcriptionPrompts = transcriptionPrompts
		self.selectedTranscriptionPromptID = selectedTranscriptionPromptID
		self.geminiApiKey = geminiApiKey
		self.openaiApiKey = openaiApiKey
		self.geminiModel = geminiModel
		self.geminiPostProcessingEnabled = geminiPostProcessingEnabled
		self.geminiPrompts = geminiPrompts
		self.selectedGeminiPromptID = selectedGeminiPromptID
		self.geminiDirectAudioMode = geminiDirectAudioMode
		self.geminiThinkingBudget = geminiThinkingBudget
		self.geminiIncludeScreenshot = geminiIncludeScreenshot
		self.geminiScreenshotMaxDimension = geminiScreenshotMaxDimension
		self.openaiScreenshotDetail = openaiScreenshotDetail
		self.aiProvider = aiProvider
		self.localLLMBaseURL = localLLMBaseURL
		self.localLLMModel = localLLMModel
		self.localLLMApiKey = localLLMApiKey
		self.localLLMMaxTokens = localLLMMaxTokens
		self.localLLMScreenshotScale = localLLMScreenshotScale
		self.localLLMSharpenScreenshot = localLLMSharpenScreenshot
		self.debugSaveSentScreenshot = debugSaveSentScreenshot
		normalizeDoubleTapSettings()
	}

	public init(from decoder: Decoder) throws {
		self.init()
		let container = try decoder.container(keyedBy: HexSettingKey.self)
		for field in HexSettingsSchema.fields {
			try field.decode(into: &self, from: container)
		}
		// Migration: settings saved before the explicit `aiProvider` field derived the
		// provider from the model name. Preserve that behavior for OpenAI users so their
		// API key still resolves correctly until they re-pick a model.
		if !container.contains(.aiProvider) {
			let model = geminiModel
			aiProvider = (model.hasPrefix("gpt-") || model.hasPrefix("o3") || model.hasPrefix("o4")) ? "openai" : "google"
		}
		normalizeDoubleTapSettings()
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: HexSettingKey.self)
		for field in HexSettingsSchema.fields {
			try field.encode(self, into: &container)
		}
	}
}

// MARK: - Schema

private enum HexSettingKey: String, CodingKey, CaseIterable {
	case soundEffectsEnabled
	case soundEffectsVolume
	case hotkey
	case openOnLogin
	case showDockIcon
	case selectedModel
	case useClipboardPaste
	case preventSystemSleep
	case recordingAudioBehavior
	case pauseMediaOnRecord // Legacy
	case minimumKeyTime
	case copyToClipboard
	case superFastModeEnabled
	case useDoubleTapOnly
	case doubleTapLockEnabled
	case outputLanguage
	case selectedMicrophoneID
	case saveTranscriptionHistory
	case maxHistoryEntries
	case pasteLastTranscriptHotkey
	case hasCompletedModelBootstrap
	case hasCompletedStorageMigration
	case wordRemovalsEnabled
	case wordRemovals
	case wordRemappings
	case transcriptionPrompts
	case selectedTranscriptionPromptID
	case geminiApiKey
	case openaiApiKey
	case geminiModel
	case geminiPostProcessingEnabled
	case geminiPrompts
	case selectedGeminiPromptID
	case geminiDirectAudioMode
	case geminiThinkingBudget
	case geminiIncludeScreenshot
	case geminiScreenshotMaxDimension
	case openaiScreenshotDetail
	case aiProvider
	case localLLMBaseURL
	case localLLMModel
	case localLLMApiKey
	case localLLMMaxTokens
	case localLLMScreenshotScale
	case localLLMSharpenScreenshot
	case debugSaveSentScreenshot
}

private struct SettingsField<Value: Codable & Sendable> {
	let key: HexSettingKey
	let keyPath: WritableKeyPath<HexSettings, Value>
	let defaultValue: Value
	let decodeStrategy: (KeyedDecodingContainer<HexSettingKey>, HexSettingKey, Value) throws -> Value
	let encodeStrategy: (inout KeyedEncodingContainer<HexSettingKey>, HexSettingKey, Value) throws -> Void

	init(
		_ key: HexSettingKey,
		keyPath: WritableKeyPath<HexSettings, Value>,
		default defaultValue: Value,
		decode: ((KeyedDecodingContainer<HexSettingKey>, HexSettingKey, Value) throws -> Value)? = nil,
		encode: ((inout KeyedEncodingContainer<HexSettingKey>, HexSettingKey, Value) throws -> Void)? = nil
	) {
		self.key = key
		self.keyPath = keyPath
		self.defaultValue = defaultValue
		self.decodeStrategy = decode ?? { container, key, defaultValue in
			try container.decodeIfPresent(Value.self, forKey: key) ?? defaultValue
		}
		self.encodeStrategy = encode ?? { container, key, value in
			try container.encode(value, forKey: key)
		}
	}

	func eraseToAny() -> AnySettingsField {
		AnySettingsField(
			key: key,
			decode: { container, settings in
				let value = try decodeStrategy(container, key, defaultValue)
				settings[keyPath: keyPath] = value
			},
			encode: { settings, container in
				let value = settings[keyPath: keyPath]
				try encodeStrategy(&container, key, value)
			}
		)
	}
}

private struct AnySettingsField {
	let key: HexSettingKey
	let decode: (KeyedDecodingContainer<HexSettingKey>, inout HexSettings) throws -> Void
	let encode: (HexSettings, inout KeyedEncodingContainer<HexSettingKey>) throws -> Void

	func decode(into settings: inout HexSettings, from container: KeyedDecodingContainer<HexSettingKey>) throws {
		try decode(container, &settings)
	}

	func encode(_ settings: HexSettings, into container: inout KeyedEncodingContainer<HexSettingKey>) throws {
		try encode(settings, &container)
	}
}

private enum HexSettingsSchema {
	static let defaults = HexSettings()

	nonisolated(unsafe) static let fields: [AnySettingsField] = [
		SettingsField(.soundEffectsEnabled, keyPath: \.soundEffectsEnabled, default: defaults.soundEffectsEnabled).eraseToAny(),
		SettingsField(.soundEffectsVolume, keyPath: \.soundEffectsVolume, default: defaults.soundEffectsVolume).eraseToAny(),
		SettingsField(.hotkey, keyPath: \.hotkey, default: defaults.hotkey).eraseToAny(),
		SettingsField(.openOnLogin, keyPath: \.openOnLogin, default: defaults.openOnLogin).eraseToAny(),
		SettingsField(.showDockIcon, keyPath: \.showDockIcon, default: defaults.showDockIcon).eraseToAny(),
		SettingsField(.selectedModel, keyPath: \.selectedModel, default: defaults.selectedModel).eraseToAny(),
		SettingsField(.useClipboardPaste, keyPath: \.useClipboardPaste, default: defaults.useClipboardPaste).eraseToAny(),
		SettingsField(.preventSystemSleep, keyPath: \.preventSystemSleep, default: defaults.preventSystemSleep).eraseToAny(),
		SettingsField(
			.recordingAudioBehavior,
			keyPath: \.recordingAudioBehavior,
			default: defaults.recordingAudioBehavior,
			decode: { container, key, defaultValue in
				if let value = try container.decodeIfPresent(RecordingAudioBehavior.self, forKey: key) {
					return value
				}
				if let legacyPause = try container.decodeIfPresent(Bool.self, forKey: .pauseMediaOnRecord) {
					return legacyPause ? .pauseMedia : .doNothing
				}
				return defaultValue
			}
		).eraseToAny(),
		SettingsField(.minimumKeyTime, keyPath: \.minimumKeyTime, default: defaults.minimumKeyTime).eraseToAny(),
		SettingsField(.copyToClipboard, keyPath: \.copyToClipboard, default: defaults.copyToClipboard).eraseToAny(),
		SettingsField(.superFastModeEnabled, keyPath: \.superFastModeEnabled, default: defaults.superFastModeEnabled).eraseToAny(),
		SettingsField(.useDoubleTapOnly, keyPath: \.useDoubleTapOnly, default: defaults.useDoubleTapOnly).eraseToAny(),
		SettingsField(.doubleTapLockEnabled, keyPath: \.doubleTapLockEnabled, default: defaults.doubleTapLockEnabled).eraseToAny(),
		SettingsField(
			.outputLanguage,
			keyPath: \.outputLanguage,
			default: defaults.outputLanguage,
			encode: { container, key, value in
				try container.encodeIfPresent(value, forKey: key)
			}
		).eraseToAny(),
		SettingsField(
			.selectedMicrophoneID,
			keyPath: \.selectedMicrophoneID,
			default: defaults.selectedMicrophoneID,
			encode: { container, key, value in
				try container.encodeIfPresent(value, forKey: key)
			}
		).eraseToAny(),
		SettingsField(.saveTranscriptionHistory, keyPath: \.saveTranscriptionHistory, default: defaults.saveTranscriptionHistory).eraseToAny(),
		SettingsField(
			.maxHistoryEntries,
			keyPath: \.maxHistoryEntries,
			default: defaults.maxHistoryEntries,
			encode: { container, key, value in
				try container.encodeIfPresent(value, forKey: key)
			}
		).eraseToAny(),
		SettingsField(
			.pasteLastTranscriptHotkey,
			keyPath: \.pasteLastTranscriptHotkey,
			default: defaults.pasteLastTranscriptHotkey,
			encode: { container, key, value in
				try container.encodeIfPresent(value, forKey: key)
			}
		).eraseToAny(),
		SettingsField(.hasCompletedModelBootstrap, keyPath: \.hasCompletedModelBootstrap, default: defaults.hasCompletedModelBootstrap).eraseToAny(),
		SettingsField(.hasCompletedStorageMigration, keyPath: \.hasCompletedStorageMigration, default: defaults.hasCompletedStorageMigration).eraseToAny(),
		SettingsField(.wordRemovalsEnabled, keyPath: \.wordRemovalsEnabled, default: defaults.wordRemovalsEnabled).eraseToAny(),
		SettingsField(
			.wordRemovals,
			keyPath: \.wordRemovals,
			default: defaults.wordRemovals
		).eraseToAny(),
		SettingsField(
			.wordRemappings,
			keyPath: \.wordRemappings,
			default: defaults.wordRemappings
		).eraseToAny(),
		SettingsField(
			.transcriptionPrompts,
			keyPath: \.transcriptionPrompts,
			default: defaults.transcriptionPrompts
		).eraseToAny(),
		SettingsField(
			.selectedTranscriptionPromptID,
			keyPath: \.selectedTranscriptionPromptID,
			default: defaults.selectedTranscriptionPromptID,
			encode: { container, key, value in
				try container.encodeIfPresent(value, forKey: key)
			}
		).eraseToAny(),
		SettingsField(
			.geminiApiKey,
			keyPath: \.geminiApiKey,
			default: defaults.geminiApiKey,
			encode: { container, key, value in
				try container.encodeIfPresent(value, forKey: key)
			}
		).eraseToAny(),
		SettingsField(
			.openaiApiKey,
			keyPath: \.openaiApiKey,
			default: defaults.openaiApiKey,
			encode: { container, key, value in
				try container.encodeIfPresent(value, forKey: key)
			}
		).eraseToAny(),
		SettingsField(.geminiModel, keyPath: \.geminiModel, default: defaults.geminiModel).eraseToAny(),
		SettingsField(.geminiPostProcessingEnabled, keyPath: \.geminiPostProcessingEnabled, default: defaults.geminiPostProcessingEnabled).eraseToAny(),
		SettingsField(.geminiPrompts, keyPath: \.geminiPrompts, default: defaults.geminiPrompts).eraseToAny(),
		SettingsField(
			.selectedGeminiPromptID,
			keyPath: \.selectedGeminiPromptID,
			default: defaults.selectedGeminiPromptID,
			encode: { container, key, value in
				try container.encodeIfPresent(value, forKey: key)
			}
		).eraseToAny(),
		SettingsField(.geminiDirectAudioMode, keyPath: \.geminiDirectAudioMode, default: defaults.geminiDirectAudioMode).eraseToAny(),
		SettingsField(.geminiThinkingBudget, keyPath: \.geminiThinkingBudget, default: defaults.geminiThinkingBudget).eraseToAny(),
		SettingsField(.geminiIncludeScreenshot, keyPath: \.geminiIncludeScreenshot, default: defaults.geminiIncludeScreenshot).eraseToAny(),
		SettingsField(
			.geminiScreenshotMaxDimension,
			keyPath: \.geminiScreenshotMaxDimension,
			default: defaults.geminiScreenshotMaxDimension,
			decode: { container, key, defaultValue in
				// Migrate old presets (768/1024/1568 — all gave ~1548 tok for 16:9)
				// to new meaningful presets (384/512/1024).
				let allowed: Set<Int> = [384, 512, 1024]
				let raw = try container.decodeIfPresent(Int.self, forKey: key) ?? defaultValue
				return allowed.contains(raw) ? raw : defaultValue
			}
		).eraseToAny(),
		SettingsField(.openaiScreenshotDetail, keyPath: \.openaiScreenshotDetail, default: defaults.openaiScreenshotDetail).eraseToAny(),
		SettingsField(.aiProvider, keyPath: \.aiProvider, default: defaults.aiProvider).eraseToAny(),
		SettingsField(.localLLMBaseURL, keyPath: \.localLLMBaseURL, default: defaults.localLLMBaseURL).eraseToAny(),
		SettingsField(.localLLMModel, keyPath: \.localLLMModel, default: defaults.localLLMModel).eraseToAny(),
		SettingsField(
			.localLLMApiKey,
			keyPath: \.localLLMApiKey,
			default: defaults.localLLMApiKey,
			encode: { container, key, value in
				try container.encodeIfPresent(value, forKey: key)
			}
		).eraseToAny(),
		SettingsField(.localLLMMaxTokens, keyPath: \.localLLMMaxTokens, default: defaults.localLLMMaxTokens).eraseToAny(),
		SettingsField(.localLLMScreenshotScale, keyPath: \.localLLMScreenshotScale, default: defaults.localLLMScreenshotScale).eraseToAny(),
		SettingsField(.localLLMSharpenScreenshot, keyPath: \.localLLMSharpenScreenshot, default: defaults.localLLMSharpenScreenshot).eraseToAny(),
		SettingsField(.debugSaveSentScreenshot, keyPath: \.debugSaveSentScreenshot, default: defaults.debugSaveSentScreenshot).eraseToAny()
	]
}
