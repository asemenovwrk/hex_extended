import SwiftUI
import Inject
import HexCore
#if canImport(ComposableArchitecture)
	import ComposableArchitecture
#endif

struct TranscriptionPromptSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@State private var isManagingPrompts = false

	var body: some View {
		Label {
			HStack {
				Picker(
					"Transcription Prompt",
					selection: Binding(
						get: { store.hexSettings.selectedTranscriptionPromptID },
						set: { store.send(.setSelectedTranscriptionPromptID($0)) }
					)
				) {
					Text("None").tag(UUID?.none)
					if !store.hexSettings.transcriptionPrompts.isEmpty {
						Divider()
						ForEach(store.hexSettings.transcriptionPrompts) { prompt in
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
		} icon: {
			Image(systemName: "text.quote")
		}
		.sheet(isPresented: $isManagingPrompts) {
			TranscriptionPromptsManagementView(store: store)
		}
		.enableInjection()
	}
}
