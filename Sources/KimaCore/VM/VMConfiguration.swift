import Foundation
import Virtualization

public enum VMConfigurationBuilder: Sendable {
    /// Build a VZVirtualMachineConfiguration from a MachineConfig
    @MainActor
    public static func build(config: MachineConfig) throws -> VZVirtualMachineConfiguration {
        let vmConfig = VZVirtualMachineConfiguration()

        // CPU & Memory
        vmConfig.cpuCount = config.cpus
        vmConfig.memorySize = UInt64(config.memoryMB) * 1024 * 1024

        // Boot loader
        let kernelURL = KimaPaths.kernelFile
        let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
        bootLoader.commandLine = "console=hvc0 root=/dev/vda rootfstype=ext4 rw modules=virtio_blk"

        if FileManager.default.fileExists(atPath: KimaPaths.initrdFile.path(percentEncoded: false)) {
            bootLoader.initialRamdiskURL = KimaPaths.initrdFile
        }
        vmConfig.bootLoader = bootLoader

        // Storage: rootfs
        let rootfsURL = KimaPaths.rootfsFile
        let rootfsAttachment = try VZDiskImageStorageDeviceAttachment(
            url: rootfsURL,
            readOnly: false
        )
        let rootfsDevice = VZVirtioBlockDeviceConfiguration(attachment: rootfsAttachment)
        vmConfig.storageDevices = [rootfsDevice]

        // Data disk (if exists)
        let diskURL = KimaPaths.diskImageFile
        if FileManager.default.fileExists(atPath: diskURL.path(percentEncoded: false)) {
            let diskAttachment = try VZDiskImageStorageDeviceAttachment(
                url: diskURL,
                readOnly: false
            )
            let diskDevice = VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
            vmConfig.storageDevices.append(diskDevice)
        }

        // Network: NAT
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        vmConfig.networkDevices = [networkDevice]

        // vsock
        let vsockDevice = VZVirtioSocketDeviceConfiguration()
        vmConfig.socketDevices = [vsockDevice]

        // Serial console (hvc0)
        let consoleLogURL = KimaPaths.consoleLogFile
        if !FileManager.default.fileExists(atPath: consoleLogURL.path(percentEncoded: false)) {
            FileManager.default.createFile(atPath: consoleLogURL.path(percentEncoded: false), contents: nil)
        }
        let logFileHandle = try FileHandle(forWritingTo: consoleLogURL)
        logFileHandle.seekToEndOfFile()

        let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
        serialPort.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: nil,
            fileHandleForWriting: logFileHandle
        )
        vmConfig.serialPorts = [serialPort]

        // Entropy
        vmConfig.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        try vmConfig.validate()
        return vmConfig
    }
}
