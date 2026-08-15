import AppKit

/// 設定画面。**今はログイン時の起動だけ**（SPEC.md「設定画面に出すもの」）。
///
/// 振り分けルールと確認の基準は仕組みとしては生きていて、`state.json` に書けば効く。
/// 画面から編集する口だけを外している。
final class SettingsWindowController: NSWindowController {

    private let login = NSButton()

    init() {
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

        content.addSubview(login)
        NSLayoutConstraint.activate([
            login.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            login.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            login.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            login.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        fitToContent()
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
    }

    @objc private func loginChanged() {
        let wanted = login.state == .on
        if !Login.setEnabled(wanted) {
            // 失敗したら見た目だけ先に進めない。実際の状態に戻す
            login.state = Login.isEnabled ? .on : .off
        }
    }
}
