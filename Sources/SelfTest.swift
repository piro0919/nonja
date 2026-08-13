import Foundation

/// ルールの当たり方を、作った通知で確かめる。`./Nonja --selftest` で走る。
/// 画面を触らずに済むので、直したあと毎回これを通す。
enum SelfTest {

    private static var failures = 0

    static func run() -> Int32 {
        failures = 0

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func made(_ bundleID: String, minutesAgo: Int, uuid: String) -> NonjaNotification {
            NonjaNotification(uuid: uuid, bundleID: bundleID, title: "題", subtitle: nil,
                              body: "本文", deliveredAt: now.addingTimeInterval(-Double(minutesAgo) * 60))
        }

        // 溜める設定で、保持時間を過ぎたものは受信箱から消えてアーカイブに入る
        do {
            let state = fresh()
            state.settings.rules = [Rule(bundleID: "com.example.slow", action: .hold,
                                         holdMinutes: 60)]
            let items = [made("com.example.slow", minutesAgo: 10, uuid: "A"),
                         made("com.example.slow", minutesAgo: 90, uuid: "B")]
            let result = Engine.apply(items, state: state, now: now)
            check(result.inbox.map(\.uuid) == ["A"], "保持時間内だけが受信箱に残る")
            check(state.retired.contains("B"), "時間切れは片付けられる")
            check(result.retiredNow == 1, "時間切れの件数が数えられる")
        }

        // クリック済みは時間が過ぎても消えない
        do {
            let state = fresh()
            state.settings.rules = [Rule(bundleID: "com.example.slow", action: .hold,
                                         holdMinutes: 60)]
            state.clicked.insert("B")
            let result = Engine.apply([made("com.example.slow", minutesAgo: 90, uuid: "B")],
                                      state: state, now: now)
            check(result.inbox.map(\.uuid) == ["B"], "確認済みは時間切れにしない")
        }

        // 基準が「表示」なら、一度出したものはその後消えない
        do {
            let state = fresh()
            state.settings.confirmBasis = .displayed
            state.settings.rules = [Rule(bundleID: "com.example.slow", action: .hold,
                                         holdMinutes: 60)]
            let item = made("com.example.slow", minutesAgo: 10, uuid: "C")
            _ = Engine.apply([item], state: state, now: now)
            let later = Engine.apply([item], state: state, now: now.addingTimeInterval(3600 * 5))
            check(later.inbox.map(\.uuid) == ["C"], "表示基準では一度出したものが残り続ける")
        }

        // 自動で既読にするものは受信箱に出ない
        do {
            let state = fresh()
            state.settings.rules = [Rule(bundleID: "com.example.noisy", action: .mute,
                                         holdMinutes: 60)]
            let result = Engine.apply([made("com.example.noisy", minutesAgo: 1, uuid: "D")],
                                      state: state, now: now)
            check(result.inbox.isEmpty, "自動で既読にするものは受信箱に出ない")
        }

        // ルールの無いアプリは既定の行に当たる
        do {
            let state = fresh()
            state.settings.rules = [Rule(bundleID: nil, action: .hold,
                                         holdMinutes: 30)]
            let result = Engine.apply([made("com.example.other", minutesAgo: 60, uuid: "E")],
                                      state: state, now: now)
            check(result.inbox.isEmpty, "既定の行が効く")
            check(state.retired.contains("E"), "既定の行でも片付けられる")
        }

        // アプリごとの行が既定の行より優先される
        do {
            let state = fresh()
            state.settings.rules = [
                Rule(bundleID: nil, action: .mute, holdMinutes: 30),
                Rule(bundleID: "com.example.keep", action: .show, holdMinutes: 30),
            ]
            let result = Engine.apply([made("com.example.keep", minutesAgo: 600, uuid: "F")],
                                      state: state, now: now)
            check(result.inbox.map(\.uuid) == ["F"], "アプリ単位の行が既定より優先される")
        }

        print(failures == 0 ? "全部通りました" : "\(failures) 件こけました")
        return failures == 0 ? 0 : 1
    }

    private static func fresh() -> State {
        let state = State()
        state.persists = false
        return state
    }

    private static func check(_ condition: Bool, _ what: String) {
        if condition {
            print("  ok   \(what)")
        } else {
            print("  NG   \(what)")
            failures += 1
        }
    }
}
