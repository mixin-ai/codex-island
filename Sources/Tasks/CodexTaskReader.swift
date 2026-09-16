import Foundation
import SQLite3

enum CodexTaskStatus: String, Equatable {
    case running, completed, interrupted, unknown

    var label: String {
        switch self {
        case .running: return "执行中"
        case .completed: return "已结束"
        case .interrupted: return "已中断"
        case .unknown: return "待确认"
        }
    }
}

struct CodexTaskItem: Identifiable, Equatable {
    let id: String
    let title: String
    let status: CodexTaskStatus
    let updatedAt: Date

    static func visible(_ items: [Self]) -> [Self] {
        Array(items.sorted {
            if ($0.status == .running) != ($1.status == .running) {
                return $0.status == .running
            }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }.prefix(3))
    }
}

struct CodexTaskLifecycle: Equatable {
    private(set) var status: CodexTaskStatus = .unknown
    private(set) var turnID: String?

    mutating func consume(type: String, turnID incoming: String?) {
        if type == "task_started" {
            status = .running
            turnID = incoming
        } else if type == "task_complete" || type == "turn_aborted" {
            if let turnID, let incoming, turnID != incoming { return }
            status = type == "task_complete" ? .completed : .interrupted
            turnID = incoming
        }
    }

    static func read(_ data: Data) -> Self {
        // Ignore a trailing partial JSONL record; Codex may be writing it now.
        guard var end = data.lastIndex(of: 10) else { return Self() }
        var events: [(String, String?)] = []
        let marker = Data("\"event_msg\"".utf8)
        let lifecycleMarkers = ["task_started", "task_complete", "turn_aborted"]
            .map { Data("\"\($0)\"".utf8) }
        while end > data.startIndex {
            let start = data[..<end].lastIndex(of: 10).map { $0 + 1 } ?? data.startIndex
            let line = data[start..<end]
            if line.count < 4_194_304,
               line.range(of: marker) != nil,
               lifecycleMarkers.contains(where: { line.range(of: $0) != nil }),
               let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               object["type"] as? String == "event_msg",
               let payload = object["payload"] as? [String: Any],
               let type = payload["type"] as? String,
               ["task_started", "task_complete", "turn_aborted"].contains(type) {
                events.append((type, payload["turn_id"] as? String))
                if type == "task_started" { break }
            }
            if start == data.startIndex { break }
            end = start - 1
        }
        var result = Self()
        for (type, turnID) in events.reversed() {
            result.consume(type: type, turnID: turnID)
        }
        return result
    }
}

final class CodexTaskReader: @unchecked Sendable {
    enum ReadError: Error { case unavailable }

    private struct CachedRollout {
        let bytes: Int
        let modified: Date
        let lifecycle: CodexTaskLifecycle
    }

    private let home: URL
    private let lock = NSLock()
    private var cache: [String: CachedRollout] = [:]

    init(home: URL = CodexTaskReader.defaultHome) { self.home = home }

    static var defaultHome: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    func read(now: Date = Date()) throws -> [CodexTaskItem] {
        lock.lock()
        defer { lock.unlock() }
        let database = home.appendingPathComponent("state_5.sqlite")
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(database.path, &pointer, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db = pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw ReadError.unavailable
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        var statement: OpaquePointer?
        let suffix = "FROM threads WHERE archived = 0 AND source NOT LIKE '%subagent%' ORDER BY updated_at DESC LIMIT 100"
        var sql = "SELECT id, COALESCE(NULLIF(name, ''), title), rollout_path, updated_at \(suffix)"
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            if let statement { sqlite3_finalize(statement) }
            statement = nil
            sql = "SELECT id, title, rollout_path, updated_at \(suffix)"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                if let statement { sqlite3_finalize(statement) }
                throw ReadError.unavailable
            }
        }
        guard let statement else { throw ReadError.unavailable }
        defer { sqlite3_finalize(statement) }

        var items: [CodexTaskItem] = []
        var seenPaths = Set<String>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw ReadError.unavailable }
            let id = text(statement, column: 0)
            let title = Self.title(text(statement, column: 1))
            let path = text(statement, column: 2)
            let updated = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)))
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let allowedRoot = home.appendingPathComponent("sessions").resolvingSymlinksInPath().path + "/"
            guard url.path.hasPrefix(allowedRoot), url.pathExtension == "jsonl" else { continue }
            seenPaths.insert(path)
            var status: CodexTaskStatus = .unknown
            var lastActivity = updated
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modified = attributes[.modificationDate] as? Date,
               let bytes = attributes[.size] as? NSNumber {
                lastActivity = max(updated, modified)
                let lifecycle: CodexTaskLifecycle
                if let saved = cache[path], saved.bytes == bytes.intValue, saved.modified == modified {
                    lifecycle = saved.lifecycle
                } else if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                    lifecycle = CodexTaskLifecycle.read(data)
                    cache[path] = CachedRollout(bytes: bytes.intValue, modified: modified, lifecycle: lifecycle)
                } else {
                    lifecycle = CodexTaskLifecycle()
                }
                status = lifecycle.status
                // A crash can leave a start without an end. Do not advertise
                // an old, silent rollout as an actively running task forever.
                if status == .running, now.timeIntervalSince(lastActivity) > 1800 { status = .unknown }
            }
            items.append(CodexTaskItem(id: id, title: title, status: status, updatedAt: lastActivity))
        }
        cache = cache.filter { seenPaths.contains($0.key) }
        return CodexTaskItem.visible(items)
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private static func title(_ raw: String) -> String {
        let firstLine = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        if firstLine.isEmpty || firstLine.hasPrefix("# Files mentioned") { return "未命名任务" }
        return String(firstLine.prefix(240))
    }
}
