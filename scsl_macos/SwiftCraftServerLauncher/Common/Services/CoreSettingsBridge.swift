import Foundation

enum CoreSettingsScope: String {
    case general
    case game
    case mirror
    case theme
    case ai
}

enum CoreSettingsBridge {
    static func read<T: Decodable>(_ type: T.Type, scope: CoreSettingsScope) throws -> T {
        try runSync {
            let envelope: ScslCoreCLIEnvelope<T> = try await ScslCoreCLIService.shared.runJSON(
                arguments: ["settings", "read", "--scope", scope.rawValue]
            )
            return envelope.data
        }
    }

    static func write<T: Encodable>(_ value: T, scope: CoreSettingsScope) throws {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ScslCoreCLIError.invalidUTF8
        }
        let _: EmptyCLIResponse = try runSync {
            let envelope: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
                arguments: ["settings", "write", "--scope", scope.rawValue, "--json", json]
            )
            return envelope.data
        }
    }

    private static func runSync<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?

        Task {
            defer { semaphore.signal() }
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
        }

        semaphore.wait()
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw ScslCoreCLIError.executionFailed("未收到 core settings 返回结果")
        }
    }
}
