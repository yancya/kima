import ArgumentParser

@main
struct Kima: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kima",
        abstract: "macOS native container management tool",
        subcommands: [
            MachineCommand.self,
            RunCommand.self,
            PsCommand.self,
            StopCommand.self,
            RmCommand.self,
            PullCommand.self,
            ImagesCommand.self,
            DaemonCommand.self,
        ]
    )
}
