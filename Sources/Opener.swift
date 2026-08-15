import AppKit
import ApplicationServices
import OSLog

/// 何が起きたかを後から追えるようにする。
/// `log show --predicate 'subsystem == "io.kkweb.nonja"' --last 10m --info` で読める
let nonjaLog = Logger(subsystem: "io.kkweb.nonja", category: "opener")

/// 通知をクリックしたときに元アプリへ飛ばす。
///
/// 本物の通知を通知センター経由で押す。`AXPress` は利用者のクリックそのものなので、
/// 遷移は OS が本来やる動きになる（SPEC.md「元アプリへの遷移」）。
/// すでに通知センターから消えている通知は押せないので、そのときはアプリを起動するだけに留める。
enum Opener {

    static func open(_ item: NonjaNotification) {
        nonjaLog.info("開きます uuid=\(item.uuid, privacy: .public) app=\(item.bundleID, privacy: .public) ax=\(AXIsProcessTrusted(), privacy: .public)")
        if press(uuid: item.uuid) {
            nonjaLog.info("通知センター経由で押しました")
            return
        }
        nonjaLog.info("見つからないのでアプリを起動します")
        launch(bundleID: item.bundleID)
    }

    /// 通知センターを開いて該当要素を押す。見つからなければ false
    static func press(uuid: String) -> Bool {
        nonjaLog.info("press 開始 uuid=\(uuid, privacy: .public) ax=\(AXIsProcessTrusted(), privacy: .public)")
        guard AXIsProcessTrusted() else {
            nonjaLog.error("アクセシビリティの許可がありません")
            return false
        }
        guard let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui").first else { return false }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        openNotificationCenter()

        // 開くまでに間があるので少し待って探す
        for _ in 0..<40 {
            if let target = find(uuid: uuid, in: axApp) {
                AXUIElementPerformAction(target, kAXPressAction as CFString)
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        closeNotificationCenter()
        return false
    }

    /// そのアプリの通知を通知センターからも消す。**macOS 自身に消させる**
    /// （SPEC.md「通知センター側も消す」）。
    ///
    /// **データベースは書き換えない。** 一度やってみたところ、macOS に丸ごと壊れていると
    /// 判定されて捨てられ、通知の履歴を失った。消すのは必ず OS の操作を通す。
    ///
    /// **アプリ単位でしか消せない。** macOS は同じアプリの通知を束ねて一つの要素として見せ、
    /// 束の中身は開いても個別に現れない。束に消す操作を送ると、そのアプリ全部が消える。
    /// だから「すべて既読」からしか呼ばない。
    ///
    /// 束の識別子は一番新しい通知のものになる。どれが先頭か分からないので、
    /// 渡された uuid を順に当てて、最初に見つかったものを使う
    @discardableResult
    static func dismissGroup(anyOf uuids: [String]) -> Bool {
        guard !uuids.isEmpty, AXIsProcessTrusted() else { return false }
        guard let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui").first else { return false }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        openNotificationCenter()
        defer { closeNotificationCenter() }

        // 開くまでに間があるので待つ
        for _ in 0..<40 {
            for uuid in uuids {
                guard let target = find(uuid: uuid, in: axApp) else { continue }
                guard let action = clearAction(of: target) else { continue }
                let ok = AXUIElementPerformAction(target, action as CFString) == .success
                nonjaLog.info("通知センターの束を消しました: \(ok, privacy: .public)")
                return ok
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        nonjaLog.info("通知センターに束が見つかりませんでした")
        return false
    }

    /// 束を消す操作。束ねられているときは「すべて消去」、1件だけのときは「閉じる」になる。
    /// どちらも**そのアプリの通知が消える**という意味では同じ
    private static func clearAction(of element: AXUIElement) -> String? {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String] else { return nil }
        return list.first { $0.contains("すべて消去") }
            ?? list.first { $0.contains("閉じる") || $0.lowercased().contains("close") }
    }

    private static func find(uuid: String, in root: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 12 { return nil }
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(root, kAXIdentifierAttribute as CFString, &value) == .success,
           let id = value as? String, id.caseInsensitiveCompare(uuid) == .orderedSame {
            return root
        }
        var kids: AnyObject?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return nil }
        for child in children {
            if let hit = find(uuid: uuid, in: child, depth: depth + 1) { return hit }
        }
        return nil
    }

    /// メニューバーの時計を押すと通知センターが開く。専用の API は公開されていない
    private static func openNotificationCenter() {
        run("""
            tell application "System Events" to tell process "ControlCenter" \
            to click (first menu bar item of menu bar 1 whose description is "時計")
            """)
    }

    private static func closeNotificationCenter() {
        run("tell application \"System Events\" to key code 53")
    }

    private static func run(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    private static func launch(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
