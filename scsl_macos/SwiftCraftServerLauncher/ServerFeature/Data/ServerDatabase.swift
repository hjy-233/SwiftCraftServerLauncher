import Foundation
import SQLite3

class ServerDatabase {
    private let db: SQLiteDatabase
    private let tableName = AppConstants.DatabaseTables.serverInstances

    init(dbPath: String) {
        self.db = SQLiteDatabase(path: dbPath)
    }

    func initialize() throws {
        try db.open()
        try createTable()
    }

    private func createTable() throws {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS \(tableName) (
            id TEXT PRIMARY KEY,
            working_path TEXT NOT NULL,
            server_name TEXT NOT NULL,
            data_json TEXT NOT NULL,
            last_played REAL NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """

        try db.execute(createTableSQL)

        let indexes = [
            ("idx_server_working_path", "working_path"),
            ("idx_server_last_played", "last_played"),
            ("idx_server_name", "server_name"),
        ]

        for (indexName, column) in indexes {
            let createIndexSQL = """
            CREATE INDEX IF NOT EXISTS \(indexName) ON \(tableName)(\(column));
            """
            try? db.execute(createIndexSQL)
        }
    }

    func saveServer(_ server: ServerInstance, workingPath: String) throws {
        try db.transaction {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let jsonData = try encoder.encode(server)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw GlobalError.validation(
                    chineseMessage: "无法编码服务器数据为 JSON",
                    i18nKey: "error.validation.json_encode_failed",
                    level: .notification
                )
            }

            let now = Date()
            let sql = """
            INSERT OR REPLACE INTO \(tableName)
            (id, working_path, server_name, data_json, last_played, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?,
                COALESCE((SELECT created_at FROM \(tableName) WHERE id = ?), ?),
                ?)
            """

            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            SQLiteDatabase.bind(statement, index: 1, value: server.id)
            SQLiteDatabase.bind(statement, index: 2, value: workingPath)
            SQLiteDatabase.bind(statement, index: 3, value: server.name)
            SQLiteDatabase.bind(statement, index: 4, value: jsonString)
            SQLiteDatabase.bind(statement, index: 5, value: server.lastPlayed)
            SQLiteDatabase.bind(statement, index: 6, value: server.id)
            SQLiteDatabase.bind(statement, index: 7, value: now)
            SQLiteDatabase.bind(statement, index: 8, value: now)

            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(db.database))
                throw GlobalError.validation(
                    chineseMessage: "保存服务器失败: \(errorMessage)",
                    i18nKey: "error.validation.server_save_failed",
                    level: .notification
                )
            }
        }
    }

    func saveServers(_ servers: [ServerInstance], workingPath: String) throws {
        try db.transaction {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let now = Date()

            let sql = """
            INSERT OR REPLACE INTO \(tableName)
            (id, working_path, server_name, data_json, last_played, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?,
                COALESCE((SELECT created_at FROM \(tableName) WHERE id = ?), ?),
                ?)
            """

            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            for server in servers {
                let jsonData = try encoder.encode(server)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continue
                }

                sqlite3_reset(statement)
                SQLiteDatabase.bind(statement, index: 1, value: server.id)
                SQLiteDatabase.bind(statement, index: 2, value: workingPath)
                SQLiteDatabase.bind(statement, index: 3, value: server.name)
                SQLiteDatabase.bind(statement, index: 4, value: jsonString)
                SQLiteDatabase.bind(statement, index: 5, value: server.lastPlayed)
                SQLiteDatabase.bind(statement, index: 6, value: server.id)
                SQLiteDatabase.bind(statement, index: 7, value: now)
                SQLiteDatabase.bind(statement, index: 8, value: now)

                let result = sqlite3_step(statement)
                guard result == SQLITE_DONE else {
                    let errorMessage = String(cString: sqlite3_errmsg(db.database))
                    throw GlobalError.validation(
                        chineseMessage: "批量保存服务器失败: \(errorMessage)",
                        i18nKey: "error.validation.servers_batch_save_failed",
                        level: .notification
                    )
                }
            }
        }
    }

    func loadServers(workingPath: String) throws -> [ServerInstance] {
        let sql = """
        SELECT data_json FROM \(tableName)
        WHERE working_path = ?
        ORDER BY last_played DESC
        """

        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        SQLiteDatabase.bind(statement, index: 1, value: workingPath)

        var servers: [ServerInstance] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let jsonString = SQLiteDatabase.stringColumn(statement, index: 0),
                  let jsonData = jsonString.data(using: .utf8) else {
                continue
            }

            do {
                let server = try decoder.decode(ServerInstance.self, from: jsonData)
                servers.append(server)
            } catch {
                Logger.shared.warning("解码服务器数据失败: \(error.localizedDescription)")
                continue
            }
        }

        return servers
    }

    func loadAllServers() throws -> [String: [ServerInstance]] {
        let sql = """
        SELECT working_path, data_json FROM \(tableName)
        ORDER BY working_path, last_played DESC
        """

        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        var grouped: [String: [ServerInstance]] = [:]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let workingPath = SQLiteDatabase.stringColumn(statement, index: 0),
                  let jsonString = SQLiteDatabase.stringColumn(statement, index: 1),
                  let jsonData = jsonString.data(using: .utf8) else {
                continue
            }

            do {
                let server = try decoder.decode(ServerInstance.self, from: jsonData)
                grouped[workingPath, default: []].append(server)
            } catch {
                Logger.shared.warning("解码服务器数据失败: \(error.localizedDescription)")
                continue
            }
        }

        return grouped
    }

    func deleteServer(id: String) throws {
        let sql = "DELETE FROM \(tableName) WHERE id = ?"
        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        SQLiteDatabase.bind(statement, index: 1, value: id)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db.database))
            throw GlobalError.validation(
                chineseMessage: "删除服务器失败: \(errorMessage)",
                i18nKey: "error.validation.server_delete_failed",
                level: .notification
            )
        }
    }

    func deleteServers(workingPath: String, serverName: String) throws {
        let sql = "DELETE FROM \(tableName) WHERE working_path = ? AND server_name = ?"
        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        SQLiteDatabase.bind(statement, index: 1, value: workingPath)
        SQLiteDatabase.bind(statement, index: 2, value: serverName)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(db.database))
            throw GlobalError.validation(
                chineseMessage: "删除服务器失败: \(errorMessage)",
                i18nKey: "error.validation.server_delete_failed",
                level: .notification
            )
        }
    }
}
