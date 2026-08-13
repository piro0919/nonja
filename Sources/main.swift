import AppKit

@main
enum Nonja {
    static func main() {
        // 画面を出さずに読み取りだけ確かめる口。権限や構造が壊れたときの切り分けに使う
        // ログイン項目の登録は失敗の理由が見えにくいので、切り離して試せるようにする
        if let index = CommandLine.arguments.firstIndex(of: "--login"),
           index + 1 < CommandLine.arguments.count {
            let wanted = CommandLine.arguments[index + 1] == "on"
            let ok = Login.setEnabled(wanted)
            print("登録\(wanted ? "" : "解除")：\(ok ? "成功" : "失敗") ・ 現在: \(Login.isEnabled ? "有効" : "無効")")
            exit(ok ? 0 : 1)
        }
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }
        if CommandLine.arguments.contains("--dump") {
            dump()
            return
        }
        // 遷移だけを切り離して試す口。押せたかどうかを返す
        if let index = CommandLine.arguments.firstIndex(of: "--press"),
           index + 1 < CommandLine.arguments.count {
            press(uuid: CommandLine.arguments[index + 1])
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static func press(uuid: String) {
        guard AXIsProcessTrusted() else {
            print("アクセシビリティの許可がありません")
            exit(1)
        }
        if Opener.press(uuid: uuid) {
            print("押せました: \(uuid)")
        } else {
            print("通知センターに見つかりませんでした: \(uuid)")
            exit(1)
        }
    }

    private static func dump() {
        do {
            let items = try Store.recent(limit: 20)
            print("読めました: \(items.count) 件")
            for item in items {
                print("  \(item.deliveredAt)  \(item.bundleID)  \(item.oneLine)")
                print("    uuid=\(item.uuid)")
            }
        } catch {
            print("読めませんでした: \(error)")
            exit(1)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var listWindow: ListWindowController!
    private var rulesWindow: RulesWindowController!
    private let state = State.load()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        listWindow = ListWindowController(state: state)
        rulesWindow = RulesWindowController(state: state)
        listWindow.onOpenSettings = { [weak self] in self?.showSettings() }
        // 窓の中で片付けたら、メニューバーの数も合わせる
        listWindow.onChange = { [weak self] in self?.showPresence() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Mark.menuBarImage(hasItems: false)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        refresh()
        // 通知の到着はデータベースへの反映まで約5秒遅れる。細かく見に行っても意味が無い
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func toggle() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        guard let window = listWindow.window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            listWindow.reload()
            placeUnderStatusItem(window)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// メニューバーの印の真下に出す。画面の端からははみ出させない
    private func placeUnderStatusItem(_ window: NSWindow) {
        guard let button = statusItem.button, let barWindow = button.window,
              let screen = barWindow.screen ?? NSScreen.main else {
            window.center()
            return
        }
        let anchor = barWindow.frame
        var x = anchor.midX - window.frame.width / 2
        let margin: CGFloat = 8
        x = min(max(x, screen.visibleFrame.minX + margin),
                screen.visibleFrame.maxX - window.frame.width - margin)
        let y = anchor.minY - window.frame.height - 6
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "今すぐ読み直す", action: #selector(refreshNow), keyEquivalent: "r")
            .target = self
        menu.addItem(withTitle: "すべて既読にする", action: #selector(markAllRead), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "設定…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "通知のバナーを止める…", action: #selector(openNotificationSettings),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Nonja を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() { refresh() }

    @objc private func markAllRead() {
        listWindow.markAllRead()
        refresh()
    }

    /// バナーを止めるのは OS 側の設定。ここから直接その画面を開く
    @objc private func openNotificationSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func showSettings() {
        rulesWindow.refresh()
        // 一覧を出している画面に出す。center() だと別のディスプレイに飛ぶことがある
        if let settings = rulesWindow.window,
           let screen = listWindow.window?.screen ?? NSScreen.main {
            let area = screen.visibleFrame
            settings.setFrameOrigin(NSPoint(
                x: area.midX - settings.frame.width / 2,
                y: area.midY - settings.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        rulesWindow.showWindow(nil)
    }

    private func refresh() {
        listWindow.reload()
        showPresence()
    }

    /// 件数は出さない。溜まっているかどうかだけを、印の塗りと輪郭で示す
    private func showPresence() {
        statusItem.button?.image = Mark.menuBarImage(hasItems: listWindow.unreadCount > 0)
    }
}
