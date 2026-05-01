import Foundation
import Combine

@MainActor
final class ServerConsoleManager: ObservableObject {
    struct ConsoleEvent: Equatable {
        enum Kind: Equatable {
            case append
            case clear
        }

        let sequence: Int
        let serverId: String
        let text: String
        let kind: Kind
    }

    static let shared = ServerConsoleManager()

    @Published private(set) var logs: [String: [String]] = [:]
    @Published private(set) var latestEvent: ConsoleEvent?
    private var inputPipes: [String: Pipe] = [:]
    private var renderedCache: [String: AttributedString] = [:]
    private var commandDrafts: [String: String] = [:]
    private var nextSequence: Int = 0

    private init() {}

    func attach(serverId: String, input: Pipe, output: Pipe, error: Pipe) {
        inputPipes[serverId] = input

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.append(serverId: serverId, text: text)
                }
            }
        }

        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.append(serverId: serverId, text: text)
                }
            }
        }
    }

    func detach(serverId: String) {
        inputPipes.removeValue(forKey: serverId)
    }

    func clear(serverId: String) {
        logs[serverId] = []
        renderedCache[serverId] = nil
        publishEvent(serverId: serverId, text: "", kind: .clear)
    }

    func appendSystemMessage(serverId: String, message: String) {
        let line = "[SCSL] \(message)\n"
        append(serverId: serverId, text: line)
    }

    func send(serverId: String, command: String) {
        guard let pipe = inputPipes[serverId] else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let data = (trimmed + "\n").data(using: .utf8) {
            pipe.fileHandleForWriting.write(data)
        }
    }

    func commandDraft(for serverId: String) -> String {
        commandDrafts[serverId] ?? ""
    }

    func setCommandDraft(_ text: String, for serverId: String) {
        commandDrafts[serverId] = text
    }

    func logText(for serverId: String) -> String {
        let lines = logs[serverId] ?? []
        return lines.joined()
    }

    func logLines(for serverId: String) -> [String] {
        let chunks = logs[serverId] ?? []
        return chunks.joined().components(separatedBy: .newlines)
    }

    func appendExternal(serverId: String, text: String) {
        append(serverId: serverId, text: text)
    }

    func renderedText(for serverId: String) -> AttributedString? {
        renderedCache[serverId]
    }

    func setRenderedText(serverId: String, text: AttributedString) {
        renderedCache[serverId] = text
    }

    private func append(serverId: String, text: String) {
        if logs[serverId] == nil {
            logs[serverId] = []
        }
        logs[serverId]?.append(text)
        publishEvent(serverId: serverId, text: text, kind: .append)
    }

    private func publishEvent(serverId: String, text: String, kind: ConsoleEvent.Kind) {
        nextSequence += 1
        latestEvent = ConsoleEvent(
            sequence: nextSequence,
            serverId: serverId,
            text: text,
            kind: kind
        )
    }
}
