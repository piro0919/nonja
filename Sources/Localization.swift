import Foundation

// 表示文字列。
//
// Konechi・Gocci と同じく .lproj は使わず Swift の表に置く。ビルドを自前の shell で組んでいて、
// 文字列だけのために資源の仕組みを足すと build.sh が重くなる。言語は2つしかない。
//
// 言語を選ぶ設定は持たない。設定画面はログイン時の起動だけに絞っている（SPEC.md「設定画面に出すもの」）。
// 既定は英語で、環境の第一言語が日本語のときだけ日本語にする

enum L {
    /// 環境の第一言語が日本語かどうか
    static var isJapanese: Bool {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ja")
    }

    static func t(_ ja: String, _ en: String) -> String {
        isJapanese ? ja : en
    }

    // メニュー
    static var settings: String { t("設定…", "Settings…") }
    static var quit: String { t("Nonja を終了", "Quit Nonja") }

    // 一覧
    static var noNotifications: String { t("通知はありません", "No notifications") }
    static var settingsButton: String { t("設定", "Settings") }
    static var markAllRead: String { t("すべて既読", "Mark All as Read") }
    static var markRead: String { t("既読", "Read") }
    static var noBody: String { t("（本文なし）", "(No text)") }

    // 設定画面
    static var settingsTitle: String { t("Nonja の設定", "Nonja Settings") }
    /// macOS 本体の翻訳表に合わせる。Konechi・Gocci と同じ言葉
    static var launchAtLogin: String { t("ログイン時に起動する", "Launch at Login") }
    static var checkForUpdates: String { t("更新を確認", "Check for Updates") }

    // 振り分けルールと確認の基準。今は画面に出していないが、名前はここで持つ
    static var ruleShow: String { t("すぐ見せる", "Show now") }
    static var ruleHold: String { t("溜める", "Hold") }
    static var ruleMute: String { t("自動で既読", "Mark as read automatically") }
    static var basisDisplayed: String { t("一覧に出たら確認済み", "Seen once listed") }
    static var basisClicked: String { t("クリックしたら確認済み", "Seen once clicked") }

    // 読めなかったとき。一覧の下に赤字で出る
    static var noPermission: String {
        t(
            "通知センターのデータベースを読む権限がありません。フルディスクアクセスを許可してください。",
            "Nonja cannot read the Notification Center database. Allow Full Disk Access for Nonja.")
    }
    static var notFound: String {
        t(
            "通知センターのデータベースが見つかりません。OS の更新で場所が変わった可能性があります。",
            "The Notification Center database was not found. A macOS update may have moved it.")
    }
    static func openFailed(_ reason: String) -> String {
        t("データベースを開けませんでした: \(reason)", "Could not open the database: \(reason)")
    }
    static func queryFailed(_ reason: String) -> String {
        t("データベースを読めませんでした: \(reason)", "Could not read the database: \(reason)")
    }
    static var unknown: String { t("不明", "unknown") }
}
