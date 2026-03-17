import Foundation

enum CommandRunner {
    static func run(executable: String, arguments: [String]) throws -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        try task.run()
        task.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if task.terminationStatus == 0 {
            return output
        }

        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "CommandRunner", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: error])
    }
}
