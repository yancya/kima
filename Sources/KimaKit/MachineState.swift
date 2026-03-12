import Foundation

public enum MachineState: String, Codable, Sendable {
    case notCreated = "not_created"
    case stopped
    case starting
    case running
    case stopping
    case error
}

public struct ContainerInfo: Codable, Sendable, Equatable {
    public var id: String
    public var image: String
    public var command: String
    public var state: String
    public var ports: [String]
    public var names: String

    public init(id: String, image: String, command: String, state: String, ports: [String], names: String) {
        self.id = id
        self.image = image
        self.command = command
        self.state = state
        self.ports = ports
        self.names = names
    }
}

public struct ImageInfo: Codable, Sendable, Equatable {
    public var id: String
    public var repository: String
    public var tag: String
    public var size: String

    public init(id: String, repository: String, tag: String, size: String) {
        self.id = id
        self.repository = repository
        self.tag = tag
        self.size = size
    }
}
