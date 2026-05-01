import Foundation

enum ScslCoreCLIError: LocalizedError {
    case sourceRootMissing
    case buildFailed(String)
    case executionFailed(String)
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .sourceRootMissing:
            return "未找到 scsl_core 工程目录"
        case .buildFailed(let detail):
            return "构建 scsl_cli 失败: \(detail)"
        case .executionFailed(let detail):
            return "执行 scsl_cli 失败: \(detail)"
        case .invalidUTF8:
            return "scsl_cli 返回了无效文本输出"
        }
    }
}

actor ScslCoreCLIService {
    static let shared = ScslCoreCLIService()

    private let fileManager = FileManager.default
    private var didEnsureBinary = false

    private init() {}

    func run(arguments: [String], standardInput: String? = nil) async throws -> String {
        try await ensureBinary()
        let binaryURL = try cliBinaryURL()
        let result = try await runProcess(
            executableURL: binaryURL,
            arguments: arguments,
            standardInput: standardInput
        )

        guard result.status == 0 else {
            let detail = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScslCoreCLIError.executionFailed(detail.isEmpty ? "无输出" : detail)
        }

        guard let output = String(data: result.stdout, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        return output
    }

    private func ensureBinary() async throws {
        if didEnsureBinary {
            return
        }

        let binaryURL = try cliBinaryURL()
        if !fileManager.fileExists(atPath: binaryURL.path) {
            let manifestPath = try cargoManifestURL().path
            let result = try await runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["cargo", "build", "--manifest-path", manifestPath, "-p", "scsl_cli", "--quiet"]
            )
            guard result.status == 0 else {
                let detail = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                throw ScslCoreCLIError.buildFailed(detail.isEmpty ? "无输出" : detail)
            }
        }

        didEnsureBinary = true
    }

    private func cargoManifestURL() throws -> URL {
        let root = try sourceRootURL()
        return root.appendingPathComponent("scsl_core", isDirectory: true)
            .appendingPathComponent("Cargo.toml", isDirectory: false)
    }

    private func cliBinaryURL() throws -> URL {
        let root = try sourceRootURL()
        return root.appendingPathComponent("scsl_core", isDirectory: true)
            .appendingPathComponent("target", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("scsl", isDirectory: false)
    }

    private func sourceRootURL() throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
        let root = url
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let cargoManifest = root
            .appendingPathComponent("scsl_core", isDirectory: true)
            .appendingPathComponent("Cargo.toml", isDirectory: false)
        guard fileManager.fileExists(atPath: cargoManifest.path) else {
            throw ScslCoreCLIError.sourceRootMissing
        }
        return root
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        standardInput: String? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            if let standardInput {
                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                stdinPipe.fileHandleForWriting.write(Data(standardInput.utf8))
                try? stdinPipe.fileHandleForWriting.close()
            }

            process.terminationHandler = { process in
                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ProcessResult(
                    status: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var combinedOutput: String {
        let out = String(data: stdout, encoding: .utf8) ?? ""
        let err = String(data: stderr, encoding: .utf8) ?? ""
        if out.isEmpty {
            return err
        }
        if err.isEmpty {
            return out
        }
        return out + "\n" + err
    }
}
