import Foundation

/// 自分の側で覚えておくもの。
///
/// 片付けた通知の控えは持たない。元の通知は macOS の通知センターに残っているので、
/// 二重に抱える意味が薄い。通知センターのデータベースには一切書き込まない。
final class State: Codable {
    /// 一度でも一覧に出した
    var displayed: Set<String> = []
    /// クリックして開いた
    var clicked: Set<String> = []
    /// 目を通したもの。クリックか、まとめて既読にする操作で入る
    var read: Set<String> = []
    /// 時間切れで片付けた。受信箱には出さない
    var retired: Set<String> = []
    var settings = Settings()

    // MARK: - 保存

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nonja", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }

    static func load() -> State {
        let decoder = JSONDecoder()
        // 書き出し側と形式を揃える。ここを忘れると読み込みが丸ごと失敗して設定が消える
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(State.self, from: data) else { return State() }
        return state
    }

    /// 自己テストのときはディスクに触らない
    var persists = true

    func save() {
        guard persists else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// 保存した JSON をそのまま読み書きする都合で、日付の形式を合わせる
    private enum CodingKeys: String, CodingKey {
        case displayed, clicked, read, retired, settings
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayed = try c.decodeIfPresent(Set<String>.self, forKey: .displayed) ?? []
        clicked = try c.decodeIfPresent(Set<String>.self, forKey: .clicked) ?? []
        read = try c.decodeIfPresent(Set<String>.self, forKey: .read) ?? []
        retired = try c.decodeIfPresent(Set<String>.self, forKey: .retired) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
    }
}
