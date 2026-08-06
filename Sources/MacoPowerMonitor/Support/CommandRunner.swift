import Foundation

enum CommandRunner {
    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) throws -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        try task.run()

        let outputBox = CommandOutputBox()
        let errorBox = CommandOutputBox()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBox.data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while task.isRunning {
            if Task.isCancelled {
                task.terminate()
                task.waitUntilExit()
                readers.wait()
                throw CancellationError()
            }
            if let deadline, Date() >= deadline {
                task.terminate()
                task.waitUntilExit()
                readers.wait()
                throw NSError(
                    domain: "CommandRunner",
                    code: Int(ETIMEDOUT),
                    userInfo: [NSLocalizedDescriptionKey: "Command timed out: \(executable)"]
                )
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        readers.wait()

        if task.terminationStatus == 0 {
            return outputBox.data
        }

        let error = String(data: errorBox.data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "CommandRunner", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: error])
    }
}

private final class CommandOutputBox: @unchecked Sendable {
    var data = Data()
}
