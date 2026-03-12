import Foundation

public enum KimaPaths: Sendable {
    /// ~/Library/Application Support/kima/
    public static var baseDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("kima", isDirectory: true)
    }

    /// ~/Library/Application Support/kima/machines/default/
    public static var defaultMachineDirectory: URL {
        baseDirectory.appendingPathComponent("machines/default", isDirectory: true)
    }

    /// ~/Library/Application Support/kima/machines/default/config.json
    public static var machineConfigFile: URL {
        defaultMachineDirectory.appendingPathComponent("config.json")
    }

    /// ~/Library/Application Support/kima/machines/default/disk.raw
    public static var diskImageFile: URL {
        defaultMachineDirectory.appendingPathComponent("disk.raw")
    }

    /// ~/Library/Application Support/kima/machines/default/vmlinuz
    public static var kernelFile: URL {
        defaultMachineDirectory.appendingPathComponent("vmlinuz")
    }

    /// ~/Library/Application Support/kima/machines/default/initrd
    public static var initrdFile: URL {
        defaultMachineDirectory.appendingPathComponent("initrd")
    }

    /// ~/Library/Application Support/kima/machines/default/rootfs.img
    public static var rootfsFile: URL {
        defaultMachineDirectory.appendingPathComponent("rootfs.img")
    }

    /// ~/Library/Application Support/kima/machines/default/console.log
    public static var consoleLogFile: URL {
        defaultMachineDirectory.appendingPathComponent("console.log")
    }

    /// ~/Library/Application Support/kima/machines/default/daemon.sock
    public static var daemonSocketFile: URL {
        defaultMachineDirectory.appendingPathComponent("daemon.sock")
    }

    /// ~/Library/Application Support/kima/machines/default/daemon.pid
    public static var daemonPidFile: URL {
        defaultMachineDirectory.appendingPathComponent("daemon.pid")
    }

    /// Ensure the machine directory exists
    public static func ensureMachineDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: defaultMachineDirectory,
            withIntermediateDirectories: true
        )
    }
}
