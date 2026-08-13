import Foundation
import SQLite3

/// 通知センターのデータベースを読み取り専用で開いて中身を取る。
///
/// 書き込みは一切しない。Apple が公開している仕組みではないので、
/// 構造が変わって読めなくなることを前提に、失敗は握り潰さず理由を返す。
enum Store {

    enum Failure: Error, CustomStringConvertible {
        case noPermission
        case notFound
        case openFailed(String)
        case queryFailed(String)

        var description: String {
            switch self {
            case .noPermission:
                return "通知センターのデータベースを読む権限がありません。フルディスクアクセスを許可してください。"
            case .notFound:
                return "通知センターのデータベースが見つかりません。OS の更新で場所が変わった可能性があります。"
            case .openFailed(let m):
                return "データベースを開けませんでした: \(m)"
            case .queryFailed(let m):
                return "データベースを読めませんでした: \(m)"
            }
        }
    }

    /// 権限とファイルの有無を先に確かめる。無い理由を区別したいので open 任せにしない
    static func check() -> Failure? {
        let path = Paths.notificationDB.path
        if !FileManager.default.fileExists(atPath: path) {
            // 権限が無いと存在確認そのものが false になるため、親をたどって理由を分ける
            let parent = Paths.notificationDB.deletingLastPathComponent().path
            if !FileManager.default.isReadableFile(atPath: parent) { return .noPermission }
            return .notFound
        }
        if !FileManager.default.isReadableFile(atPath: path) { return .noPermission }
        return nil
    }

    static func recent(limit: Int = 200) throws -> [NonjaNotification] {
        if let failure = check() { throw failure }

        var db: OpaquePointer?
        // WAL に未反映の書き込みがあるので immutable では読まない。mode=ro で開く
        let uri = "file:\(Paths.notificationDB.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "不明"
            sqlite3_close(db)
            throw Failure.openFailed(message)
        }
        defer { sqlite3_close(db) }

        let sql = """
            select r.uuid, r.data, r.delivered_date, a.identifier
            from record r left join app a on a.app_id = r.app_id
            where r.delivered_date is not null
            order by r.delivered_date desc limit ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw Failure.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var out: [NonjaNotification] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let payload = blob(stmt, 1) else { continue }
            let fields = parse(payload: payload)
            // uuid は plist 側にも入っているが、列のほうが確実
            let uuid = blob(stmt, 0).map(uuidString) ?? fields.uuid
            let bundleID = text(stmt, 3) ?? fields.app
            guard let uuid, let bundleID else { continue }

            let seconds = sqlite3_column_double(stmt, 2) + Paths.appleEpochOffset
            out.append(NonjaNotification(
                uuid: uuid,
                bundleID: bundleID,
                title: fields.title,
                subtitle: fields.subtitle,
                body: fields.body,
                deliveredAt: Date(timeIntervalSince1970: seconds)))
        }
        return out
    }

    // MARK: - 列の取り出し

    private static func blob(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private static func text(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        let s = String(cString: c)
        return s.isEmpty ? nil : s
    }

    /// 16 バイトの生の UUID を文字列にする。通知センター側の AXIdentifier は大文字
    private static func uuidString(_ data: Data) -> String? {
        guard data.count == 16 else { return nil }
        let bytes = [UInt8](data)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15])).uuidString
    }

    // MARK: - 本体のバイナリ plist

    private struct Fields {
        var app: String?
        var uuid: String?
        var title: String?
        var subtitle: String?
        var body: String?
    }

    /// data 列はバイナリ plist。表示に使うのは req の中の titl / subt / body
    private static func parse(payload: Data) -> Fields {
        var f = Fields()
        guard let root = try? PropertyListSerialization.propertyList(
                from: payload, options: [], format: nil) as? [String: Any] else { return f }

        f.app = root["app"] as? String
        if let raw = root["uuid"] as? Data { f.uuid = uuidString(raw) }

        if let req = root["req"] as? [String: Any] {
            f.title = string(req["titl"])
            f.subtitle = string(req["subt"])
            f.body = string(req["body"])
        }
        return f
    }

    /// 文字列の欄は二通りある。素の文字列と、ローカライズされた `[書式, 解決済み, 引数]` の配列。
    /// KeepingYouAwake は後者で入っていた。解決済みを優先し、無ければ書式を採る
    private static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? nil : s }
        guard let array = value as? [Any] else { return nil }
        for candidate in [array.count > 1 ? array[1] : nil, array.first] {
            if let s = candidate as? String, !s.isEmpty { return s }
        }
        return nil
    }
}
