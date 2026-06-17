import AppKit
import SwiftUI
import Inject
import HexCore
#if canImport(ComposableArchitecture)
	import ComposableArchitecture
#endif

struct GeminiSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@State private var isManagingPrompts = false

	private let aiModels: [(id: String, name: String, provider: String)] = [
		("gemini-2.5-flash", "Gemini 2.5 Flash", "google"),
		("gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite", "google"),
		("gemini-2.5-pro", "Gemini 2.5 Pro", "google"),
		("gemini-3-flash-preview", "Gemini 3 Flash (Preview)", "google"),
		("gemini-3.1-flash-lite-preview", "Gemini 3.1 Flash Lite (Preview)", "google"),
		("gemma-4-26b-a4b-it", "Gemma 4 26B (Open)", "google"),
		("gemma-4-31b-it", "Gemma 4 31B (Open)", "google"),
		("gpt-5.4-nano", "GPT-5.4 Nano", "openai"),
		("gpt-5.4-mini", "GPT-5.4 Mini", "openai"),
	]

	private static let localSelectionTag = "__local__"

	private var selectedProvider: String {
		store.hexSettings.aiProvider
	}

	var body: some View {
		Section {
			Toggle(
				"Enable AI Processing",
				isOn: Binding(
					get: { store.hexSettings.geminiPostProcessingEnabled },
					set: { store.send(.setGeminiPostProcessingEnabled($0)) }
				)
			)

			if store.hexSettings.geminiPostProcessingEnabled {
				Picker(
					"Model",
					selection: Binding(
						get: {
							store.hexSettings.aiProvider == "local"
								? Self.localSelectionTag
								: store.hexSettings.geminiModel
						},
						set: { value in
							if value == Self.localSelectionTag {
								store.send(.setAIProvider("local"))
							} else {
								store.send(.setGeminiModel(value))
							}
						}
					)
				) {
					Text("Google").disabled(true)
					ForEach(aiModels.filter { $0.provider == "google" }, id: \.id) { model in
						Text("  " + model.name).tag(model.id)
					}
					Divider()
					Text("OpenAI").disabled(true)
					ForEach(aiModels.filter { $0.provider == "openai" }, id: \.id) { model in
						Text("  " + model.name).tag(model.id)
					}
					Divider()
					Text("Local").disabled(true)
					Text("  Local LLM (LM Studio / Ollama)").tag(Self.localSelectionTag)
				}
				.pickerStyle(.menu)

				if selectedProvider == "local" {
					localLLMFields
				} else {
					cloudProviderFields
				}

				// Prompt picker
				HStack {
					Picker(
						"Prompt",
						selection: Binding(
							get: { store.hexSettings.selectedGeminiPromptID },
							set: { store.send(.setSelectedGeminiPromptID($0)) }
						)
					) {
						Text("None").tag(UUID?.none)
						if !store.hexSettings.geminiPrompts.isEmpty {
							Divider()
							ForEach(store.hexSettings.geminiPrompts) { prompt in
								Text(prompt.name.isEmpty ? "Untitled" : prompt.name)
									.tag(prompt.id as UUID?)
							}
						}
					}
					.pickerStyle(.menu)

					Button {
						isManagingPrompts = true
					} label: {
						Image(systemName: "pencil.line")
					}
					.buttonStyle(.borderless)
					.help("Manage prompts")
				}

				if selectedProvider != "local" {
					Picker(
						"Thinking Budget",
						selection: Binding(
							get: { store.hexSettings.geminiThinkingBudget },
							set: { store.send(.setGeminiThinkingBudget($0)) }
						)
					) {
						Text("Off (fastest)").tag(0)
						Text("Low (1024)").tag(1024)
						Text("Medium (4096)").tag(4096)
						Text("High (8192)").tag(8192)
					}
					.pickerStyle(.menu)
				}
			}
		} header: {
			Label("AI Processing", systemImage: "sparkles")
		}
		.sheet(isPresented: $isManagingPrompts) {
			GeminiPromptsManagementView(store: store)
		}
		.enableInjection()
	}

	// MARK: - Cloud provider fields (Google / OpenAI)

	@ViewBuilder
	private var cloudProviderFields: some View {
		SecureField(
			"Google API Key",
			text: Binding(
				get: { store.hexSettings.geminiApiKey ?? "" },
				set: { store.send(.setGeminiApiKey($0.isEmpty ? nil : $0)) }
			)
		)
		.textFieldStyle(.roundedBorder)

		SecureField(
			"OpenAI API Key",
			text: Binding(
				get: { store.hexSettings.openaiApiKey ?? "" },
				set: { store.send(.setOpenAIApiKey($0.isEmpty ? nil : $0)) }
			)
		)
		.textFieldStyle(.roundedBorder)

		// Direct audio only supported by Google models (not OpenAI)
		if selectedProvider == "google" {
			Toggle(
				"Send audio directly (skip Whisper)",
				isOn: Binding(
					get: { store.hexSettings.geminiDirectAudioMode },
					set: { store.send(.setGeminiDirectAudioMode($0)) }
				)
			)
		}

		screenshotFields
	}

	// MARK: - Screenshot context (shared by all providers)

	@ViewBuilder
	private var screenshotFields: some View {
		VStack(alignment: .leading, spacing: 4) {
			Toggle(
				"Include screenshot of active window",
				isOn: Binding(
					get: { store.hexSettings.geminiIncludeScreenshot },
					set: { store.send(.setGeminiIncludeScreenshot($0)) }
				)
			)
			Text(selectedProvider == "local"
				? "Sends a JPEG of the frontmost window alongside the transcription. Requires a vision-capable local model."
				: "Sends a JPEG of the frontmost window alongside the transcription so the model has visual context for what you were looking at.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}

		// Screenshot quality (provider-specific). Google has its own presets; OpenAI
		// and local OpenAI-compatible servers share the detail-based control.
		if store.hexSettings.geminiIncludeScreenshot {
			if selectedProvider == "google" {
				Picker(
					"Screenshot Quality",
					selection: Binding(
						get: { store.hexSettings.geminiScreenshotMaxDimension },
						set: { store.send(.setGeminiScreenshotMaxDimension($0)) }
					)
				) {
					Text("Low — 384px (~258 tok, layout only)").tag(384)
					Text("Medium — 512px (~1032 tok)").tag(512)
					Text("High — 1024px (~1548 tok, text readable)").tag(1024)
				}
				.pickerStyle(.menu)
			} else if selectedProvider == "local" {
				VStack(alignment: .leading, spacing: 4) {
					HStack {
						Text("Screenshot Scale")
						Spacer()
						Text("\(Int((store.hexSettings.localLLMScreenshotScale * 100).rounded()))%")
							.foregroundStyle(.secondary)
							.monospacedDigit()
					}
					Slider(
						value: Binding(
							get: { store.hexSettings.localLLMScreenshotScale },
							set: { store.send(.setLocalLLMScreenshotScale($0)) }
						),
						in: 0.1 ... 1.0,
						step: 0.05
					)
					Text("Fraction of the window's native resolution sent to the model. Lower = faster on models with dynamic image resolution (no effect on models that re-scale to a fixed size internally).")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
				Toggle(
					"Sharpen text for legibility",
					isOn: Binding(
						get: { store.hexSettings.localLLMSharpenScreenshot },
						set: { store.send(.setLocalLLMSharpenScreenshot($0)) }
					)
				)
				.help("Applies a light unsharp mask after downscaling so text stays readable at lower scale (lets you push the slider lower for more speed).")
			} else {
				Picker(
					"Screenshot Detail",
					selection: Binding(
						get: { store.hexSettings.openaiScreenshotDetail },
						set: { store.send(.setOpenAIScreenshotDetail($0)) }
					)
				) {
					Text("Low — 85 tok (flat)").tag("low")
					Text("High — ~765 tok (4:3) / ~1105 tok (16:9)").tag("high")
				}
				.pickerStyle(.menu)
			}

			// Debug: save the exact image sent to the model.
			Toggle(
				"Save sent screenshot to disk (debug)",
				isOn: Binding(
					get: { store.hexSettings.debugSaveSentScreenshot },
					set: { store.send(.setDebugSaveSentScreenshot($0)) }
				)
			)
			if store.hexSettings.debugSaveSentScreenshot {
				Button("Show in Finder") {
					if let url = ScreenshotClient.debugScreenshotURL {
						NSWorkspace.shared.activateFileViewerSelecting([url])
					}
				}
				.buttonStyle(.link)
				.font(.caption)
			}
		}
	}

	// MARK: - Local LLM fields (OpenAI-compatible servers)

	@ViewBuilder
	private var localLLMFields: some View {
		VStack(alignment: .leading, spacing: 4) {
			TextField(
				"Base URL",
				text: Binding(
					get: { store.hexSettings.localLLMBaseURL },
					set: { store.send(.setLocalLLMBaseURL($0)) }
				)
			)
			.textFieldStyle(.roundedBorder)
			Text("OpenAI-compatible endpoint, e.g. http://localhost:1234/v1 for LM Studio.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}

		VStack(alignment: .leading, spacing: 4) {
			TextField(
				"Model",
				text: Binding(
					get: { store.hexSettings.localLLMModel },
					set: { store.send(.setLocalLLMModel($0)) }
				)
			)
			.textFieldStyle(.roundedBorder)
			Text("Exact model id from your server (e.g. qwen/qwen3.6-35b-a3b).")
				.font(.caption)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}

		Picker(
			"Max output tokens",
			selection: Binding(
				get: { store.hexSettings.localLLMMaxTokens },
				set: { store.send(.setLocalLLMMaxTokens($0)) }
			)
		) {
			Text("1024").tag(1024)
			Text("2048").tag(2048)
			Text("4096").tag(4096)
			Text("8192").tag(8192)
		}
		.pickerStyle(.menu)

		SecureField(
			"API Key (optional)",
			text: Binding(
				get: { store.hexSettings.localLLMApiKey ?? "" },
				set: { store.send(.setLocalLLMApiKey($0.isEmpty ? nil : $0)) }
			)
		)
		.textFieldStyle(.roundedBorder)

		screenshotFields
	}
}

// MARK: - Prompt Management Sheet

private struct GeminiPromptsManagementView: View {
	@Bindable var store: StoreOf<SettingsFeature>
	@Environment(\.dismiss) var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("AI Processing Prompts")
				.font(.title2.bold())
			Text("Define instructions for the AI model. E.g.: \"Fix technical terms and punctuation\" or \"Transliterate Russian to Latin\".")
				.font(.callout)
				.foregroundStyle(.secondary)

			// Placeholder hint: explains the optional inline-injection token.
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 4) {
					Image(systemName: "text.insert")
						.foregroundStyle(.secondary)
					Text("Insert ")
						.foregroundStyle(.secondary)
					+ Text(GeminiClient.transcriptionPlaceholder)
						.font(.callout.monospaced().bold())
					+ Text(" where the transcription should go.")
						.foregroundStyle(.secondary)
				}
				.font(.callout)
				Text("If omitted, the prompt is used as a system instruction and the transcription is sent separately (legacy behavior).")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
			.padding(8)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(
				RoundedRectangle(cornerRadius: 6)
					.fill(Color(NSColor.controlBackgroundColor))
			)

			if store.hexSettings.geminiPrompts.isEmpty {
				VStack(spacing: 8) {
					Spacer()
					Text("No prompts yet")
						.foregroundStyle(.tertiary)
					Spacer()
				}
				.frame(maxWidth: .infinity)
			} else {
				ScrollView {
					LazyVStack(spacing: 12) {
						ForEach(store.hexSettings.geminiPrompts) { prompt in
							if let binding = promptBinding(for: prompt.id) {
								GeminiPromptRow(prompt: binding) {
									store.send(.removeGeminiPrompt(prompt.id))
								}
							}
						}
					}
					.padding(.horizontal, 1)
				}
			}

			HStack {
				Button {
					store.send(.addGeminiPrompt)
				} label: {
					Label("Add Prompt", systemImage: "plus")
				}
				Spacer()
				Button("Done") { dismiss() }
					.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(minWidth: 500, idealWidth: 550, minHeight: 350, idealHeight: 450)
	}

	private func promptBinding(for id: UUID) -> Binding<TranscriptionPrompt>? {
		guard store.hexSettings.geminiPrompts.contains(where: { $0.id == id }) else {
			return nil
		}
		return Binding(
			get: {
				store.hexSettings.geminiPrompts.first(where: { $0.id == id })
					?? TranscriptionPrompt(id: id, name: "", text: "")
			},
			set: { store.send(.updateGeminiPrompt($0)) }
		)
	}
}

private struct GeminiPromptRow: View {
	@Binding var prompt: TranscriptionPrompt
	var onDelete: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				TextField("Name", text: $prompt.name)
					.textFieldStyle(.roundedBorder)
					.font(.headline)
					.frame(maxWidth: 200)
				Spacer()
				Button(role: .destructive, action: onDelete) {
					Image(systemName: "trash")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.borderless)
			}
			TextEditor(text: $prompt.text)
				.font(.body.monospaced())
				.frame(minHeight: 120, idealHeight: 160)
				.scrollContentBackground(.hidden)
				.padding(6)
				.background(
					RoundedRectangle(cornerRadius: 6)
						.fill(Color(NSColor.controlBackgroundColor))
				)
				.overlay(
					RoundedRectangle(cornerRadius: 6)
						.stroke(Color.gray.opacity(0.2))
				)
		}
		.padding(10)
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(Color(NSColor.controlBackgroundColor))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 8)
				.stroke(Color.gray.opacity(0.15))
		)
	}
}
