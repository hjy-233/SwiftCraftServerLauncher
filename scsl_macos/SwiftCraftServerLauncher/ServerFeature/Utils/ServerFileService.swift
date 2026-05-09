import Foundation

enum ServerFileService {
    static func listFiles(server: ServerInstance) async throws -> [ServerFileItem] {
        let response: ScslCoreCLIEnvelope<[LocalServerFileEntry]> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "files", "list", server.id]
        )
        let entries = response.data
        return entries.map { entry in
            ServerFileItem(
                url: nil,
                relativePath: entry.relativePath,
                isDirectory: entry.isDirectory,
                fileSize: entry.fileSize.flatMap(Int.init(exactly:))
            )
        }
    }

    static func readFile(server: ServerInstance, relativePath: String) async throws -> String {
        let response: ScslCoreCLIEnvelope<ServerFileReadResponse> = try await ScslCoreCLIService.shared.runJSON(arguments: [
            "server", "files", "read", server.id, "--path", relativePath
        ])
        return response.data.content
    }

    static func writeFile(server: ServerInstance, relativePath: String, content: String) async throws {
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(
            arguments: ["server", "files", "write", server.id, "--path", relativePath],
            standardInput: content
        )
    }

    static func createDirectory(server: ServerInstance, relativePath: String) async throws {
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(arguments: [
            "server", "files", "mkdir", server.id, "--path", relativePath
        ])
    }

    static func createFile(server: ServerInstance, relativePath: String) async throws {
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(arguments: [
            "server", "files", "touch", server.id, "--path", relativePath
        ])
    }

    static func movePath(server: ServerInstance, from: String, to: String) async throws {
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(arguments: [
            "server", "files", "move", server.id, "--from", from, "--to", to
        ])
    }

    static func deletePath(server: ServerInstance, relativePath: String) async throws {
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(arguments: [
            "server", "files", "delete", server.id, "--path", relativePath
        ])
    }

    static func importPath(server: ServerInstance, sourceURL: URL, targetDirectory: String) async throws {
        let _: ScslCoreCLIEnvelope<EmptyCLIResponse> = try await ScslCoreCLIService.shared.runJSON(arguments: [
            "server", "files", "import", server.id,
            "--source", sourceURL.path,
            "--directory", targetDirectory,
        ])
    }
}

private struct LocalServerFileEntry: Decodable {
    let relativePath: String
    let isDirectory: Bool
    let fileSize: UInt64?

    private enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case isDirectory = "is_directory"
        case fileSize = "file_size"
    }
}

private struct ServerFileReadResponse: Decodable {
    let content: String
}
