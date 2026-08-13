import Foundation

enum Paths {
    /// 通知センターの実体。macOS 26.5.2 で確認した場所。
    /// `/var/folders/…/0/com.apple.notificationcenter/db2/` にも同名の構造があるが、
    /// そちらは空でありこちらが本体（SPEC.md「検討して捨てた経路」）
    static var notificationDB: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    /// Apple 基準時（2001-01-01）から Unix 時間への差
    static let appleEpochOffset: TimeInterval = 978_307_200
}
