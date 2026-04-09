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

	private var selectedProvider: String {
		aiModels.first(where: { $0.id == store.hexSettings.geminiModel })?.provider ?? "google"
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
						get: { store.hexSettings.geminiModel },
						set: { store.send(.setGeminiModel($0)) }
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
				}
				.pickerStyle(.menu)

				SecureField(
					selectedProvider == "openai" ? "OpenAI API Key" : "Google API Key",
					text: Binding(
						get: { store.hexSettings.geminiApiKey ?? "" },
						set: { store.send(.setGeminiApiKey($0.isEmpty ? nil : $0)) }
					)
				)
				.textFieldStyle(.roundedBorder)

				Toggle(
					"Send audio directly to Gemini (skip Whisper)",
					isOn: Binding(
						get: { store.hexSettings.geminiDirectAudioMode },
						set: { store.send(.setGeminiDirectAudioMode($0)) }
					)
				)

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
		} header: {
			Label("AI Processing (Gemini)", systemImage: "sparkles")
		}
		.sheet(isPresented: $isManagingPrompts) {
			GeminiPromptsManagementView(store: store)
		}
		.enableInjection()
	}
}

// MARK: - Prompt Management Sheet

private struct GeminiPromptsManagementView: View {
	@Bindable var store: StoreOf<SettingsFeature>
	@Environment(\.dismiss) var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Gemini Prompts")
				.font(.title2.bold())
			Text("Define instructions for Gemini. E.g.: \"Fix technical terms and punctuation\" or \"Transliterate Russian to Latin\".")
				.font(.callout)
				.foregroundStyle(.secondary)

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
				.frame(minHeight: 60, idealHeight: 80)
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
