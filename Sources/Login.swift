import Foundation
import ServiceManagement

/// ログイン時の自動起動。
///
/// 常駐して初めて意味が出るアプリなので、毎回手で起動する状態だと使われない。
/// `SMAppService.mainApp` は macOS 13 以降の仕組みで、補助の実行ファイルを持たずに
/// アプリ自身を登録できる。登録すると「ログイン項目」に Nonja が並ぶ。
enum Login {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 登録に失敗しても致命的ではないので、結果を返して呼び手に任せる
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // すでに登録済みで register を呼ぶと失敗するので、状態を見てから
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            nonjaLog.error("ログイン項目の切り替えに失敗: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
