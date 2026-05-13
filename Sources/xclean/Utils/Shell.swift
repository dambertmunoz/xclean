import Foundation

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var success: Bool { exitCode == 0 }
}

enum Shell {
    /// Synchronously run an executable. Returns captured stdout/stderr/exit code.
    /// Does not throw on non-zero exit; inspect `success`.
    ///
    /// Drains stdout and stderr **in parallel** — reading one pipe to EOF
    /// while the child is still writing to the other can fill the pipe
    /// buffer (~64 KB on macOS) and deadlock the child. Each pipe gets its
    /// own dispatch queue; we wait for both via DispatchGroup.
    ///
    /// - Parameter env: if provided, overrides the child's environment.
    ///   Pass `nil` to inherit the current process environment.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], env: [String: String]? = nil) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        if let env = env { process.environment = env }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let q = DispatchQueue.global(qos: .userInitiated)

        group.enter()
        q.async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        q.async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: "\(error)")
        }

        process.waitUntilExit()
        group.wait()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Convenience for `/usr/bin/xcrun <subcmd> <args>`.
    @discardableResult
    static func xcrun(_ args: [String]) -> ShellResult {
        return run("/usr/bin/xcrun", args)
    }
}
