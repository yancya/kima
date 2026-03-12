import Foundation
import XCTest
@testable import KimaCore
@testable import KimaKit

final class KimaCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(KimaCore.version, "0.1.0")
    }

    func testMachineConfigDefaults() {
        let config = MachineConfig.default
        XCTAssertEqual(config.cpus, 2)
        XCTAssertEqual(config.memoryMB, 2048)
        XCTAssertEqual(config.diskSizeGB, 64)
    }

    func testMachineConfigSerializeDeserialize() throws {
        let config = MachineConfig(cpus: 4, memoryMB: 4096, diskSizeGB: 128)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("kima-test-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try config.save(to: tempURL)
        let loaded = try MachineConfig.load(from: tempURL)
        XCTAssertEqual(loaded, config)
    }

    func testPathsConstruction() {
        let base = KimaPaths.baseDirectory
        XCTAssert(base.path().contains("kima"))
        XCTAssertEqual(KimaPaths.machineConfigFile.lastPathComponent, "config.json")
        XCTAssertEqual(KimaPaths.diskImageFile.lastPathComponent, "disk.raw")
        XCTAssertEqual(KimaPaths.daemonSocketFile.lastPathComponent, "daemon.sock")
    }

    func testJSONRPCRoundTrip() throws {
        let request = JSONRPCRequest(
            id: 1,
            method: RPCMethod.containerRun,
            params: ["image": .string("nginx"), "ports": .array([.string("8080:80")])]
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        XCTAssertEqual(decoded.method, "container.run")
        XCTAssertEqual(decoded.id, 1)
    }
}
