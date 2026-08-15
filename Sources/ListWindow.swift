import AppKit

/// Return と Delete を拾う表。既定ではどちらも何もしない
final class KeyTableView: NSTableView {
    weak var controller: ListWindowController?

    override func keyDown(with event: NSEvent) {
        if controller?.keyDownInTable(event) == true { return }
        super.keyDown(with: event)
    }
}

/// 選択の帯を角丸にする。左右に余白を取って、窓の縁まで届かせない
final class RoundedRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let area = bounds.insetBy(dx: 8, dy: 2)
        let path = NSBezierPath(roundedRect: area, xRadius: 8, yRadius: 8)
        // 濃く塗ると中の文字が沈む。薄い面に留めて、文字はそのまま読ませる
        NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.28 : 0.14).setFill()
        path.fill()
    }
}

/// 溜まった通知を並べる窓。
///
/// 時系列に混ぜると通知センターと同じで埋もれるので、**アプリごとにまとめる**。
/// 束の並びは、その束の一番新しい通知の時刻で決める。
final class ListWindowController: NSWindowController {

    /// 表に流し込む一行。見出しと中身が混ざる
    private enum Row {
        case header(bundleID: String, app: String)
        case item(NonjaNotification)
    }

    private let table = KeyTableView()
    private let search = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private let state: State

    private var inbox: [NonjaNotification] = []
    private var rows: [Row] = []
    /// 折りたたんだ束。数が多いアプリを畳んで、他を見やすくする
    private var collapsed: Set<String> = []
    /// 中身が変わったらメニューバーの数も直したい
    var onChange: (() -> Void)?
    /// 設定を開く。右クリックの menu だけだと見つけられない
    var onOpenSettings: (() -> Void)?

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    /// メニューバーに出す数。未読だけ数える
    var unreadCount: Int { inbox.count }

    init(state: State) {
        self.state = state
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Nonja"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let window, let content = window.contentView else { return }

        // 背景は下が透けるぼかし。メニューバーから出す小さな窓に合う
        let backdrop = NSVisualEffectView()
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: content.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        search.placeholderString = "絞り込む"
        search.target = self
        search.action = #selector(searchChanged)
        search.sendsSearchStringImmediately = true
        search.translatesAutoresizingMaskIntoConstraints = false

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 3
        status.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        // 角丸の選択を自分で描くので、標準の差し込み表示は使わない
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.controller = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // 最後の行が状態表示に貼り付かないよう、下に余白を持たせる
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape",
                                           accessibilityDescription: "設定") ?? NSImage(),
                            target: self, action: #selector(openSettings))
        gear.isBordered = false
        gear.bezelStyle = .inline
        gear.contentTintColor = .secondaryLabelColor
        gear.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(search)
        content.addSubview(gear)
        content.addSubview(scroll)
        content.addSubview(status)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 38),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            search.trailingAnchor.constraint(equalTo: gear.leadingAnchor, constant: -8),
            gear.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            gear.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            gear.widthAnchor.constraint(equalToConstant: 22),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
    }

    // MARK: - 読み込み

    @discardableResult
    func reload() -> Int {
        var failure: String?
        do {
            inbox = Engine.apply(try Store.recent(limit: 500), state: state).inbox
        } catch {
            inbox = []
            failure = "\(error)"
        }
        rebuildRows()
        updateStatus(error: failure)
        return unreadCount
    }

    private func rebuildRows() {
        let needle = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        func hit(_ app: String, _ text: String) -> Bool {
            needle.isEmpty || app.lowercased().contains(needle) || text.lowercased().contains(needle)
        }

        rows = []
        let visible = inbox.filter { hit($0.appName, $0.oneLine) }
        // アプリごとにまとめ、束の並びはその束の最新の時刻で決める
        let groups = Dictionary(grouping: visible, by: \.bundleID)
        let ordered = groups.sorted {
            ($0.value.first?.deliveredAt ?? .distantPast) > ($1.value.first?.deliveredAt ?? .distantPast)
        }
        for (bundleID, items) in ordered {
            rows.append(.header(bundleID: bundleID, app: items[0].appName))
            if collapsed.contains(bundleID) { continue }
            rows.append(contentsOf: items.map { Row.item($0) })
        }
        table.reloadData()
        focusTable()
        // 組み直したら必ず先頭に戻す。前の位置に留まると、どこを見ているか分からなくなる
        if !rows.isEmpty { table.scrollRowToVisible(0) }
    }

    /// 開いた直後は何も選ばない。
    /// 先頭を自動で選ぶと、一行だけ青く塗られた理由が伝わらない。
    /// 矢印キーを押した時点で表が自分で先頭を選ぶので、操作は変わらない
    private func focusTable() {
        window?.makeFirstResponder(table)
    }

    private func updateStatus(error: String?) {
        if let error {
            status.stringValue = error
            status.textColor = .systemRed
            return
        }
        // 平常時は何も言わない。一覧を見れば有無は分かる（SPEC.md「件数は出さない」）。
        // 場所だけ残すのは、読めなくなったときの赤字の行き先として要るため
        status.stringValue = ""
        status.textColor = .secondaryLabelColor
    }

    // MARK: - 操作

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func searchChanged() {
        rebuildRows()
    }

    func keyDownInTable(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76:            // Return
            openSelected()
            return true
        case 51, 117:           // Delete
            retireSelected()
            return true
        default:
            return false
        }
    }

    private func item(at row: Int) -> NonjaNotification? {
        guard row >= 0, row < rows.count else { return nil }
        switch rows[row] {
        case .item(let item): return item
        case .header: return nil
        }
    }

    @objc func openSelected() {
        guard let item = item(at: table.selectedRow) else { return }
        state.clicked.insert(item.uuid)
        retire(item)
        state.save()
        Opener.open(item)
        // 開いた時点で用は済んでいる。一覧からは下ろす
        inbox.removeAll { $0.uuid == item.uuid }
        rebuildRows()
        updateStatus(error: nil)
        onChange?()
    }

    private func retire(_ item: NonjaNotification) {
        state.retired.insert(item.uuid)
        state.read.insert(item.uuid)
    }

    /// 手で既読にする。ルールの時間切れと同じ扱いにする
    private func retireSelected() {
        guard let item = item(at: table.selectedRow) else { return }
        retire(item)
        state.save()
        inbox.removeAll { $0.uuid == item.uuid }
        rebuildRows()
        updateStatus(error: nil)
        onChange?()
    }

    // MARK: - 束ごとの操作

    @objc private func toggleGroup(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        if collapsed.contains(bundleID) { collapsed.remove(bundleID) } else { collapsed.insert(bundleID) }
        rebuildRows()
    }

    /// 束ごと既読にする。既読＝一覧から消える。元の通知は通知センターに残る
    @objc private func readGroup(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        for item in inbox where item.bundleID == bundleID { retire(item) }
        state.save()
        inbox.removeAll { $0.bundleID == bundleID }
        rebuildRows()
        updateStatus(error: nil)
        onChange?()
    }

    func markAllRead() {
        for item in inbox { retire(item) }
        state.save()
        inbox = []
        rebuildRows()
        updateStatus(error: nil)
        onChange?()
    }
}

