import ComposableArchitecture
import Inject
import SwiftUI

struct AboutView: View {
    @ObserveInjection var inject
    @Bindable var store: StoreOf<SettingsFeature>
    @State private var showingChangelog = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                }
                HStack {
                    Label("Changelog", systemImage: "doc.text")
                    Spacer()
                    Button("Show Changelog") {
                        showingChangelog.toggle()
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $showingChangelog, onDismiss: {
                        showingChangelog = false
                    }) {
                        ChangelogView()
                    }
                }
                HStack {
                    Label("Based on Hex by Kit Langton", systemImage: "apple.terminal.on.rectangle")
                    Spacer()
                    Link("Original Repo", destination: URL(string: "https://github.com/kitlangton/Hex/")!)
                }
                HStack {
                    Label("Hex Extended", systemImage: "sparkles")
                    Spacer()
                    Link("Our Fork", destination: URL(string: "https://github.com/asemenovwrk/hex_extended")!)
                }
            }
        }
        .formStyle(.grouped)
        .enableInjection()
    }
}
