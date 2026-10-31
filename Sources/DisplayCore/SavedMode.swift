import Foundation

/// A user-named mode tied to a stable display UUID rather than a transient display ID.
public struct SavedMode: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let displayUUID: String
    public let displayName: String
    public let name: String
    public let mode: DisplayModeSpec

    public init(
        id: UUID = UUID(),
        displayUUID: String,
        displayName: String,
        name: String,
        mode: DisplayModeSpec
    ) {
        self.id = id
        self.displayUUID = displayUUID
        self.displayName = displayName
        self.name = name
        self.mode = mode
    }
}