extension ListWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return 28 }
        return 56
    }

    /// 見出しは選ばせない
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let bundleID, let app):
            let label = NSTextField(labelWithString: app.uppercased())
            label.font = .systemFont(ofSize: 10, weight: .bold)
            label.textColor = .tertiaryLabelColor

            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)

            // 束ごとの操作。1件ずつ触らずに済むようにする
            let twist = smallButton(collapsed.contains(bundleID) ? "▸" : "▾",
                                    #selector(toggleGroup(_:)), bundleID)
            let readAll = smallButton("既読", #selector(readGroup(_:)), bundleID)

            let stack = NSStackView(views: [twist, label, spacer, readAll])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 6
            stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 2, right: 16)
            return stack

        case .item(let item):
            return cell(bundleID: item.bundleID, when: item.deliveredAt, text: item.oneLine)

        }
    }

    private func cell(bundleID: String, when: Date, text: String) -> NSView {
        let icon = NSImageView(image: AppNames.icon(for: bundleID))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let body = NSTextField(labelWithString: text.isEmpty ? "（本文なし）" : text)
        body.font = .systemFont(ofSize: 12.5, weight: .medium)
        body.textColor = .labelColor
        body.lineBreakMode = .byTruncatingTail
        body.maximumNumberOfLines = 2

        let time = NSTextField(labelWithString: Self.formatter.string(from: when))
        time.font = .systemFont(ofSize: 10)
        time.textColor = .tertiaryLabelColor

        let lines = NSStackView(views: [body, time])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 3

        let row = NSStackView(views: [icon, lines])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 14)
        return row
    }

    /// 見出しに並べる小さなボタン。文字だけの控えめな見た目にする
    private func smallButton(_ title: String, _ action: Selector, _ bundleID: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.identifier = .init(bundleID)
        return button
    }

    /// 選んだ行を角の丸い面で塗る。既定の四角い帯より落ち着く
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RoundedRowView()
    }
}
