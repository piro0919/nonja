import AppKit

/// Return と Delete を拾う表。既定ではどちらも何もしない
final class KeyTableView: NSTableView {
    weak var controller: ListWindowController?

    override func keyDown(with event: NSEvent) {
        if controller?.keyDownInTable(event) == true { return }
        super.keyDown(with: event)
    }

    /// カーソルの下の行を知るための領域。表に一つだけ置く
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) { controller?.updateHover() }
    override func mouseEntered(with event: NSEvent) { controller?.updateHover() }
    override func mouseExited(with event: NSEvent) { controller?.updateHover() }
}

/// 指を乗せている間だけ、中の部品を見せる行。
///
/// 隠すと幅が動いて落ち着かないので、透明にして場所は取らせたままにする。
/// **出し入れの判断は行では持たない。** 行ごとに追跡領域を置くと、スクロールで
/// 通り過ぎたときに入った通知だけが来て出た通知が来ず、出たままの行が溜まる。
/// 表がカーソルの位置から一行だけ選ぶ（`ListWindowController.updateHover`）
final class HoverRevealView: NSStackView {
    weak var revealed: NSView?
}

/// 押せることをカーソルで伝えるボタン。
///
/// 見出しのアプリ名は文字だけの見た目なので、指の形に変わるかどうかが唯一の手掛かりになる
final class PointingButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
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
    private let status = NSTextField(labelWithString: "")
    /// 測った行の高さ。鍵は uuid と幅
    private var heights: [String: CGFloat] = [:]
    /// 状態表示は平常時に文字を持たない。畳めるよう、関わる制約を持っておく
    private var statusHeight: NSLayoutConstraint!
    private var statusGap: NSLayoutConstraint!
    private var statusBottom: NSLayoutConstraint!
    private let state: State

    private var inbox: [NonjaNotification] = []
    private var rows: [Row] = []
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
        // 行の高さは中身で決める（`heightOfRow`）。固定にすると三行以上の本文が下で切れる。
        // `usesAutomaticRowHeights` は使わない。幅まで中身に決めさせてしまい、行が窓からはみ出す
        table.dataSource = self
        table.delegate = self
        // 一段目のクリックで開く。ダブルクリックは気付ける見た目をしていなかった
        table.target = self
        table.action = #selector(rowClicked)
        table.controller = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // 最後の行を窓の縁に貼り付かせない。状態表示は平常時に畳まれていて、間に何も入らない
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // スクロールしただけではマウスは動かないので通知が来ない。位置を引き直す口を作る
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)

        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape",
                                           accessibilityDescription: "設定") ?? NSImage(),
                            target: self, action: #selector(openSettings))
        gear.isBordered = false
        gear.bezelStyle = .inline
        gear.contentTintColor = .secondaryLabelColor
        gear.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(gear)
        content.addSubview(scroll)
        content.addSubview(status)
        statusGap = scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6)
        statusBottom = status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        statusHeight = status.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            // 窓の上端は掴んで動かすための帯なので、そのぶん空けて歯車だけを置く
            gear.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            gear.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            gear.widthAnchor.constraint(equalToConstant: 22),
            scroll.topAnchor.constraint(equalTo: gear.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusGap,
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            statusBottom,
            statusHeight,
        ])
    }

    /// 平常時は文字を持たないので、場所ごと畳む。
    /// 空の文字欄でも高さは残るため、隠すだけでは下に余白が残る
    private func collapseStatus(_ collapsed: Bool) {
        // 高さは外して本来の大きさに戻す。定数で入れ直すと複数行のエラーが切れる
        statusHeight.isActive = collapsed
        statusGap.constant = collapsed ? 0 : -6
        statusBottom.constant = collapsed ? 0 : -10
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
        rows = []
        // アプリごとにまとめ、束の並びはその束の最新の時刻で決める
        let groups = Dictionary(grouping: inbox, by: \.bundleID)
        let ordered = groups.sorted {
            ($0.value.first?.deliveredAt ?? .distantPast) > ($1.value.first?.deliveredAt ?? .distantPast)
        }
        for (bundleID, items) in ordered {
            rows.append(.header(bundleID: bundleID, app: items[0].appName))
            rows.append(contentsOf: items.map { Row.item($0) })
        }
        table.reloadData()
        updateHover()
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
            collapseStatus(false)
            return
        }
        // 平常時は何も言わない。一覧を見れば有無は分かる（SPEC.md「件数は出さない」）。
        // 場所だけ残すのは、読めなくなったときの赤字の行き先として要るため
        status.stringValue = ""
        status.textColor = .secondaryLabelColor
        collapseStatus(true)
    }

    // MARK: - 操作

    @objc private func openSettings() { onOpenSettings?() }

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

    /// カーソルの真下の行だけボタンを見せる。
    ///
    /// 位置から毎回引き直すので、スクロールでも窓の外へ出ても取り残しが出ない
    @objc private func scrolled() { updateHover() }

    func updateHover() {
        guard let window = table.window else { return }
        let inTable = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hovered = table.bounds.contains(inTable) ? table.row(at: inTable) : -1
        for row in table.rows(in: table.visibleRect).lowerBound
            ..< table.rows(in: table.visibleRect).upperBound {
            guard let view = table.view(atColumn: 0, row: row, makeIfNecessary: false)
                    as? HoverRevealView else { continue }
            view.revealed?.alphaValue = row == hovered ? 1 : 0
        }
    }

    private func item(at row: Int) -> NonjaNotification? {
        guard row >= 0, row < rows.count else { return nil }
        switch rows[row] {
        case .item(let item): return item
        case .header: return nil
        }
    }

    /// マウスで押された行を開く。一段目のクリックで飛ぶ（SPEC.md「既読は一覧から消えること」）
    @objc private func rowClicked() {
        guard let item = item(at: table.clickedRow) else { return }
        open(item)
    }

    @objc func openSelected() {
        guard let item = item(at: table.selectedRow) else { return }
        open(item)
    }

    private func open(_ item: NonjaNotification) {
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

    /// 行に出したボタンから既読にする。Delete と同じ扱いで、元アプリへは飛ばない
    @objc private func readRow(_ sender: NSButton) {
        guard let uuid = sender.identifier?.rawValue,
              let item = inbox.first(where: { $0.uuid == uuid }) else { return }
        retireAndDrop(item)
    }

    /// 手で既読にする。ルールの時間切れと同じ扱いにする
    private func retireSelected() {
        guard let item = item(at: table.selectedRow) else { return }
        retireAndDrop(item)
    }

    private func retireAndDrop(_ item: NonjaNotification) {
        retire(item)
        state.save()
        inbox.removeAll { $0.uuid == item.uuid }
        rebuildRows()
        updateStatus(error: nil)
        onChange?()
    }

    // MARK: - 束ごとの操作

    /// そのアプリの通知設定を OS 側で開く（SPEC.md「アプリ単位の通知は OS の設定へ送る」）。
    /// Nonja 側では何も持たない。切る場所を二つに分けない
    @objc private func openNotificationSettings(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue,
              let url = URL(string: "x-apple.systempreferences:"
                            + "com.apple.Notifications-Settings.extension?id=\(bundleID)")
        else { return }
        NSWorkspace.shared.open(url)
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

    /// 見出しは選ばせない
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let bundleID, let app):
            // アプリ名そのものが、そのアプリの通知設定への入口。
            // 見出しにボタンを増やさずに済む（SPEC.md「アプリ単位の通知は OS の設定へ送る」）
            let label = PointingButton(title: app.uppercased(), target: self,
                                       action: #selector(openNotificationSettings(_:)))
            label.isBordered = false
            label.bezelStyle = .inline
            label.font = .systemFont(ofSize: 10, weight: .bold)
            label.contentTintColor = .tertiaryLabelColor
            label.identifier = .init(bundleID)

            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)

            // 束ごとの操作。1件ずつ触らずに済むようにする
            // 行のボタンと同じ言葉にしない。どちらが一件でどちらが全部か読めなくなる
            let readAll = smallButton("すべて既読", #selector(readGroup(_:)), bundleID)

            let stack = NSStackView(views: [label, spacer, readAll])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 6
            stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 2, right: 16)
            return stack

        case .item(let item):
            return cell(item)

        }
    }

    private func cell(_ item: NonjaNotification) -> HoverRevealView {
        let bundleID = item.bundleID
        let when = item.deliveredAt
        let text = item.oneLine
        let icon = NSImageView(image: AppNames.icon(for: bundleID))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let body = NSTextField(labelWithString: text.isEmpty ? "（本文なし）" : Self.clip(text))
        body.font = .systemFont(ofSize: 12.5, weight: .medium)
        body.textColor = .labelColor
        body.lineBreakMode = .byTruncatingTail
        body.maximumNumberOfLines = 3
        // 折り返す幅を先に教える。これが無いと本文が一行のまま伸び、
        // 高さも測れず、行が窓の外へ出ていく
        body.preferredMaxLayoutWidth = Self.bodyWidth(in: table.bounds.width)

        let time = NSTextField(labelWithString: Self.formatter.string(from: when))
        time.font = .systemFont(ofSize: 10)
        time.textColor = .tertiaryLabelColor

        let lines = NSStackView(views: [body, time])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 3

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        // 指を乗せた行にだけ出す。休んでいる間は透明で、場所だけ取っている
        let read = smallButton("既読", #selector(readRow(_:)), item.uuid)
        read.alphaValue = 0

        let row = HoverRevealView(views: [icon, lines, spacer, read])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: Self.rowPadding, left: 16,
                                      bottom: Self.rowPadding, right: 14)
        row.revealed = read
        return row
    }

    /// 行の中身の上下に置く余白。高さの計算と行の組み立てで同じ値を使う
    private static let rowPadding: CGFloat = 8

    /// 本文の行数を抑える。
    ///
    /// `maximumNumberOfLines` は折り返しにしか効かず、本文が自前で持っている改行は数えない。
    /// 長い投稿がそのまま並ぶと一件で窓が埋まるので、文字の側で断つ
    private static func clip(_ text: String, lines: Int = 3) -> String {
        let all = text.components(separatedBy: "\n")
        guard all.count > lines else { return text }
        return all.prefix(lines).joined(separator: "\n") + "…"
    }

    /// 本文が使える幅。左の余白と絵、右の余白と「既読」のぶんを引く
    private static func bodyWidth(in tableWidth: CGFloat) -> CGFloat {
        max(120, tableWidth - (16 + 26 + 10 + 14 + 44))
    }

    /// 行ごとの高さ。中身を一度組んで測る。
    ///
    /// 表は 10 秒ごとに読み直すので、同じ幅で測った結果は取っておく
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .header:
            return 28
        case .item(let item):
            let width = tableView.bounds.width
            let key = "\(item.uuid)@\(Int(width))"
            if let known = heights[key] { return known }
            let view = cell(item)
            view.setFrameSize(NSSize(width: width, height: 0))
            view.layoutSubtreeIfNeeded()
            // 外側の `fittingSize` は数 pt 足りず、その不足が下の余白だけを削る。
            // 中身の高さを取って、上下の余白は自分で足す
            let content = view.arrangedSubviews.map(\.fittingSize.height).max() ?? 0
            let height = max(44, content + Self.rowPadding * 2)
            heights[key] = height
            return height
        }
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
