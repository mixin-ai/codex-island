import Foundation
import SQLite3

@main
struct CodexTaskTests {
    static var failures = 0

    static func expect(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL") \(label)")
        if !value { failures += 1 }
    }

    static func event(_ type: String, turn: String = "a") -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"\(turn)\"}}\n"
    }

    static func parse(_ value: String) -> CodexTaskStatus {
        CodexTaskLifecycle.read(Data(value.utf8)).status
    }

    static func main() throws {
        expect(parse(event("task_started")) == .running, "start marks running")
        expect(parse(event("task_started") + event("task_complete")) == .completed, "completion ends current turn")
        expect(parse(event("task_started") + event("turn_aborted")) == .interrupted, "abort never looks completed")
        expect(parse(event("task_complete") + event("task_started", turn: "b")) == .running, "new turn clears old completion")
        expect(parse(event("task_started", turn: "b") + event("task_complete", turn: "a")) == .running, "late old completion cannot finish a new turn")
        expect(parse(event("task_started") + event("task_complete").dropLast()) == .running, "partial last record is ignored")
        expect(parse(event("task_started") + "malformed\n") == .running, "malformed line does not invent a status")
        expect(parse("{\"type\":\"response_item\",\"payload\":{\"type\":\"task_complete\"}}\n") == .unknown, "message content is not a lifecycle event")
        expect(parse("") == .unknown, "empty log is unknown")

        let now = Date()
        let sample = [
            CodexTaskItem(id: "done", title: "已完成任务", status: .completed, updatedAt: now),
            CodexTaskItem(id: "run", title: "运行任务", status: .running, updatedAt: now.addingTimeInterval(-20)),
            CodexTaskItem(id: "old", title: "较旧任务", status: .interrupted, updatedAt: now.addingTimeInterval(-10)),
            CodexTaskItem(id: "last", title: "最旧任务", status: .completed, updatedAt: now.addingTimeInterval(-30))
        ]
        expect(CodexTaskItem.visible(sample).map(\.id) == ["run", "done"], "running first, recent ended next, max two")

        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let rollout = home.appendingPathComponent("sessions/task.jsonl")
        try event("task_started").write(to: rollout, atomically: true, encoding: .utf8)
        var db: OpaquePointer?
        guard sqlite3_open(home.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK else { fatalError("fixture DB") }
        let sql = """
        CREATE TABLE threads(id TEXT, name TEXT, title TEXT, rollout_path TEXT, updated_at INTEGER, source TEXT, archived INTEGER);
        INSERT INTO threads VALUES('task', '简短任务名', 'long original prompt', '\(rollout.path)', \(Int(now.timeIntervalSince1970)), 'vscode', 0);
        INSERT INTO threads VALUES('archived', 'hidden', '', '\(rollout.path)', \(Int(now.timeIntervalSince1970)), 'vscode', 1);
        INSERT INTO threads VALUES('agent', 'hidden', '', '\(rollout.path)', \(Int(now.timeIntervalSince1970)), '{"subagent":{}}', 0);
        INSERT INTO threads VALUES('outside', 'hidden', '', '/tmp/outside.jsonl', \(Int(now.timeIntervalSince1970)), 'vscode', 0);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { fatalError("fixture schema") }
        sqlite3_close(db)
        let reader = CodexTaskReader(home: home)
        var items = try reader.read(now: now)
        expect(items.count == 1 && items[0].title == "简短任务名", "uses task name and excludes archives, subagents, outside paths")
        expect(items.first?.status == .running, "reader sees a live task")
        expect(try reader.read(now: now).first?.status == .running, "unchanged cached log remains running")
        try (event("task_started") + event("task_complete")).write(to: rollout, atomically: true, encoding: .utf8)
        items = try reader.read(now: now)
        expect(items.first?.status == .completed, "changed log invalidates cache and shows completion")
        try event("task_started", turn: "b").write(to: rollout, atomically: true, encoding: .utf8)
        expect(try reader.read(now: now.addingTimeInterval(3600)).first?.status == .unknown, "stale unfinished task is unknown")
        try FileManager.default.removeItem(at: rollout)
        expect(try reader.read(now: now).first?.status == .unknown, "missing rollout does not reuse a stale running state")
        print(failures == 0 ? "ALL TASK TESTS PASS" : "\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
