import Foundation
import Virtualization
import Logging

/// Wrapper around VZVirtualMachine with delegate handling
@MainActor
public final class KimaVirtualMachine: NSObject, Sendable {
    private let vm: VZVirtualMachine
    private let logger: Logger

    public init(configuration: VZVirtualMachineConfiguration) {
        self.vm = VZVirtualMachine(configuration: configuration)
        self.logger = Logger(label: "kima.vm")
        super.init()
        self.vm.delegate = self
    }

    public var state: VZVirtualMachine.State {
        vm.state
    }

    public var canStart: Bool {
        vm.canStart
    }

    public var canStop: Bool {
        vm.canStop
    }

    public var canRequestStop: Bool {
        vm.canRequestStop
    }

    /// The underlying vsock device for guest communication
    public var socketDevice: VZVirtioSocketDevice? {
        vm.socketDevices.first as? VZVirtioSocketDevice
    }

    public func start() async throws {
        try await vm.start()
        logger.info("VM started")
    }

    public func stop() async throws {
        try await vm.stop()
        logger.info("VM stopped")
    }

    public func requestStop() throws {
        try vm.requestStop()
        logger.info("VM stop requested")
    }
}

extension KimaVirtualMachine: VZVirtualMachineDelegate {
    nonisolated public func virtualMachine(
        _ virtualMachine: VZVirtualMachine,
        didStopWithError error: Error
    ) {
        let logger = Logger(label: "kima.vm")
        logger.error("VM stopped with error: \(error.localizedDescription)")
    }

    nonisolated public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        let logger = Logger(label: "kima.vm")
        logger.info("Guest initiated stop")
    }
}
