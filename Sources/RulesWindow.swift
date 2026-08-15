import AppKit

/// 中身を上端から並べるための枠。
///
/// `NSClipView` は既定で反転していないので原点が左下にあり、中身が枠より短いと下に沈む。
/// 反転させると上端が原点になり、短いうちは上から並び、長くなればそのまま伸びる。
final class TopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// ルールの編集画面。アプリ単位で、扱いと保持時間と時間切れの行き先を決める。
/// 正規表現はまだ入れない（SPEC.md「振り分けルール」）。
final class RulesWindowController: NSWindowController {

    private let state: State
    private let stack = NSStackView()
    private let basis = NSPopUpButton()
    private let login = NSButton()
    /// ルールを足すときに選べるアプリ。通知が来たことのあるものだけを出す
    private var knownApps: [String] = []

    init(state: State) {
        self.state = state
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Nonja の設定"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }

        let basisLabel = NSTextField(labelWithString: "確認したとみなす基準")
        basisLabel.font = .systemFont(ofSize: 12, weight: .medium)
        for option in ConfirmBasis.allCases { basis.addItem(withTitle: option.label) }
        basis.target = self
        basis.action = #selector(basisChanged)

        let note = NSTextField(wrappingLabelWithString:
            "「一覧に出たら確認済み」にすると、窓を一度開いた通知は消えなくなります。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        // 位置を制約で決めるものは、必ずこれを切る。切り忘れると自動生成の制約と
        // ぶつかって、そこを起点に画面全体が崩れる
        note.translatesAutoresizingMaskIntoConstraints = false

        let add = NSButton(title: "ルールを追加", target: self, action: #selector(addRule))

        login.title = "ログイン時に起動する"
        login.setButtonType(.switch)
        // これを切らないと自動生成の制約とぶつかり、画面全体が崩れる
        login.translatesAutoresizingMaskIntoConstraints = false
        login.target = self
        login.action = #selector(loginChanged)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        // 既定の NSClipView は原点が左下にあるため、中身が枠より短いと下端に沈み、
        // 上に空白が開く。上から並べるには原点のほうを直す（SPEC.md「画面を組むときの落とし穴」）
        scroll.contentView = TopAlignedClipView()
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // 高さを決めない空ビューを挟むと縦に伸び、下の並びを丸ごと押し下げる。
        // 高さを与えて、横にだけ効く余白にする
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let top = NSStackView(views: [basisLabel, basis, spacer, add])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8
        top.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(top)
        content.addSubview(note)
        content.addSubview(login)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            top.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            note.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 6),
            note.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            note.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            login.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 12),
            login.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: login.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            // 枠を反転させただけでは足りない。中身の上端を枠の上端に留めておかないと、
            // 中身が短い間は下に沈んだままになる。下端は縛らない。伸びる先を塞ぐことになる
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
    }

    func refresh() {
        basis.selectItem(at: ConfirmBasis.allCases.firstIndex(of: state.settings.confirmBasis) ?? 0)
        login.state = Login.isEnabled ? .on : .off
        knownApps = (try? Store.recent(limit: 500))
            .map { Array(Set($0.map(\.bundleID))).sorted() } ?? []

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for rule in state.settings.effectiveRules {
            stack.addArrangedSubview(row(for: rule))
        }
    }

    /// 1行ぶんの編集欄。`bundleID` が nil の行は既定なので消せない
    private func row(for rule: Rule) -> NSView {
        let isFallback = rule.bundleID == nil
        let name = NSTextField(labelWithString:
            isFallback ? "その他すべて" : AppNames.displayName(for: rule.bundleID!))
        name.font = .systemFont(ofSize: 12, weight: isFallback ? .semibold : .regular)
        name.lineBreakMode = .byTruncatingTail
        name.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let action = NSPopUpButton()
        for a in Rule.Action.allCases { action.addItem(withTitle: a.label) }
        action.selectItem(at: Rule.Action.allCases.firstIndex(of: rule.action) ?? 0)
        action.target = self
        action.action = #selector(changed(_:))
        action.identifier = .init(rule.bundleID ?? "")

        let minutes = NSTextField(string: "\(rule.holdMinutes)")
        minutes.widthAnchor.constraint(equalToConstant: 54).isActive = true
        minutes.alignment = .right
        minutes.target = self
        minutes.action = #selector(changed(_:))
        minutes.identifier = .init(rule.bundleID ?? "")
        minutes.isEnabled = rule.action == .hold

        let unit = NSTextField(labelWithString: "分で片付ける")
        unit.font = .systemFont(ofSize: 11)
        unit.textColor = .secondaryLabelColor

        var views: [NSView] = [name, action, minutes, unit]
        if !isFallback {
            let remove = NSButton(title: "削除", target: self, action: #selector(removeRule(_:)))
            remove.identifier = .init(rule.bundleID!)
            remove.bezelStyle = .rounded
            views.append(remove)
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 6
        return row
    }

    // MARK: - 編集

    @objc private func loginChanged() {
        let wanted = login.state == .on
        if !Login.setEnabled(wanted) {
            // 失敗したら見た目だけ先に進めない。実際の状態に戻す
            login.state = Login.isEnabled ? .on : .off
        }
    }

    @objc private func basisChanged() {
        state.settings.confirmBasis = ConfirmBasis.allCases[basis.indexOfSelectedItem]
        state.save()
    }

    /// 行の中の値が変わったら、その行ごと読み直して保存する
    @objc private func changed(_ sender: NSControl) {
        guard let row = sender.superview as? NSStackView else { return }
        let bundleID = sender.identifier?.rawValue ?? ""
        let controls = row.arrangedSubviews

        guard let action = controls.compactMap({ $0 as? NSPopUpButton }).first,
              let minutes = controls.compactMap({ $0 as? NSTextField })
                .first(where: { $0.isEditable }) else { return }

        let updated = Rule(
            bundleID: bundleID.isEmpty ? nil : bundleID,
            action: Rule.Action.allCases[action.indexOfSelectedItem],
            holdMinutes: max(1, Int(minutes.stringValue) ?? 60))

        state.settings.rules.removeAll { $0.bundleID == updated.bundleID }
        state.settings.rules.append(updated)
        state.save()
        refresh()
    }

    @objc private func removeRule(_ sender: NSButton) {
        let bundleID = sender.identifier?.rawValue ?? ""
        state.settings.rules.removeAll { $0.bundleID == bundleID }
        state.save()
        refresh()
    }

    @objc private func addRule() {
        let existing = Set(state.settings.rules.compactMap(\.bundleID))
        let candidates = knownApps.filter { !existing.contains($0) }
        guard !candidates.isEmpty else { return }

        let menu = NSMenu()
        for bundleID in candidates {
            let item = NSMenuItem(title: AppNames.displayName(for: bundleID),
                                  action: #selector(pickApp(_:)), keyEquivalent: "")
            item.target = self
            item.identifier = .init(bundleID)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func pickApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        state.settings.rules.append(
            Rule(bundleID: bundleID, action: .hold, holdMinutes: 60))
        state.save()
        refresh()
    }
}
