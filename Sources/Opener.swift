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
///
/// **待つ間に主スレッドを止めない。** 通知センターが開くのを待つ間、最長で 2.4 秒かかる。
/// `Thread.sleep` で待っていた頃は、その間メニューバーも一覧も固まっていた。
/// `Task.sleep` で手放して待つ
@MainActor
enum Opener {

    /// 前の操作が終わるまで次を始めない。
    /// どちらも時計を押して通知センターを開け閉めするので、重なると開閉が噛み合わず開いたまま残る
    private static var last: Task<Void, Never>?

    /// 操作を順番待ちに並べる。呼んだ側は待たずに戻ってよい
    private static func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = last
        last = Task {
            await previous?.value
            await work()
        }
    }

    /// 開く操作を並べて、すぐ戻る。一覧のクリックから呼ぶ
    static func openInBackground(_ item: NonjaNotification) {
        enqueue { await open(item) }
    }

    /// 束を消す操作を並べて、すぐ戻る。「すべて既読」から呼ぶ
    static func dismissGroupInBackground(anyOf uuids: [String]) {
        enqueue { await dismissGroup(anyOf: uuids) }
    }

    static func open(_ item: NonjaNotification) async {
        nonjaLog.info(
            "開きます uuid=\(item.uuid, privacy: .public) app=\(item.bundleID, privacy: .public) ax=\(AXIsProcessTrusted(), privacy: .public)"
        )
        if await press(uuid: item.uuid) {
            nonjaLog.info("通知センター経由で押しました")
            return
        }
        nonjaLog.info("見つからないのでアプリを起動します")
        launch(bundleID: item.bundleID)
    }

    /// 通知センターを開いて該当要素を押す。見つからなければ false
    static func press(uuid: String) async -> Bool {
        nonjaLog.info("press 開始 uuid=\(uuid, privacy: .public) ax=\(AXIsProcessTrusted(), privacy: .public)")
        guard AXIsProcessTrusted() else {
            nonjaLog.error("アクセシビリティの許可がありません")
            return false
        }
        guard
            let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui"
            ).first
        else { return false }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        openNotificationCenter()
        // **押せても閉じる。** 押した側の枝で閉じ忘れていて、遷移のたびに
        // 通知センターが開きっぱなしになっていた。一瞬の明滅では済んでいなかった
        defer { closeNotificationCenter() }

        // 開くまでに間があるので少し待って探す
        for _ in 0..<40 {
            if let target = find(uuid: uuid, in: axApp) {
                AXUIElementPerformAction(target, kAXPressAction as CFString)
                // 押した直後に閉じにいくと早すぎて効かない。
                // 表示が動いている最中の操作は飲み込まれ、開いたまま残る
                await pause(0.4)
                return true
            }
            await pause(0.05)
        }
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
    static func dismissGroup(anyOf uuids: [String]) async -> Bool {
        guard !uuids.isEmpty, AXIsProcessTrusted() else { return false }
        guard
            let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui"
            ).first
        else { return false }

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
            await pause(0.05)
        }
        nonjaLog.info("通知センターに束が見つかりませんでした")
        return false
    }

    /// 主スレッドを止めずに待つ。取り消されても待つのをやめるだけで、続きはそのまま進める
    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// 束を消す操作。束ねられているときは「すべて消去」、1件だけのときは「閉じる」になる。
    /// どちらも**そのアプリの通知が消える**という意味では同じ
    private static func clearAction(of element: AXUIElement) -> String? {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
            let list = names as? [String]
        else { return nil }
        return clearActionName(in: list)
    }

    /// 消す操作の名前を選ぶ。
    ///
    /// **この操作には言語によらない識別子がない。** 通知センターが足している独自の操作で、
    /// 名前は `Name:すべて消去\nTarget:…` のように表示言語の文字列そのものになる。
    /// だから日本語と英語の両方を並べて当てる。ほかの言語の macOS では見つからず、
    /// 「すべて既読」は Nonja の中だけで既読になる（通知センター側には残る）。
    /// 束ねられているときは「閉じる」より「すべて消去」を先に選ぶ
    nonisolated static func clearActionName(in names: [String]) -> String? {
        func has(_ words: [String]) -> String? {
            names.first { name in words.contains { name.localizedCaseInsensitiveContains($0) } }
        }
        return has(["すべて消去", "Clear All"]) ?? has(["閉じる", "Close"])
    }

    private static func find(uuid: String, in root: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 12 { return nil }
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(root, kAXIdentifierAttribute as CFString, &value) == .success,
            let id = value as? String, id.caseInsensitiveCompare(uuid) == .orderedSame
        {
            return root
        }
        var kids: AnyObject?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &kids) == .success,
            let children = kids as? [AXUIElement]
        else { return nil }
        for child in children {
            if let hit = find(uuid: uuid, in: child, depth: depth + 1) { return hit }
        }
        return nil
    }

    /// メニューバーの時計を押すと通知センターが開く。専用の API は公開されていない
    private static func openNotificationCenter() {
        run(clickClockScript)
    }

    /// 閉じるのも時計を押す。
    ///
    /// **Escape では閉じない。** 押した直後は前面が元アプリへ移っているので、
    /// Escape はそちらへ流れる。時計はどこが前面でも同じように効く
    private static func closeNotificationCenter() {
        run(clickClockScript)
    }

    /// 時計は **AXIdentifier（`com.apple.menuextra.clock`）で探す。** 説明文の「時計」は
    /// 表示言語で変わり、英語の macOS では "Clock" になって見つからない。
    /// 識別子を持たない項目もあり、`whose` で絞ると最初のそれで失敗するので一つずつ当てる。
    /// 識別子で見つからない版に備えて、日本語と英語の説明文でも探す
    private static let clickClockScript = """
        tell application "System Events" to tell process "ControlCenter"
            repeat with m in (every menu bar item of menu bar 1)
                try
                    if value of attribute "AXIdentifier" of m is "com.apple.menuextra.clock" then
                        click m
                        return
                    end if
                end try
            end repeat
            click (first menu bar item of menu bar 1 whose description is "時計" or description is "Clock")
        end tell
        """

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
