import Foundation
import SQLite3

/// 通知センター側からも通知を消す経路。実機で1件消せることを確認済み
/// （SPEC.md「通知センター側も消す」）。
///
/// 普段の Nonja はデータベースを読み取り専用でしか開かない（`Store`）。ここだけが例外で、
/// 唯一の書き込みになる。今は `--forget <uuid>` でしか動かない。
///
/// 消すには二箇所を直す必要がある。
///
/// 1. `record` の該当行
/// 2. そのアプリの `delivered` の `list`。**通知1件につき1行ではなく、アプリごとに1行**で、
///    16 バイトの UUID を隙間なく並べた塊が入っている。ここから該当の 16 バイトを抜く
///
/// どちらも書式が公開されていない。**書き損じるとそのアプリの通知一覧が壊れる。**
/// 書き込む前に必ず控えを取る。
enum Forget {

    enum Failure: Error, CustomStringConvertible {
        case openFailed(String)
        case notFound
        case backupFailed(String)
        case writeFailed(String)

        var description: String {
            switch self {
            case .openFailed(let m): return "データベースを書き込みで開けませんでした: \(m)"
            case .notFound: return "その通知はデータベースにありません。"
            case .backupFailed(let m): return "控えを作れませんでした: \(m)"
            case .writeFailed(let m): return "書き込みに失敗しました: \(m)"
            }
        }
    }

    /// 書き込む前に控える。戻す先が無い状態で触らない
    private static func backup() throws {
        let source = Paths.notificationDB
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent("db.nonja-backup")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw Failure.backupFailed("\(error)")
        }
    }

    /// 指定した通知を通知センターから消す。消した件数を返す
    @discardableResult
    static func forget(uuid target: UUID) throws -> Int {
        try backup()

        var db: OpaquePointer?
        guard sqlite3_open_v2(Paths.notificationDB.path, &db,
                              SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "不明"
            sqlite3_close(db)
            throw Failure.openFailed(message)
        }
        defer { sqlite3_close(db) }

        var bytes = withUnsafeBytes(of: target.uuid) { Data($0) }

        // どのアプリの通知かを先に押さえる。record を消した後では引けなくなる
        var appID: Int64?
        var find: OpaquePointer?
        if sqlite3_prepare_v2(db, "select app_id from record where uuid = ?", -1, &find, nil) == SQLITE_OK {
            bytes.withUnsafeBytes { raw in
                _ = sqlite3_bind_blob(find, 1, raw.baseAddress, Int32(raw.count), nil)
            }
            if sqlite3_step(find) == SQLITE_ROW { appID = sqlite3_column_int64(find, 0) }
        }
        sqlite3_finalize(find)
        guard let appID else { throw Failure.notFound }

        try execute(db, "begin immediate")
        do {
            try deleteRecord(db, uuid: &bytes)
            try trimDelivered(db, appID: appID, uuid: bytes)
            try execute(db, "commit")
        } catch {
            try? execute(db, "rollback")
            throw error
        }
        return 1
    }

    private static func deleteRecord(_ db: OpaquePointer, uuid bytes: inout Data) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "delete from record where uuid = ?", -1, &statement, nil) == SQLITE_OK else {
            throw Failure.writeFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        bytes.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(statement, 1, raw.baseAddress, Int32(raw.count), nil)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw Failure.writeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// アプリごとの塊から 16 バイトを抜いて書き戻す
    private static func trimDelivered(_ db: OpaquePointer, appID: Int64, uuid bytes: Data) throws {
        var read: OpaquePointer?
        guard sqlite3_prepare_v2(db, "select list from delivered where app_id = ?", -1, &read, nil) == SQLITE_OK else {
            throw Failure.writeFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(read, 1, appID)
        var list = Data()
        if sqlite3_step(read) == SQLITE_ROW, let raw = sqlite3_column_blob(read, 0) {
            list = Data(bytes: raw, count: Int(sqlite3_column_bytes(read, 0)))
        }
        sqlite3_finalize(read)
        guard !list.isEmpty else { return }

        // 16 バイト刻みで並んでいる。刻みに乗らない塊は触らない。
        // 書式が違うということなので、当てずっぽうで書き換えるより何もしない方が安全
        guard list.count % 16 == 0 else { return }
        var trimmed = Data()
        for start in stride(from: 0, to: list.count, by: 16) {
            let slice = list[start..<start + 16]
            if slice.elementsEqual(bytes) { continue }
            trimmed.append(contentsOf: slice)
        }
        guard trimmed.count != list.count else { return }

        var write: OpaquePointer?
        guard sqlite3_prepare_v2(db, "update delivered set list = ? where app_id = ?", -1, &write, nil) == SQLITE_OK else {
            throw Failure.writeFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(write) }
        trimmed.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(write, 1, raw.baseAddress, Int32(raw.count), nil)
        }
        sqlite3_bind_int64(write, 2, appID)
        guard sqlite3_step(write) == SQLITE_DONE else {
            throw Failure.writeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw Failure.writeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// 常駐プロセスに読み直させる。これをしないと画面上の通知は消えない
    static func reload() {
        for name in ["usernoted", "NotificationCenter"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            task.arguments = ["-x", name]
            try? task.run()
            task.waitUntilExit()
        }
    }
}
