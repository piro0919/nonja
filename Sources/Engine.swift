import Foundation

/// 読み出した通知にルールを当てて、受信箱に出すものを決める。
///
/// 通知センター側には手を触れない。片付けるのはこちらの表示だけで、
/// 元の通知は macOS の通知センターにそのまま残る。だからクリックすれば飛べる。
enum Engine {

    struct Result {
        /// 受信箱に出すもの。新しい順
        var inbox: [NonjaNotification] = []
        /// 今回の読み込みで時間切れになった件数
        var retiredNow = 0
    }

    static func apply(_ items: [NonjaNotification], state: State, now: Date = Date()) -> Result {
        var result = Result()
        let settings = state.settings

        for item in items {
            if state.retired.contains(item.uuid) { continue }

            let rule = settings.rule(for: item)

            // 自動で既読にするものは受信箱に出さない。記録だけ残して素通しする
            if rule.action == .mute {
                state.retired.insert(item.uuid)
                continue
            }

            if rule.action == .hold, isExpired(item, rule: rule, state: state, now: now) {
                // 控えは残さない。元の通知は macOS の通知センターにそのまま残っている
                state.retired.insert(item.uuid)
                result.retiredNow += 1
                continue
            }

            result.inbox.append(item)
        }

        // 受信箱に出す＝一覧に出たということ。確認の基準が「表示」のときはここで確認済みになる
        for item in result.inbox { state.displayed.insert(item.uuid) }
        state.save()
        return result
    }

    /// 保持時間を過ぎていて、かつまだ確認していないもの
    private static func isExpired(_ item: NonjaNotification, rule: Rule,
                                  state: State, now: Date) -> Bool {
        if confirmed(item, state: state) { return false }
        let deadline = item.deliveredAt.addingTimeInterval(TimeInterval(rule.holdMinutes) * 60)
        return now >= deadline
    }

    private static func confirmed(_ item: NonjaNotification, state: State) -> Bool {
        switch state.settings.confirmBasis {
        case .displayed: return state.displayed.contains(item.uuid)
        case .clicked: return state.clicked.contains(item.uuid)
        }
    }

}
