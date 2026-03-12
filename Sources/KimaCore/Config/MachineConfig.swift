import Foundation

public struct MachineConfig: Codable, Sendable, Equatable {
    public var cpus: Int
    public var memoryMB: Int
    public var diskSizeGB: Int

    public static let `default` = MachineConfig(cpus: 2, memoryMB: 2048, diskSizeGB: 64)

    public init(cpus: Int = 2, memoryMB: Int = 2048, diskSizeGB: Int = 64) {
        self.cpus = cpus
        self.memoryMB = memoryMB
        self.diskSizeGB = diskSizeGB
    }

    public func save(to url: URL? = nil) throws {
        let target = url ?? KimaPaths.machineConfigFile
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: target, options: .atomic)
    }

    public static func load(from url: URL? = nil) throws -> MachineConfig {
        let target = url ?? KimaPaths.machineConfigFile
        let data = try Data(contentsOf: target)
        return try JSONDecoder().decode(MachineConfig.self, from: data)
    }
}
