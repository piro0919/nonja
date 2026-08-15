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
        // 通知センター側からも消す口。唯一の書き込みなので、今は明示的に呼んだときだけ動く
        if let index = CommandLine.arguments.firstIndex(of: "--forget"),
           index + 1 < CommandLine.arguments.count {
            forget(uuid: CommandLine.arguments[index + 1])
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

    /// 通知センター側からも消す。今は画面からは呼ばれない
    private static func forget(uuid: String) {
        guard let target = UUID(uuidString: uuid) else {
            print("uuid の形になっていません: \(uuid)")
            exit(1)
        }
        do {
            try Forget.forget(uuid: target)
            Forget.reload()
            print("消しました: \(uuid)")
            print("控えは db.nonja-backup に置いてあります。戻すときはこれを db に上書きしてください。")
        } catch {
            print("消せませんでした: \(error)")
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
    private var settingsWindow: SettingsWindowController!
    private let state = State.load()
    private var timer: Timer?
    /// 届いたときに印を回している間だけ動く
    private var spinTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        listWindow = ListWindowController(state: state)
        settingsWindow = SettingsWindowController()
        listWindow.onOpenSettings = { [weak self] in self?.showSettings() }
        // 窓の中で片付けたら、メニューバーの数も合わせる
        listWindow.onChange = { [weak self] in self?.showPresence() }
        listWindow.onArrival = { [weak self] in self?.spin() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Mark.menuBarImage(hasItems: false)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        refresh()
        // 更新の確認は起動時に1回だけ。見つかったときだけ画面を出す
        Updater.shared.checkQuietly()
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
        menu.addItem(withTitle: "更新を確認…", action: #selector(checkForUpdates), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Nonja を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() { refresh() }

    @objc private func checkForUpdates() { Updater.shared.checkNow() }

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
        settingsWindow.refresh()
        // 一覧を出している画面に出す。center() だと別のディスプレイに飛ぶことがある
        if let settings = settingsWindow.window,
           let screen = listWindow.window?.screen ?? NSScreen.main {
            let area = screen.visibleFrame
            settings.setFrameOrigin(NSPoint(
                x: area.midX - settings.frame.width / 2,
                y: area.midY - settings.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.showWindow(nil)
    }

    private func refresh() {
        listWindow.reload()
        showPresence()
    }

    /// 件数は出さない。溜まっているかどうかだけを、印の塗りと輪郭で示す
    private func showPresence() {
        guard spinTimer == nil else { return }   // 回している間は上書きしない
        statusItem.button?.image = Mark.menuBarImage(hasItems: listWindow.unreadCount > 0)
    }

    /// 届いたときに印を一回転させる（SPEC.md「届いたら回す」）。
    ///
    /// バナーの代わりではない。**気付かなくても構わない**合図なので、
    /// 音も出さず、割り込まず、0.6 秒で終わる。回している間に次が届いたら、最初からやり直す
    private func spin() {
        nonjaLog.info("届いたので印を回します")
        spinTimer?.invalidate()
        let started = Date()
        // 減速するぶん、等速のときより少し長くしないと最後が駆け足になる
        let duration: TimeInterval = 0.8
        spinTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = Date().timeIntervalSince(started) / duration
            if progress >= 1 {
                timer.invalidate()
                self.spinTimer = nil
                self.showPresence()
                return
            }
            // 等速だと機械が回っているように見える。投げたものは勢いよく回り始めて、
            // 抵抗で緩みながら止まる。三乗で減速させるとその感じになる
            let eased = 1 - pow(1 - progress, 3)
            // 手裏剣は投げた向きに回る。負の角で時計回りになる
            self.statusItem.button?.image = Mark.menuBarImage(
                hasItems: self.listWindow.unreadCount > 0,
                rotation: -360 * eased)
        }
    }
}
