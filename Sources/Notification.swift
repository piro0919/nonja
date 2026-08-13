import AppKit
import Foundation

/// 通知センターから読み出した一件。
struct NonjaNotification {
    /// 通知センター上の要素の AXIdentifier と一致する。クリック時の遷移に使う
    let uuid: String
    /// 送信元のバンドル識別子
    let bundleID: String
    let title: String?
    let subtitle: String?
    let body: String?
    let deliveredAt: Date

    /// 一覧に出す送信元の名前。バンドル識別子からアプリ名を引けなければ識別子のまま出す
    var appName: String {
        AppNames.displayName(for: bundleID)
    }

    var oneLine: String {
        [title, subtitle, body]
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " / ")
    }
}

enum AppNames {
    private static var cache: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    /// 送信元アプリのアイコン。一覧の左に出すと、どこから来たのかが一目で分かる
    static func icon(for bundleID: String) -> NSImage {
        if let hit = icons[bundleID] { return hit }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        icons[bundleID] = image
        return image
    }

    static func displayName(for bundleID: String) -> String {
        if let hit = cache[bundleID] { return hit }
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        }
        cache[bundleID] = name
        return name
    }
}
