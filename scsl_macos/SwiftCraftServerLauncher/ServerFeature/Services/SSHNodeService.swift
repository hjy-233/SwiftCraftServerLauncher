import Foundation

// swiftlint:disable type_body_length file_length
enum SSHNodeService {
    struct ConnectionResult {
        let output: String
    }

    struct PortProcessInfo: Identifiable {
        let id = UUID()
        let pid: Int
        let command: String
        let user: String
    }

    static func testConnectionAndPrepareDirectories(node: ServerNode, password: String) async throws -> ConnectionResult {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = """
        mkdir -p '\(escapeSingleQuotes(root))' '\(escapeSingleQuotes("\(root)/servers"))' '\(escapeSingleQuotes("\(root)/data"))' '\(escapeSingleQuotes("\(root)/logs"))' && echo __SCSL_OK__ && uname -a && whoami
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        guard output.contains("__SCSL_OK__") else {
            throw GlobalError.validation(
                chineseMessage: "SSH 连接成功但目录探测失败",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        return ConnectionResult(output: output)
    }

    static func prepareRemoteServerDirectoryAndDownload(
        node: ServerNode,
        serverName: String,
        target: ServerDownloadService.DownloadTarget
    ) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        var headerPart = ""
        if let headers = target.headers, !headers.isEmpty {
            headerPart = headers.map { "-H '\(escapeSingleQuotes("\($0.key): \($0.value)"))'" }.joined(separator: " ")
        }
        let doneFlag = "\(serverDir)/.scsl_download_done"
        let failFlag = "\(serverDir)/.scsl_download_failed"
        let startCommand = """
        mkdir -p '\(escapeSingleQuotes(serverDir))' && rm -f '\(escapeSingleQuotes(doneFlag))' '\(escapeSingleQuotes(failFlag))' && \
        curl -fsSL \(headerPart) '\(escapeSingleQuotes(target.url.absoluteString))' -o '\(escapeSingleQuotes("\(serverDir)/\(target.fileName)"))' && \
        printf "eula=true\\n" > '\(escapeSingleQuotes("\(serverDir)/eula.txt"))' && \
        touch '\(escapeSingleQuotes(doneFlag))' && \
        printf "__SCSL_DONE__\\n"
        """
        do {
            let startOutput = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: startCommand,
                successMarker: "__SCSL_DONE__",
                timeoutSeconds: 1800
            )
            guard startOutput.contains("__SCSL_DONE__") else {
                throw GlobalError.validation(
                    chineseMessage: "远程下载失败，请检查 SSH 输出",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            }
            return
        } catch {
            _ = try? await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: "touch '\(escapeSingleQuotes(failFlag))'",
                timeoutSeconds: 10
            )
            // 命令可能在落盘后 SSH 会话抖动，进入轮询兜底判断。
            if !isRetryablePollingSSHError(error) {
                throw error
            }
        }

        let startTime = Date()
        let maxWaitSeconds: TimeInterval = 1800
        var retryablePollingErrorCount = 0
        while Date().timeIntervalSince(startTime) < maxWaitSeconds {
            do {
                if try await verifyRemoteServerPrepared(
                    node: node,
                    password: password,
                    serverName: serverName,
                    jarFileName: target.fileName
                ) {
                    return
                }
                retryablePollingErrorCount = 0
            } catch {
                // 轮询阶段允许短暂 SSH 抖动，避免目录已创建完成但被瞬时网络错误打断。
                if !isRetryablePollingSSHError(error) {
                    throw error
                }
                retryablePollingErrorCount += 1
                let elapsed = Date().timeIntervalSince(startTime)
                if retryablePollingErrorCount >= 5, elapsed >= 15 {
                    Logger.shared.warning("远程轮询连续 SSH 抖动，按已创建完成处理: \(serverName)")
                    return
                }
            }

            let failCheckCommand = """
            if test -f '\(escapeSingleQuotes(failFlag))'; then printf "__SCSL_FAIL__\\n"; fi
            """
            do {
                let failOutput = try await runExpectSSH(
                    host: node.host,
                    port: node.port,
                    username: node.username,
                    password: password,
                    remoteCommand: failCheckCommand,
                    successMarker: "__SCSL_FAIL__",
                    timeoutSeconds: 20
                )
                if failOutput.contains("__SCSL_FAIL__") {
                    throw GlobalError.validation(
                        chineseMessage: "远程下载失败，请检查网络或镜像源",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                }
            } catch {
                if !isRetryablePollingSSHError(error) {
                    throw error
                }
                retryablePollingErrorCount += 1
            }

            try await Task.sleep(nanoseconds: 3_000_000_000)
        }

        if retryablePollingErrorCount > 0 {
            Logger.shared.warning("远程下载轮询超时且存在 SSH 抖动，按已创建完成处理: \(serverName)")
            return
        }
        throw GlobalError.validation(
            chineseMessage: "远程下载超时，请稍后在远程目录确认文件是否已完成",
            i18nKey: "error.validation.server_not_selected",
            level: .notification
        )
    }

    private static func isRetryablePollingSSHError(_ error: Error) -> Bool {
        let message = GlobalError.from(error).chineseMessage
        return message.contains("SSH 执行失败(exit=255)")
            || message.contains("__SCSL_EXPECT_TIMEOUT__")
            || message.contains("远程系统正在启动中")
    }

    private static func verifyRemoteServerPrepared(
        node: ServerNode,
        password: String,
        serverName: String,
        jarFileName: String
    ) async throws -> Bool {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = """
        if test -f '\(escapeSingleQuotes("\(serverDir)/\(jarFileName)"))' || ls '\(escapeSingleQuotes(serverDir))'/*.jar >/dev/null 2>&1; then printf "__SCSL_READY__\\n"; fi
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command,
            successMarker: "__SCSL_READY__",
            timeoutSeconds: 20
        )
        return output.contains("__SCSL_READY__")
    }

    static func deleteRemoteServerDirectory(node: ServerNode, serverName: String) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = """
        if test -d '\(escapeSingleQuotes(serverDir))'; then rm -rf '\(escapeSingleQuotes(serverDir))'; fi && echo __SCSL_DELETED__
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        guard output.contains("__SCSL_DELETED__") else {
            throw GlobalError.validation(
                chineseMessage: "远程删除服务器目录失败，请检查 SSH 输出",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func waitForRemoteServerJar(
        node: ServerNode,
        serverName: String,
        expectedJarName: String,
        timeoutSeconds: Int = 30,
        pollIntervalSeconds: Int = 3
    ) async -> Bool {
        guard let password = try? loadPassword(for: node) else {
            return false
        }
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let start = Date()

        while Date().timeIntervalSince(start) < Double(timeoutSeconds) {
            let checkCommand = """
            if test -f '\(escapeSingleQuotes("\(serverDir)/\(expectedJarName)"))' || ls '\(escapeSingleQuotes(serverDir))'/*.jar >/dev/null 2>&1; then printf "__SCSL_READY__\\n"; fi
            """
            if let output = try? await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: checkCommand,
                successMarker: "__SCSL_READY__",
                timeoutSeconds: 15
            ),
            output.contains("__SCSL_READY__") {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds) * 1_000_000_000)
        }
        return false
    }

    static func verifyRemoteJarIntegrity(
        node: ServerNode,
        serverName: String,
        jarFileName: String
    ) async throws -> Bool {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && \
        if ! test -f '\(escapeSingleQuotes(jarFileName))'; then echo __SCSL_JAR_MISSING__; \
        elif ! command -v java >/dev/null 2>&1; then echo __SCSL_JAVA_MISSING__; \
        elif java -jar '\(escapeSingleQuotes(jarFileName))' --help >/tmp/scsl-jar-check.log 2>&1; then echo __SCSL_JAR_OK__; \
        elif grep -qi 'Invalid or corrupt jarfile' /tmp/scsl-jar-check.log; then echo __SCSL_JAR_BAD__; \
        else echo __SCSL_JAR_OK__; fi
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command,
            timeoutSeconds: 45
        )
        if output.contains("__SCSL_JAR_BAD__") || output.contains("__SCSL_JAR_MISSING__") {
            return false
        }
        return true
    }

    static func redownloadRemoteServerJar(
        node: ServerNode,
        serverName: String,
        target: ServerDownloadService.DownloadTarget
    ) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        var headerPart = ""
        if let headers = target.headers, !headers.isEmpty {
            headerPart = headers.map { "-H '\(escapeSingleQuotes("\($0.key): \($0.value)"))'" }.joined(separator: " ")
        }
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && \
        rm -f '\(escapeSingleQuotes(target.fileName))' && \
        curl -fsSL \(headerPart) '\(escapeSingleQuotes(target.url.absoluteString))' -o '\(escapeSingleQuotes(target.fileName))' && \
        echo __SCSL_REDOWNLOADED__
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command,
            successMarker: "__SCSL_REDOWNLOADED__",
            timeoutSeconds: 1800
        )
        guard output.contains("__SCSL_REDOWNLOADED__") else {
            throw GlobalError.validation(
                chineseMessage: "远程重下 Jar 失败",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func startRemoteServer(
        node: ServerNode,
        server: ServerInstance,
        launchCommand: String
    ) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(server.name)"
        let helper = "\(root)/.scsl/scsl-helper.sh"
        let helperCommand = """
        cd '\(escapeSingleQuotes(serverDir))' && \
        (test -f eula.txt || printf "eula=true\\n" > eula.txt) && \
        '\(escapeSingleQuotes(helper))' start '\(escapeSingleQuotes(serverDir))' '\(escapeSingleQuotes(launchCommand))'
        """
        let fallbackCommand = """
        cd '\(escapeSingleQuotes(serverDir))' && \
        (test -f eula.txt || printf "eula=true\\n" > eula.txt) && \
        if test -f .scsl.pid && kill -0 $(cat .scsl.pid) 2>/dev/null; then \
          echo __SCSL_ALREADY_RUNNING__; \
        else \
          rm -f .scsl.pid .scsl.stdin; \
          mkfifo .scsl.stdin && \
          nohup /bin/sh -lc 'tail -f .scsl.stdin | /bin/sh -lc \"\(escapeSingleQuotes(launchCommand))\"' >> scsl-server.log 2>&1 & \
          echo $! > .scsl.pid; \
          sleep 1; \
          if test -f .scsl.pid && kill -0 $(cat .scsl.pid) 2>/dev/null; then echo __SCSL_STARTED__; else echo __SCSL_START_FAILED__; fi; \
        fi
        """
        let output: String
        do {
            try await ensureRemoteHelper(node: node, password: password)
            output = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: helperCommand
            )
        } catch {
            output = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: fallbackCommand
            )
        }
        if output.contains("__SCSL_ALREADY_RUNNING__") {
            throw GlobalError.validation(
                chineseMessage: "服务器已在运行，请先停止当前实例或直接查看控制台",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        guard output.contains("__SCSL_STARTED__") else {
            throw GlobalError.validation(
                chineseMessage: "远程启动失败，请检查 SSH 输出: \(output.trimmingCharacters(in: .whitespacesAndNewlines))",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func stopRemoteServer(
        node: ServerNode,
        server: ServerInstance
    ) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(server.name)"
        let helper = "\(root)/.scsl/scsl-helper.sh"
        let helperCommand = """
        '\(escapeSingleQuotes(helper))' stop '\(escapeSingleQuotes(serverDir))' '\(escapeSingleQuotes(server.serverJar))' && echo __SCSL_STOPPED__
        """
        let fallbackCommand = """
        cd '\(escapeSingleQuotes(serverDir))' && \
        if test -f .scsl.pid; then kill $(cat .scsl.pid) 2>/dev/null || true; rm -f .scsl.pid; fi && \
        rm -f .scsl.stdin && pkill -f '\(escapeSingleQuotes(server.serverJar))' || true && echo __SCSL_STOPPED__
        """
        do {
            try await ensureRemoteHelper(node: node, password: password)
            _ = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: helperCommand
            )
        } catch {
            _ = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: fallbackCommand
            )
        }
    }

    static func remoteServerDirectoryExists(node: ServerNode, serverName: String) async throws -> Bool {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = """
        if test -d '\(escapeSingleQuotes(serverDir))'; then echo __SCSL_EXISTS__; else echo __SCSL_MISSING__; fi
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        return output.contains("__SCSL_EXISTS__")
    }

    static func fetchRemoteServerLog(
        node: ServerNode,
        serverName: String,
        maxLines: Int = 300
    ) async throws -> String {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let helper = "\(root)/.scsl/scsl-helper.sh"
        let helperCommand = """
        '\(escapeSingleQuotes(helper))' log '\(escapeSingleQuotes(serverDir))' '\(maxLines)'
        """
        let fallbackCommand = """
        if cd '\(escapeSingleQuotes(serverDir))' 2>/dev/null; then \
          if test -f scsl-server.log && test -s scsl-server.log; then \
            tail -n \(maxLines) scsl-server.log; \
          elif test -f logs/latest.log; then \
            tail -n \(maxLines) logs/latest.log; \
          elif test -f latest.log; then \
            tail -n \(maxLines) latest.log; \
          elif test -f server.log; then \
            tail -n \(maxLines) server.log; \
          else \
            echo ""; \
          fi; \
        else \
          echo "__SCSL_LOG_DIR_MISSING__"; \
        fi
        """
        do {
            let helperOutput = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: helperCommand,
                useTTY: false
            )
            if !helperOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return helperOutput
            }
            // Helper may return empty even when Minecraft writes logs/latest.log.
            return try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: fallbackCommand,
                useTTY: false
            )
        } catch {
            return try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: fallbackCommand,
                useTTY: false
            )
        }
    }

    static func updateRemoteServerProperties(node: ServerNode, server: ServerInstance) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(server.name)"
        let enableRcon = "false"
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && touch server.properties && \
        if grep -q '^enable-rcon=' server.properties; then sed -i.bak 's/^enable-rcon=.*/enable-rcon=\(enableRcon)/' server.properties; else echo 'enable-rcon=\(enableRcon)' >> server.properties; fi && \
        if grep -q '^rcon.port=' server.properties; then sed -i.bak 's/^rcon.port=.*/rcon.port=\(server.rconPort)/' server.properties; else echo 'rcon.port=\(server.rconPort)' >> server.properties; fi && \
        if grep -q '^rcon.password=' server.properties; then sed -i.bak 's|^rcon.password=.*|rcon.password=\(escapeSingleQuotes(server.rconPassword))|' server.properties; else echo 'rcon.password=\(escapeSingleQuotes(server.rconPassword))' >> server.properties; fi && \
        rm -f server.properties.bak && echo __SCSL_PROPS_OK__
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        guard output.contains("__SCSL_PROPS_OK__") else {
            throw GlobalError.validation(
                chineseMessage: "远程配置 server.properties 失败",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func ensureRemoteJava21(node: ServerNode) async throws {
        let password = try loadPassword(for: node)
        let command = """
        has_java21() {
          if command -v java21 >/dev/null 2>&1; then
            return 0
          fi
          if command -v java >/dev/null 2>&1; then
            JAVA_VERSION_LINE="$(java -version 2>&1 | head -n 1)"
            JAVA_MAJOR="$(printf "%s" "$JAVA_VERSION_LINE" | cut -d '"' -f 2 | cut -d '.' -f 1)"
            if test -n "$JAVA_MAJOR" && test "$JAVA_MAJOR" -ge 21; then
              return 0
            fi
          fi
          return 1
        }

        if has_java21; then
          echo __SCSL_JAVA21_OK__
          exit 0
        fi

        INSTALL_STATUS="unknown"
        if command -v apt-get >/dev/null 2>&1; then
          export DEBIAN_FRONTEND=noninteractive
          apt-get update -y && (apt-get install -y openjdk-21-jre-headless || apt-get install -y openjdk-21-jdk-headless) && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v dnf >/dev/null 2>&1; then
          dnf install -y java-21-openjdk-headless && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v yum >/dev/null 2>&1; then
          (yum install -y java-21-openjdk-headless || yum install -y java-21-openjdk) && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v zypper >/dev/null 2>&1; then
          zypper --non-interactive install java-21-openjdk-headless && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v pacman >/dev/null 2>&1; then
          pacman -Sy --noconfirm jre21-openjdk && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v apk >/dev/null 2>&1; then
          apk add --no-cache openjdk21-jre && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        else
          INSTALL_STATUS="no_package_manager"
        fi

        if has_java21; then
          echo __SCSL_JAVA21_OK__
        else
          echo __SCSL_JAVA21_FAIL__:$INSTALL_STATUS
        fi
        exit 0
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        guard output.contains("__SCSL_JAVA21_OK__") else {
            throw GlobalError.validation(
                chineseMessage: "远程未能自动安装 Java 21，请手动安装后重试。输出: \(output.trimmingCharacters(in: .whitespacesAndNewlines))",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func execute(node: ServerNode, remoteCommand: String, timeoutSeconds: Int = 60) async throws -> String {
        let password = try loadPassword(for: node)
        return try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: remoteCommand,
            timeoutSeconds: timeoutSeconds
        )
    }

    static func readRemoteServerProperties(node: ServerNode, serverName: String) async throws -> [String: String] {
        let content = try await readRemoteConfigFile(
            node: node,
            serverName: serverName,
            relativePath: "server.properties"
        )
        return parseProperties(content)
    }

    static func writeRemoteServerProperties(node: ServerNode, serverName: String, properties: [String: String]) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let keys = properties.keys.sorted()
        let lines = keys.map { "\($0)=\(properties[$0] ?? "")" }
        let content = lines.joined(separator: "\n") + "\n"
        let base64 = Data(content.utf8).base64EncodedString()
        let command = "cd '\(escapeSingleQuotes(serverDir))' && printf '%s' '\(base64)' | base64 -d > server.properties"
        _ = try await execute(node: node, remoteCommand: command)
    }

    static func remotePortProcesses(node: ServerNode, port: Int) async throws -> [PortProcessInfo] {
        let command = """
        if command -v lsof >/dev/null 2>&1; then
          lsof -nP -iTCP:\(port) -sTCP:LISTEN | awk 'NR>1 {print $2 "|" $1 "|" $3}'
        elif command -v ss >/dev/null 2>&1; then
          ss -ltnp 'sport = :\(port)' | sed -n 's/.*pid=\\([0-9][0-9]*\\),fd=[0-9][0-9]*.*/\\1|unknown|unknown/p'
        else
          echo ""
        fi
        """
        let output = try await execute(node: node, remoteCommand: command)
        return output
            .split(separator: "\n")
            .map(String.init)
            .compactMap { line in
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3, let pid = Int(parts[0]) else { return nil }
                return PortProcessInfo(pid: pid, command: parts[1], user: parts[2])
            }
    }

    static func killRemoteProcess(node: ServerNode, pid: Int) async throws {
        let command = "kill -TERM \(pid) 2>/dev/null || kill -9 \(pid) 2>/dev/null || true"
        _ = try await execute(node: node, remoteCommand: command)
    }

    static func listRemoteWorlds(node: ServerNode, serverName: String) async throws -> [String] {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = "cd '\(escapeSingleQuotes(serverDir))' && ls -1d world* 2>/dev/null || true"
        let output = try await execute(node: node, remoteCommand: command)
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func removeRemoteWorld(node: ServerNode, serverName: String, worldName: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = "cd '\(escapeSingleQuotes(serverDir))' && rm -rf '\(escapeSingleQuotes(worldName))'"
        _ = try await execute(node: node, remoteCommand: command)
    }

    static func uploadRemoteWorldDirectory(node: ServerNode, serverName: String, localURL: URL) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let worldName = localURL.lastPathComponent
        let target = "\(serverDir)/\(worldName)"
        _ = try await execute(
            node: node,
            remoteCommand: "mkdir -p '\(escapeSingleQuotes(serverDir))' && rm -rf '\(escapeSingleQuotes(target))'"
        )
        try await scpToRemote(node: node, localPath: localURL.path, remotePath: target, recursive: true)
    }

    static func sendRemoteDirectCommand(node: ServerNode, serverName: String, command: String) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let helper = "\(root)/.scsl/scsl-helper.sh"
        let helperCommand = "'\(escapeSingleQuotes(helper))' send '\(escapeSingleQuotes(serverDir))' '\(escapeSingleQuotes(command))'"
        let fallbackCommand = """
        cd '\(escapeSingleQuotes(serverDir))' && \
        if test -p .scsl.stdin; then printf '%s\\n' '\(escapeSingleQuotes(command))' > .scsl.stdin && echo __SCSL_SENT__; else echo __SCSL_STDIN_MISSING__; fi
        """
        do {
            try await ensureRemoteHelper(node: node, password: password)
            let output = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: helperCommand
            )
            guard output.contains("__SCSL_SENT__") else {
                throw GlobalError.validation(
                    chineseMessage: "远程控制台未连接到运行中的服务器进程，请先启动服务器",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            }
        } catch {
            let output = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: fallbackCommand
            )
            guard output.contains("__SCSL_SENT__") else {
                throw GlobalError.validation(
                    chineseMessage: "远程控制台未连接到运行中的服务器进程，请先启动服务器",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            }
        }
    }

    static func sendRemoteInterrupt(node: ServerNode, serverName: String, force: Bool = false) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let helper = "\(root)/.scsl/scsl-helper.sh"
        let mode = force ? "force" : "soft"
        let helperCommand = "'\(escapeSingleQuotes(helper))' interrupt '\(escapeSingleQuotes(serverDir))' '\(mode)'"
        let fallbackCommand = """
        cd '\(escapeSingleQuotes(serverDir))' && \
        if test -p .scsl.stdin; then printf '%s\\n' 'stop' > .scsl.stdin || true; fi && \
        sleep 8 && \
        if test -f .scsl.pid; then \
          pid=$(cat .scsl.pid); \
          if test "\(mode)" = "force"; then \
            pkill -KILL -P "$pid" 2>/dev/null || true; \
            kill -KILL "$pid" 2>/dev/null || true; \
          else \
            if kill -0 "$pid" 2>/dev/null; then \
              pkill -INT -P "$pid" 2>/dev/null || true; \
              kill -INT "$pid" 2>/dev/null || true; \
              sleep 2; \
            fi; \
            if kill -0 "$pid" 2>/dev/null; then \
              pkill -TERM -P "$pid" 2>/dev/null || true; \
              kill -TERM "$pid" 2>/dev/null || true; \
            fi; \
          fi; \
          rm -f .scsl.pid .scsl.stdin; \
          echo __SCSL_INTERRUPTED__; \
        else \
          echo __SCSL_PID_MISSING__; \
        fi
        """
        do {
            try await ensureRemoteHelper(node: node, password: password)
            _ = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: helperCommand
            )
        } catch {
            _ = try await runExpectSSH(
                host: node.host,
                port: node.port,
                username: node.username,
                password: password,
                remoteCommand: fallbackCommand
            )
        }
    }

    static func executeRemoteRCON(
        node: ServerNode,
        serverName: String,
        port: Int,
        password: String,
        command: String
    ) async throws -> String {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let encodedPassword = Data(password.utf8).base64EncodedString()
        let encodedCommand = Data(command.utf8).base64EncodedString()
        let script = """
        cd '\(escapeSingleQuotes(serverDir))' && python3 - <<'PY'
        import base64, socket, struct, sys
        HOST = "127.0.0.1"
        PORT = \(port)
        PASSWORD = base64.b64decode("\(encodedPassword)").decode("utf-8")
        COMMAND = base64.b64decode("\(encodedCommand)").decode("utf-8")

        def send_packet(sock, req_id, ptype, body):
            b = body.encode("utf-8")
            pkt = struct.pack("<iii", len(b)+10, req_id, ptype) + b + b"\\x00\\x00"
            sock.sendall(pkt)

        def recv_packet(sock):
            head = sock.recv(4)
            if len(head) < 4:
                raise RuntimeError("eof")
            size = struct.unpack("<i", head)[0]
            data = b""
            while len(data) < size:
                chunk = sock.recv(size - len(data))
                if not chunk:
                    raise RuntimeError("eof")
                data += chunk
            req_id, ptype = struct.unpack("<ii", data[:8])
            body = data[8:-2].decode("utf-8", errors="replace")
            return req_id, ptype, body

        try:
            s = socket.create_connection((HOST, PORT), timeout=6.0)
            send_packet(s, 101, 3, PASSWORD)
            rid, _, _ = recv_packet(s)
            if rid != 101:
                print("__SCSL_RCON_AUTH_FAIL__")
                sys.exit(0)
            send_packet(s, 102, 2, COMMAND)
            rid, _, body = recv_packet(s)
            if rid != 102:
                print("__SCSL_RCON_EXEC_FAIL__")
            else:
                print("__SCSL_RCON_OK__")
                print(body)
        except Exception as e:
            print("__SCSL_RCON_ERR__:" + str(e))
        finally:
            try:
                s.close()
            except Exception:
                pass
        PY
        """
        let output = try await execute(node: node, remoteCommand: script)
        if output.contains("__SCSL_RCON_AUTH_FAIL__") {
            throw GlobalError.validation(
                chineseMessage: "RCON 认证失败，请检查密码",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        if output.contains("__SCSL_RCON_EXEC_FAIL__") {
            throw GlobalError.validation(
                chineseMessage: "RCON 命令执行失败",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        if let range = output.range(of: "__SCSL_RCON_ERR__:") {
            let detail = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            throw GlobalError.validation(
                chineseMessage: "RCON 连接失败: \(detail)",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        if let okRange = output.range(of: "__SCSL_RCON_OK__") {
            return String(output[okRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func listRemoteMods(node: ServerNode, serverName: String) async throws -> [String] {
        try await listRemoteJarFiles(node: node, serverName: serverName, subDirectory: "mods")
    }

    static func listRemotePlugins(node: ServerNode, serverName: String) async throws -> [String] {
        try await listRemoteJarFiles(node: node, serverName: serverName, subDirectory: "plugins")
    }

    static func uploadRemoteMod(node: ServerNode, serverName: String, localURL: URL) async throws {
        try await uploadRemoteJar(node: node, serverName: serverName, subDirectory: "mods", localURL: localURL)
    }

    static func uploadRemotePlugin(node: ServerNode, serverName: String, localURL: URL) async throws {
        try await uploadRemoteJar(node: node, serverName: serverName, subDirectory: "plugins", localURL: localURL)
    }

    static func removeRemoteMod(node: ServerNode, serverName: String, fileName: String) async throws {
        try await removeRemoteJar(node: node, serverName: serverName, subDirectory: "mods", fileName: fileName)
    }

    static func removeRemotePlugin(node: ServerNode, serverName: String, fileName: String) async throws {
        try await removeRemoteJar(node: node, serverName: serverName, subDirectory: "plugins", fileName: fileName)
    }

    static func listRemoteConfigFiles(node: ServerNode, serverName: String) async throws -> [String] {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let marker = "__SCSL_FILE__"
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && find . -type f -size -1000k \\( -iname '*.properties' -o -iname '*.yml' -o -iname '*.yaml' -o -iname '*.toml' -o -iname '*.json' -o -iname '*.conf' -o -iname '*.cfg' -o -iname '*.ini' \\) ! -iname 'eula.txt' -print | sed 's#^\\./##' | while IFS= read -r f; do printf '\(marker)%s\\n' \"$f\"; done
        """
        let output = try await execute(node: node, remoteCommand: command)
        var files = output
            .components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { isValidRemoteConfigPath($0) }
            .filter { $0.lowercased() != "server.properties" }
            .sorted()
        if !files.contains("server.properties") {
            let hasServerProperties = try await execute(
                node: node,
                remoteCommand: "cd '\(escapeSingleQuotes(serverDir))' && if test -f server.properties; then echo yes; else echo no; fi"
            )
            _ = hasServerProperties
        }
        files = Array(Set(files)).sorted()
        Logger.shared.debug("远程配置文件扫描: \(serverName) -> \(files.count) 个, 示例: \(files.prefix(8).joined(separator: ", "))")
        return files
    }

    struct RemoteFileEntry: Hashable {
        let relativePath: String
        let isDirectory: Bool
    }

    static func listRemoteServerFiles(node: ServerNode, serverName: String) async throws -> [RemoteFileEntry] {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let marker = "__SCSL_FILE__"
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && find . -mindepth 1 -print | while IFS= read -r p; do if [ -d "$p" ]; then printf '\(marker)D|%s\\n' "${p#./}"; else printf '\(marker)F|%s\\n' "${p#./}"; fi; done
        """
        let output = try await execute(node: node, remoteCommand: command)
        let entries = output
            .components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { line -> RemoteFileEntry? in
                guard line.count > 2 else { return nil }
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                let kind = parts[0]
                let path = parts[1]
                guard isValidRemoteConfigPath(path) else { return nil }
                return RemoteFileEntry(relativePath: path, isDirectory: kind == "D")
            }
        return entries.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    static func createRemoteDirectory(node: ServerNode, serverName: String, relativePath: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = "cd '\(escapeSingleQuotes(serverDir))' && mkdir -p '\(escapeSingleQuotes(relativePath))'"
        _ = try await execute(node: node, remoteCommand: command)
    }

    static func moveRemotePath(node: ServerNode, serverName: String, from: String, to: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = "cd '\(escapeSingleQuotes(serverDir))' && mv '\(escapeSingleQuotes(from))' '\(escapeSingleQuotes(to))'"
        _ = try await execute(node: node, remoteCommand: command)
    }

    static func removeRemotePath(node: ServerNode, serverName: String, relativePath: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = "cd '\(escapeSingleQuotes(serverDir))' && rm -rf '\(escapeSingleQuotes(relativePath))'"
        _ = try await execute(node: node, remoteCommand: command)
    }

    static func uploadRemoteFile(node: ServerNode, serverName: String, localURL: URL, remoteDirectory: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let targetDir = remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteDirPath = targetDir.isEmpty ? serverDir : "\(serverDir)/\(targetDir)"
        _ = try await execute(node: node, remoteCommand: "mkdir -p '\(escapeSingleQuotes(remoteDirPath))'")
        let remotePath = "\(remoteDirPath)/\(localURL.lastPathComponent)"
        try await scpToRemote(node: node, localPath: localURL.path, remotePath: remotePath, recursive: localURL.hasDirectoryPath)
    }

    static func readRemoteConfigFile(node: ServerNode, serverName: String, relativePath: String) async throws -> String {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = "cd '\(escapeSingleQuotes(serverDir))' && (base64 -w 0 '\(escapeSingleQuotes(relativePath))' 2>/dev/null || base64 '\(escapeSingleQuotes(relativePath))')"
        let output = try await execute(node: node, remoteCommand: command)
        let compact = output.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        if let data = Data(base64Encoded: compact),
           let text = String(data: data, encoding: .utf8) {
            Logger.shared.debug("远程读取配置文件成功: \(serverName)/\(relativePath), 长度: \(text.count)")
            return text
        }
        Logger.shared.warning("远程读取配置文件 base64 解码失败，返回原文: \(serverName)/\(relativePath), 原始长度: \(output.count)")
        return output
    }

    static func writeRemoteConfigFile(node: ServerNode, serverName: String, relativePath: String, content: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let base64 = Data(content.utf8).base64EncodedString()
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && printf '%s' '\(base64)' | base64 -d > '\(escapeSingleQuotes(relativePath))'
        """
        _ = try await execute(node: node, remoteCommand: command)
    }

    private static func parseProperties(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if raw.hasPrefix("#") { continue }
            if let idx = raw.firstIndex(of: "=") {
                let key = String(raw[..<idx]).trimmingCharacters(in: .whitespaces)
                let value = String(raw[raw.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        return result
    }

    private static func isValidRemoteConfigPath(_ value: String) -> Bool {
        if value.contains("\u{0}") { return false }
        if value.contains("spawn ssh") { return false }
        if value.contains("StrictHostKeyChecking") { return false }
        if value.hasPrefix("-o ") { return false }
        if value.contains("password:") { return false }
        if value.contains("System is booting up") { return false }
        if value.contains("Warning: Permanently added") { return false }
        if value.contains("__SCSL_") { return false }
        if value.contains("\n") || value.contains("\r") { return false }
        return true
    }

    private static func listRemoteJarFiles(node: ServerNode, serverName: String, subDirectory: String) async throws -> [String] {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = "\(root)/servers/\(serverName)/\(subDirectory)"
        let output = try await execute(
            node: node,
            remoteCommand: "mkdir -p '\(escapeSingleQuotes(dir))' && cd '\(escapeSingleQuotes(dir))' && ls -1 *.jar 2>/dev/null || true"
        )
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private static func uploadRemoteJar(node: ServerNode, serverName: String, subDirectory: String, localURL: URL) async throws {
        guard localURL.pathExtension.lowercased() == "jar" else { return }
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = "\(root)/servers/\(serverName)/\(subDirectory)"
        _ = try await execute(node: node, remoteCommand: "mkdir -p '\(escapeSingleQuotes(dir))'")
        let remotePath = "\(dir)/\(localURL.lastPathComponent)"
        try await scpToRemote(node: node, localPath: localURL.path, remotePath: remotePath, recursive: false)
    }

    private static func removeRemoteJar(node: ServerNode, serverName: String, subDirectory: String, fileName: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = "\(root)/servers/\(serverName)/\(subDirectory)"
        _ = try await execute(
            node: node,
            remoteCommand: "cd '\(escapeSingleQuotes(dir))' && rm -f '\(escapeSingleQuotes(fileName))'"
        )
    }

    private static func runExpectSSH(
        host: String,
        port: Int,
        username: String,
        password: String,
        remoteCommand: String,
        successMarker: String? = nil,
        useTTY: Bool = true,
        timeoutSeconds: Int = 60
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")

            let wrappedCommand = wrapRemoteCommand(remoteCommand)
            let ttyFlag = useTTY ? "-tt" : ""
            let successMarkerExpect: String
            if let successMarker, !successMarker.isEmpty {
                successMarkerExpect = """
                -re {\(successMarker)} { send_user "\(escapeExpectString(successMarker))\\n"; exit 0 }
                """
            } else {
                successMarkerExpect = ""
            }
            let script = """
            log_user 1
            set timeout \(timeoutSeconds)
            spawn ssh \(ttyFlag) -p \(port) -o LogLevel=ERROR -o ConnectTimeout=10 -o ConnectionAttempts=1 -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \(username)@\(host) "\(escapeDoubleQuotes(wrappedCommand))"
            expect {
                -re {.*yes/no.*} { send "yes\\r"; exp_continue }
                -re {.*[Pp]assword:.*} { send "\(escapeExpectString(password))\\r"; exp_continue }
                -re {.*密码[:：].*} { send "\(escapeExpectString(password))\\r"; exp_continue }
                \(successMarkerExpect)
                timeout { send_user "__SCSL_EXPECT_TIMEOUT__\\n"; exit 124 }
                eof { }
            }
            catch wait result
            set code [lindex $result 3]
            exit $code
            """
            process.arguments = ["-c", script]

            process.terminationHandler = { _ in
            let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""
            let rawCombined = sanitizeSSHClientNoise(out + (err.isEmpty ? "" : "\n" + err))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let outOnly = sanitizeSSHClientNoise(out).trimmingCharacters(in: .whitespacesAndNewlines)
            let merged = sanitizeSSHClientNoise(out + (err.isEmpty ? "" : "\n" + err))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerAll = (outOnly + "\n" + merged).lowercased()
            if lowerAll.contains("pam_nologin") || lowerAll.contains("system is booting up") {
                continuation.resume(throwing: GlobalError.validation(
                    chineseMessage: "远程系统正在启动中，SSH 暂不可用，请稍后重试",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                ))
                return
            }
            if process.terminationStatus == 0 {
                    continuation.resume(returning: outOnly)
            } else {
                    let detail: String
                    if !merged.isEmpty {
                        detail = merged
                    } else if !rawCombined.isEmpty {
                        detail = rawCombined
                    } else {
                        detail = "无输出（可能是 SSH 认证失败、远程禁止 root 登录、或远程 shell 不可用）"
                    }
                    continuation.resume(throwing: GlobalError.validation(
                        chineseMessage: "SSH 执行失败(exit=\(process.terminationStatus)): \(detail)",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    ))
            }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func scpToRemote(
        node: ServerNode,
        localPath: String,
        remotePath: String,
        recursive: Bool
    ) async throws {
        let password = try loadPassword(for: node)
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")

            let recursiveFlag = recursive ? "-r " : ""
            let script = """
            log_user 0
            set timeout 1200
            match_max 2000000
            set output ""
            spawn scp \(recursiveFlag)-P \(node.port) -o LogLevel=ERROR -o ConnectTimeout=10 -o ConnectionAttempts=1 -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "\(escapeDoubleQuotes(localPath))" \(node.username)@\(node.host):"\(escapeDoubleQuotes(remotePath))"
            expect {
                -re {.*yes/no.*} { send "yes\\r"; exp_continue }
                -re {.*[Pp]assword:.*} { send "\(escapeExpectString(password))\\r"; exp_continue }
                -re {.*Permission denied.*} { append output $expect_out(0,string); puts $output; exit 255 }
                -re {.+} { append output $expect_out(0,string); exp_continue }
                timeout { puts $output; exit 124 }
                eof {
                    catch { append output $expect_out(buffer) }
                }
            }
            puts $output
            catch wait result
            set code [lindex $result 3]
            exit $code
            """
            process.arguments = ["-c", script]

            process.terminationHandler = { _ in
                let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                let merged = (out + (err.isEmpty ? "" : "\n" + err)).trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: GlobalError.validation(
                        chineseMessage: "SCP 上传失败: \(merged)",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func loadPassword(for node: ServerNode) throws -> String {
        let storageURL = AppPaths.dataDirectory.appendingPathComponent("server_node_passwords.json")
        guard
            let data = try? Data(contentsOf: storageURL),
            let dict = try? JSONDecoder().decode([String: String].self, from: data),
            let password = dict[node.id],
            !password.isEmpty
        else {
            throw GlobalError.validation(
                chineseMessage: "未找到节点密码，请重新执行连接测试",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        return password
    }

    private static func escapeDoubleQuotes(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func escapeExpectString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func escapeSingleQuotes(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private static func wrapRemoteCommand(_ command: String) -> String {
        let base64 = Data(command.utf8).base64EncodedString()
        return "printf %s '\(base64)' | base64 -d | /bin/sh"
    }

    private static func sanitizeSSHClientNoise(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return true }
                if trimmed.hasPrefix("spawn ssh ") { return false }
                if trimmed.contains("'s password:") { return false }
                if trimmed.hasPrefix("Warning: Permanently added") { return false }
                if trimmed.hasPrefix("Connection to ") && trimmed.hasSuffix(" closed.") { return false }
                if trimmed.hasPrefix("Connection to ") && trimmed.hasSuffix(" closed") { return false }
                return true
            }
            .joined(separator: "\n")
    }

    private static func ensureRemoteHelper(node: ServerNode, password: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let helperDir = "\(root)/.scsl"
        let helperPath = "\(helperDir)/scsl-helper.sh"
        let script = """
        #!/bin/sh
        set -eu
        action="$1"
        server_dir="${2:-}"
        case "$action" in
          start)
            launch_cmd="${3:-}"
            cd "$server_dir"
            if test -f .scsl.pid && kill -0 "$(cat .scsl.pid)" 2>/dev/null; then
              echo "__SCSL_ALREADY_RUNNING__"; exit 0
            fi
            rm -f .scsl.pid .scsl.stdin
            mkfifo .scsl.stdin
            launch_cmd_escaped="$(printf '%s' "$launch_cmd" | sed 's/\"/\\\\\"/g')"
            nohup /bin/sh -lc "tail -f .scsl.stdin | /bin/sh -lc \"$launch_cmd_escaped\"" >> scsl-server.log 2>&1 &
            echo $! > .scsl.pid
            sleep 1
            if test -f .scsl.pid && kill -0 "$(cat .scsl.pid)" 2>/dev/null; then
              echo "__SCSL_STARTED__"
            else
              echo "__SCSL_START_FAILED__"
              tail -n 120 scsl-server.log 2>/dev/null || true
            fi
            ;;
          stop)
            jar_hint="${3:-}"
            cd "$server_dir"
            if test -f .scsl.pid; then kill "$(cat .scsl.pid)" 2>/dev/null || true; rm -f .scsl.pid; fi
            rm -f .scsl.stdin
            if test -n "$jar_hint"; then pkill -f "$jar_hint" || true; fi
            ;;
          send)
            cmd="${3:-}"
            cd "$server_dir"
            if test -p .scsl.stdin; then
              printf '%s\\n' "$cmd" > .scsl.stdin
              echo "__SCSL_SENT__"
            else
              echo "__SCSL_STDIN_MISSING__"
              exit 3
            fi
            ;;
          interrupt)
            cd "$server_dir"
            mode="${3:-soft}"
            if test "$mode" != "force"; then
              if test -p .scsl.stdin; then printf '%s\\n' 'stop' > .scsl.stdin || true; fi
              sleep 8
            fi
            if test -f .scsl.pid; then
              pid="$(cat .scsl.pid)"
              if test "$mode" = "force"; then
                pkill -KILL -P "$pid" 2>/dev/null || true
                kill -KILL "$pid" 2>/dev/null || true
              else
                if kill -0 "$pid" 2>/dev/null; then
                  pkill -INT -P "$pid" 2>/dev/null || true
                  kill -INT "$pid" 2>/dev/null || true
                  sleep 2
                fi
                if kill -0 "$pid" 2>/dev/null; then
                  pkill -TERM -P "$pid" 2>/dev/null || true
                  kill -TERM "$pid" 2>/dev/null || true
                fi
              fi
              rm -f .scsl.pid .scsl.stdin
              echo "__SCSL_INTERRUPTED__"
            else
              echo "__SCSL_PID_MISSING__"
              exit 4
            fi
            ;;
          log)
            lines="${3:-300}"
            cd "$server_dir" 2>/dev/null || { echo "__SCSL_LOG_DIR_MISSING__"; exit 0; }
            if test -f scsl-server.log && test -s scsl-server.log; then
              tail -n "$lines" scsl-server.log
            elif test -f logs/latest.log; then
              tail -n "$lines" logs/latest.log
            elif test -f latest.log; then
              tail -n "$lines" latest.log
            elif test -f server.log; then
              tail -n "$lines" server.log
            else
              echo ""
            fi
            ;;
          *)
            exit 2
            ;;
        esac
        """
        let base64 = Data(script.utf8).base64EncodedString()
        let serviceName = "scsl-helper-bootstrap.service"
        let helperDirEscaped = escapeSingleQuotes(helperDir)
        let helperPathEscaped = escapeSingleQuotes(helperPath)
        let serviceBody = """
        [Unit]
        Description=SCSL Helper Bootstrap
        After=network.target

        [Service]
        Type=oneshot
        ExecStart=/bin/sh -lc 'mkdir -p '\(helperDirEscaped)' && test -f '\(helperPathEscaped)' && chmod +x '\(helperPathEscaped)' || true'
        RemainAfterExit=yes

        [Install]
        WantedBy=multi-user.target
        """
        let serviceBase64 = Data(serviceBody.utf8).base64EncodedString()
        let command = """
        mkdir -p '\(escapeSingleQuotes(helperDir))' && \
        printf '%s' '\(base64)' | base64 -d > '\(escapeSingleQuotes(helperPath))' && \
        chmod +x '\(escapeSingleQuotes(helperPath))' && \
        if test -x '\(escapeSingleQuotes(helperPath))'; then echo __SCSL_HELPER_OK__; else echo __SCSL_HELPER_FAIL__; fi && \
        if command -v systemctl >/dev/null 2>&1; then \
          printf '%s' '\(serviceBase64)' | base64 -d > /etc/systemd/system/\(serviceName) && \
          systemctl daemon-reload && \
          systemctl enable \(serviceName) >/dev/null 2>&1 || true && \
          systemctl start \(serviceName) >/dev/null 2>&1 || true && \
          echo __SCSL_HELPER_AUTOSTART_OK__; \
        else \
          (crontab -l 2>/dev/null; echo "@reboot mkdir -p '\(escapeSingleQuotes(helperDir))' && test -f '\(escapeSingleQuotes(helperPath))' && chmod +x '\(escapeSingleQuotes(helperPath))' || true") | crontab - 2>/dev/null || true && \
          echo __SCSL_HELPER_AUTOSTART_OK__; \
        fi
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        guard output.contains("__SCSL_HELPER_OK__") else {
            throw GlobalError.validation(
                chineseMessage: "远程 helper 安装失败",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }
}
// swiftlint:enable type_body_length
