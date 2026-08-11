import Foundation

/// Runs Git commands asynchronously and terminates the subprocess when the
/// surrounding Swift task is cancelled.
enum GitProcessRunner {
    static func run(_ arguments: [String]) async -> String? {
        let process = CancellableGitProcess(arguments: arguments)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.run { output in
                    continuation.resume(returning: output)
                }
            }
        } onCancel: {
            process.cancel()
        }
    }
}

private final class CancellableGitProcess: @unchecked Sendable {
    private let arguments: [String]
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run(completion: @escaping @Sendable (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + self.arguments
            let output = Pipe()
            process.standardOutput = output
            // stderr is never read; route it to /dev/null so a chatty Git
            // process cannot fill a pipe buffer and wedge the refresh.
            process.standardError = FileHandle.nullDevice

            self.lock.lock()
            let shouldStart = !self.cancelled
            self.lock.unlock()
            guard shouldStart else {
                completion(nil)
                return
            }

            do {
                try process.run()
            } catch {
                completion(nil)
                return
            }

            self.lock.lock()
            if self.cancelled {
                self.lock.unlock()
                process.terminate()
            } else {
                self.process = process
                self.lock.unlock()
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            self.lock.lock()
            self.process = nil
            self.lock.unlock()

            guard process.terminationStatus == 0 else {
                completion(nil)
                return
            }
            completion(String(data: data, encoding: .utf8))
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
