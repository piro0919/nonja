import Foundation

/// 通知をどう扱うか。上から順に見て、最初に一致したものを使う（SPEC.md「振り分けルール」）
struct Rule: Codable, Equatable {
    enum Action: String, Codable, CaseIterable {
        /// すぐ受信箱に出す。時間で消えない
        case show
        /// 受信箱に出すが、時間切れで片付ける
        case hold
        /// 受信箱に出さず、最初から既読にする
        case mute

        var label: String {
            switch self {
            case .show: return "すぐ見せる"
            case .hold: return "溜める"
            case .mute: return "自動で既読"
            }
        }
    }

    /// 送信元のバンドル識別子。`nil` はどのアプリにも当たる既定の行
    var bundleID: String?
    var action: Action
    /// 溜める場合の保持時間（分）
    var holdMinutes: Int

    static let fallback = Rule(bundleID: nil, action: .show, holdMinutes: 60)

    func matches(_ item: NonjaNotification) -> Bool {
        guard let bundleID else { return true }
        return bundleID.caseInsensitiveCompare(item.bundleID) == .orderedSame
    }
}

/// 何をもって「確認した」とみなすか。使ってみてから決めるので両方持つ（SPEC.md「保留」）
enum ConfirmBasis: String, Codable, CaseIterable {
    /// 一覧に出た時点で確認済み
    case displayed
    /// クリックした時点で確認済み
    case clicked

    var label: String {
        switch self {
        case .displayed: return "一覧に出たら確認済み"
        case .clicked: return "クリックしたら確認済み"
        }
    }
}

struct Settings: Codable {
    var rules: [Rule] = []
    var confirmBasis: ConfirmBasis = .clicked

    /// 既定の行は必ず最後に一つだけ置く。編集画面から消せないようにするためここで担保する
    var effectiveRules: [Rule] {
        rules.filter { $0.bundleID != nil } + [fallbackRule]
    }

    var fallbackRule: Rule {
        rules.first { $0.bundleID == nil } ?? .fallback
    }

    func rule(for item: NonjaNotification) -> Rule {
        effectiveRules.first { $0.matches(item) } ?? .fallback
    }
}
