import Foundation

public struct TranscriptionPrompt: Codable, Equatable, Identifiable, Sendable {
	public var id: UUID
	public var name: String
	public var text: String

	public init(
		id: UUID = UUID(),
		name: String,
		text: String
	) {
		self.id = id
		self.name = name
		self.text = text
	}
}
