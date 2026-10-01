import Foundation

enum Paths {
    /// 通知センターの実体。macOS 26.5.2 で確認した場所。
    /// `/var/folders/…/0/com.apple.notificationcenter/db2/` にも同名の構造があるが、
    /// そちらは空でありこちらが本体（SPEC.md「検討して捨てた経路」）
    ///
    /// **確かめたのは macOS 26 だけ。** ほかの版で場所が違っても、推測で候補を足さない。
    /// 違う場所を読みにいくと、空や別物を本物と取り違えるおそれがある。見つからなければそう伝える
    static var notificationDB: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    /// 置き場所を確かめた macOS。見つからないときの案内に出す
    static let verifiedOS = "macOS 26"

    /// 見つからなかったときに知らせてもらう先
    static let issues = "github.com/piro0919/nonja/issues"

    /// Apple 基準時（2001-01-01）から Unix 時間への差
    static let appleEpochOffset: TimeInterval = 978_307_200
}
