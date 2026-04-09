import SwiftUI
import Inject
import HexCore
#if canImport(ComposableArchitecture)
	import ComposableArchitecture
#endif

struct TranscriptionPromptsManagementView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@Environment(\.dismiss) var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Transcription Prompts")
				.font(.title2.bold())
			Text("Add terminology hints for Whisper. List words, acronyms, or phrases the model should recognize.")
				.font(.callout)
				.foregroundStyle(.secondary)

			if store.hexSettings.transcriptionPrompts.isEmpty {
				VStack(spacing: 8) {
					Spacer()
					Text("No prompts yet")
						.foregroundStyle(.tertiary)
					Text("Add a prompt to help Whisper recognize technical terms.")
						.font(.caption)
						.foregroundStyle(.tertiary)
					Spacer()
				}
				.frame(maxWidth: .infinity)
			} else {
				ScrollView {
					LazyVStack(spacing: 12) {
						ForEach(store.hexSettings.transcriptionPrompts) { prompt in
							if let binding = promptBinding(for: prompt.id) {
								PromptRow(prompt: binding) {
									store.send(.removeTranscriptionPrompt(prompt.id))
								}
							}
						}
					}
					.padding(.horizontal, 1)
				}
			}

			HStack {
				Button {
					store.send(.addTranscriptionPrompt)
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
		.enableInjection()
	}

	private func promptBinding(for id: UUID) -> Binding<TranscriptionPrompt>? {
		guard store.hexSettings.transcriptionPrompts.contains(where: { $0.id == id }) else {
			return nil
		}
		return Binding(
			get: {
				store.hexSettings.transcriptionPrompts.first(where: { $0.id == id })
					?? TranscriptionPrompt(id: id, name: "", text: "")
			},
			set: { store.send(.updateTranscriptionPrompt($0)) }
		)
	}
}

private struct PromptRow: View {
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
				.help("Delete prompt")
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
