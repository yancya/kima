import ArgumentParser
import Foundation
import KimaCore
import Logging

/// Hidden subcommand that runs the VM daemon process
struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "_daemon",
        abstract: "Internal: run the VM daemon (do not call directly)",
        shouldDisplay: false
    )

    func run() async throws {
        var logger = Logger(label: "kima.daemon")
        logger.logLevel = .info

        logger.info("Daemon starting...")

        let lifecycle = VMLifecycle()
        guard await lifecycle.canBoot() else {
            logger.error("Cannot boot: kernel or rootfs not found. Run Scripts/build-vm-image.sh first.")
            throw ExitCode.failure
        }

        let config = try MachineConfig.load()

        // Write PID file
        let pidStr = "\(Foundation.ProcessInfo.processInfo.processIdentifier)"
        try pidStr.write(to: KimaPaths.daemonPidFile, atomically: true, encoding: .utf8)

        // Build config and start VM on MainActor
        try await MainActor.run {
            let vmConfig = try VMConfigurationBuilder.build(config: config)
            let vm = KimaVirtualMachine(configuration: vmConfig)
            _daemonVM = vm
        }

        try await _daemonVM?.start()
        logger.info("VM started")

        // Get vsock device on MainActor (sync)
        let agentClient: GuestAgentClient = try await MainActor.run {
            guard let socketDevice = _daemonVM?.socketDevice else {
                logger.error("No vsock device found")
                throw ExitCode.failure
            }
            return GuestAgentClient(socketDevice: socketDevice)
        }

        // Wait for guest agent (async, already @MainActor isolated)
        logger.info("Waiting for guest agent...")
        try await agentClient.waitForAgent(timeout: 120)

        // Start daemon socket server (sync on MainActor)
        try await MainActor.run {
            let server = DaemonServer(agentClient: agentClient)
            try server.start()
            _daemonServer = server
        }

        logger.info("Daemon ready. Send SIGTERM to stop.")

        // Handle SIGTERM for graceful shutdown
        let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM)
        signal(SIGTERM, SIG_IGN)
        sigSource.setEventHandler {
            Task { @MainActor in
                let shutdownLogger = Logger(label: "kima.daemon")
                shutdownLogger.info("Received SIGTERM, shutting down...")
                _daemonServer?.stop()
                try? await _daemonVM?.stop()
                try? FileManager.default.removeItem(at: KimaPaths.daemonPidFile)
                Foundation.exit(0)
            }
        }
        sigSource.resume()

        // Keep the daemon running indefinitely
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            // Never resumes — daemon runs until SIGTERM
        }
    }
}

// Global references to keep VM and server alive during daemon lifetime
@MainActor
private var _daemonVM: KimaVirtualMachine?
@MainActor
private var _daemonServer: DaemonServer?
