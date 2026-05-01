import Foundation
import Network

enum RCONService {
    private enum PacketType {
        static let auth: Int32 = 3
        static let exec: Int32 = 2
    }

    static func execute(host: String, port: UInt16, password: String, command: String) async throws -> String {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 25575), using: .tcp)
        try await start(connection: connection)
        defer {
            connection.cancel()
        }

        let authId = Int32(101)
        try await sendPacket(connection: connection, id: authId, type: PacketType.auth, body: password)
        let authResponse = try await receivePacket(connection: connection)
        guard authResponse.id == authId else {
            throw GlobalError.validation(
                chineseMessage: "RCON 认证失败，请检查密码",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }

        let cmdId = Int32(102)
        try await sendPacket(connection: connection, id: cmdId, type: PacketType.exec, body: command)
        let response = try await receivePacket(connection: connection)
        guard response.id == cmdId else {
            throw GlobalError.validation(
                chineseMessage: "RCON 命令执行失败",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        return response.body
    }

    private static func start(connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func sendPacket(connection: NWConnection, id: Int32, type: Int32, body: String) async throws {
        let payload = encodePacket(id: id, type: type, body: body)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func receivePacket(connection: NWConnection) async throws -> (id: Int32, type: Int32, body: String) {
        let header = try await receiveExact(connection: connection, length: 4)
        let size = Int(header.withUnsafeBytes { $0.load(as: Int32.self).littleEndian })
        let content = try await receiveExact(connection: connection, length: size)
        let id = content.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self).littleEndian }
        let type = content.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self).littleEndian }
        let bodyData = content.subdata(in: 8..<(content.count - 2))
        let body = String(data: bodyData, encoding: .utf8) ?? ""
        return (id, type, body)
    }

    private static func receiveExact(connection: NWConnection, length: Int) async throws -> Data {
        var data = Data()
        while data.count < length {
            let chunk = try await receive(connection: connection, maxLength: length - data.count)
            if chunk.isEmpty {
                throw GlobalError.validation(
                    chineseMessage: "RCON 连接已断开，请确认服务器已启动且 enable-rcon、rcon.port、rcon.password 配置正确并已重启生效",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            }
            data.append(chunk)
        }
        return data
    }

    private static func receive(connection: NWConnection, maxLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
        }
    }

    private static func encodePacket(id: Int32, type: Int32, body: String) -> Data {
        var packet = Data()
        let bodyData = body.data(using: .utf8) ?? Data()
        var size = Int32(4 + 4 + bodyData.count + 2).littleEndian
        var packetId = id.littleEndian
        var packetType = type.littleEndian
        packet.append(Data(bytes: &size, count: 4))
        packet.append(Data(bytes: &packetId, count: 4))
        packet.append(Data(bytes: &packetType, count: 4))
        packet.append(bodyData)
        packet.append(0)
        packet.append(0)
        return packet
    }
}
