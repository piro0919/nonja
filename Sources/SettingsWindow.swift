import AppKit

/// 設定画面。**ログイン時の起動と、止めているアプリだけ**（SPEC.md「設定画面に出すもの」）。
///
/// 振り分けルールと確認の基準そのものは `state.json` に書けば効く。
/// 画面から編集する口は持たない。ここに出すのは、一覧の中に戻す場所を作れないものだけ。
final class SettingsWindowController: NSWindowController {

    private let state: State
    private let login = NSButton()
    /// 止めているアプリの並び。空のときは見出しごと出さない
    private let muted = NSStackView()
    private let mutedTitle = NSTextField(labelWithString: "止めているアプリ")

    init(state: State) {
        self.state = state
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Nonja の設定"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }

        login.title = "ログイン時に起動する"
        login.setButtonType(.switch)
        // 位置を制約で決めるものは、必ずこれを切る。切り忘れると自動生成の制約と
        // ぶつかって、そこを起点に画面全体が崩れる
        login.translatesAutoresizingMaskIntoConstraints = false
        login.target = self
        login.action = #selector(loginChanged)

        mutedTitle.font = .systemFont(ofSize: 10, weight: .bold)
        mutedTitle.textColor = .tertiaryLabelColor

        muted.orientation = .vertical
        muted.alignment = .leading
        muted.spacing = 6
        muted.translatesAutoresizingMaskIntoConstraints = false

        let column = NSStackView(views: [login, mutedTitle, muted])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        // 見出しと並びの間は詰める。ひとかたまりに見せる
        column.setCustomSpacing(6, after: mutedTitle)

        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    /// 窓の高さは中身に合わせる。固定すると余りがどこかに出る
    /// （SPEC.md「画面を組むときの落とし穴」）
    private func fitToContent() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        var frame = window.frame
        let height = content.fittingSize.height + (frame.height - content.frame.height)
        // 上辺を動かさずに下辺だけ伸び縮みさせる。原点は左下なので、差のぶん下げる
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }

    func refresh() {
        login.state = Login.isEnabled ? .on : .off

        muted.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let stopped = state.settings.rules
            .filter { $0.action == .mute }
            .compactMap(\.bundleID)
            .sorted()
        for bundleID in stopped { muted.addArrangedSubview(row(for: bundleID)) }
        // 何も止めていなければ、見出しごと畳んで存在しなかったことにする
        mutedTitle.isHidden = stopped.isEmpty
        muted.isHidden = stopped.isEmpty

        fitToContent()
    }

    /// 1行ぶん。名前と、戻すためのボタン
    private func row(for bundleID: String) -> NSView {
        let name = NSTextField(labelWithString: AppNames.displayName(for: bundleID))
        name.font = .systemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingTail
        name.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let restore = NSButton(title: "戻す", target: self, action: #selector(restore(_:)))
        restore.bezelStyle = .rounded
        restore.identifier = .init(bundleID)

        let row = NSStackView(views: [name, restore])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    @objc private func restore(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        state.settings.rules.removeAll { $0.bundleID == bundleID }
        state.save()
        refresh()
        onRestore?()
    }

    /// 戻したら一覧を読み直してもらう
    var onRestore: (() -> Void)?

    @objc private func loginChanged() {
        let wanted = login.state == .on
        if !Login.setEnabled(wanted) {
            // 失敗したら見た目だけ先に進めない。実際の状態に戻す
            login.state = Login.isEnabled ? .on : .off
        }
    }
}
