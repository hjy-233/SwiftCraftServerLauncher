import Foundation

enum ScslCoreCLIError: LocalizedError {
    case sourceRootMissing
    case bundledBinaryMissing
    case buildFailed(String)
    case executionFailed(String)
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .sourceRootMissing:
            return "未找到 scsl_core 工程目录"
        case .bundledBinaryMissing:
            return "未找到内置 scsl CLI"
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
    private var resolvedBinaryURL: URL?
    private let appName = "SwiftCraftServerLauncher"

    private init() {}

    func run(arguments: [String], standardInput: String? = nil) async throws -> String {
        let envelope: ScslCoreCLIEnvelope<String> = try await runJSON(
            arguments: arguments,
            standardInput: standardInput
        )
        return envelope.data
    }

    func runJSON<T: Decodable>(
        arguments: [String],
        standardInput: String? = nil
    ) async throws -> ScslCoreCLIEnvelope<T> {
        try await ensureBinary()
        guard let binaryURL = resolvedBinaryURL else {
            throw ScslCoreCLIError.executionFailed("未解析到可用的 scsl CLI")
        }
        let result = try await runProcess(
            executableURL: binaryURL,
            arguments: arguments,
            standardInput: standardInput
        )

        let payload = result.status == 0 ? result.stdout : result.stderr
        guard let output = String(data: payload, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatterWithFractionalSeconds = ISO8601DateFormatter()
            formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatterWithFractionalSeconds.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = formatterWithFractionalSeconds.date(from: dateString) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(dateString)"
            )
        }
        let envelope = try decoder.decode(ScslCoreCLIEnvelope<T>.self, from: data)
        guard result.status == 0 else {
            throw ScslCoreCLIError.executionFailed(envelope.error?.message ?? "无输出")
        }
        return envelope
    }

    private func ensureBinary() async throws {
        if didEnsureBinary,
           let resolvedBinaryURL,
           fileManager.fileExists(atPath: resolvedBinaryURL.path) {
            return
        }

        if let bundledBinaryURL = bundledBinaryURL() {
            resolvedBinaryURL = try syncBundledBinaryIfNeeded(from: bundledBinaryURL)
            didEnsureBinary = true
            return
        }

        let binaryURL = try developmentBinaryURL()
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

        resolvedBinaryURL = binaryURL
        didEnsureBinary = true
    }

    private func cargoManifestURL() throws -> URL {
        let root = try sourceRootURL()
        return root.appendingPathComponent("scsl_core", isDirectory: true)
            .appendingPathComponent("Cargo.toml", isDirectory: false)
    }

    private func developmentBinaryURL() throws -> URL {
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

    private func bundledBinaryURL() -> URL? {
        Bundle.main.url(forResource: "scsl", withExtension: nil, subdirectory: "cli")
    }

    private func managedBinaryURL() -> URL? {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return applicationSupport
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("scsl", isDirectory: false)
    }

    private func managedBinaryVersionURL() -> URL? {
        managedBinaryURL()?.deletingLastPathComponent().appendingPathComponent("scsl.version", isDirectory: false)
    }

    private func expectedBundledVersion() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0"
        let buildVersion = info["CFBundleVersion"] as? String ?? "0"
        return "\(shortVersion)+\(buildVersion)"
    }

    private func syncBundledBinaryIfNeeded(from bundledBinaryURL: URL) throws -> URL {
        guard let managedBinaryURL = managedBinaryURL(),
              let managedBinaryVersionURL = managedBinaryVersionURL() else {
            throw ScslCoreCLIError.bundledBinaryMissing
        }

        let expectedVersion = expectedBundledVersion()
        let currentVersion = try? String(contentsOf: managedBinaryVersionURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if fileManager.fileExists(atPath: managedBinaryURL.path),
           currentVersion == expectedVersion,
           managedBinaryMatchesBundled(managedBinaryURL: managedBinaryURL, bundledBinaryURL: bundledBinaryURL) {
            return managedBinaryURL
        }

        try fileManager.createDirectory(
            at: managedBinaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: managedBinaryURL.path) {
            try fileManager.removeItem(at: managedBinaryURL)
        }
        try fileManager.copyItem(at: bundledBinaryURL, to: managedBinaryURL)
        try setExecutableIfNeeded(at: managedBinaryURL)
        try expectedVersion.write(to: managedBinaryVersionURL, atomically: true, encoding: .utf8)
        return managedBinaryURL
    }

    private func managedBinaryMatchesBundled(managedBinaryURL: URL, bundledBinaryURL: URL) -> Bool {
        guard let managedAttributes = try? fileManager.attributesOfItem(atPath: managedBinaryURL.path),
              let bundledAttributes = try? fileManager.attributesOfItem(atPath: bundledBinaryURL.path),
              let managedSize = managedAttributes[.size] as? NSNumber,
              let bundledSize = bundledAttributes[.size] as? NSNumber,
              managedSize == bundledSize,
              let managedData = try? Data(contentsOf: managedBinaryURL),
              let bundledData = try? Data(contentsOf: bundledBinaryURL) else {
            return false
        }
        return managedData == bundledData
    }

    private func setExecutableIfNeeded(at url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
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
            let group = DispatchGroup()
            let lock = NSLock()
            var stdoutData = Data()
            var stderrData = Data()

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

            do {
                try process.run()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    lock.lock()
                    stdoutData = data
                    lock.unlock()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    lock.lock()
                    stderrData = data
                    lock.unlock()
                    group.leave()
                }
                DispatchQueue.global(qos: .utility).async {
                    process.waitUntilExit()
                    group.wait()
                    lock.lock()
                    let stdout = stdoutData
                    let stderr = stderrData
                    lock.unlock()
                    continuation.resume(returning: ProcessResult(
                        status: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct ScslCoreCLIEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T
    let error: ScslCoreCLIEnvelopeError?

    private enum CodingKeys: String, CodingKey {
        case ok
        case data
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try container.decode(Bool.self, forKey: .ok)
        self.error = try container.decodeIfPresent(ScslCoreCLIEnvelopeError.self, forKey: .error)
        self.data = try container.decodeIfPresent(T.self, forKey: .data) ?? Self.decodeDefaultValue()
    }

    private static func decodeDefaultValue() throws -> T {
        if T.self == EmptyCLIResponse.self, let empty = EmptyCLIResponse() as? T {
            return empty
        }
        throw DecodingError.valueNotFound(
            T.self,
            DecodingError.Context(codingPath: [], debugDescription: "scsl_cli 返回缺少 data 字段")
        )
    }
}

struct ScslCoreCLIEnvelopeError: Decodable {
    let message: String
}

struct EmptyCLIResponse: Decodable {}

private struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var combinedOutput: String {
        let out = String(bytes: stdout, encoding: .utf8) ?? ""
        let err = String(bytes: stderr, encoding: .utf8) ?? ""
        if out.isEmpty {
            return err
        }
        if err.isEmpty {
            return out
        }
        return out + "\n" + err
    }
}
