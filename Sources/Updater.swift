import AppKit
import Sparkle

// 自動更新。Gocci と同じ組み方で、鍵も同じものを使う。
//
// 確認は起動時に1回だけで、定期的には見に行かない。見つかったときだけ画面を出す。
// 通知の鬱陶しさを減らすためのアプリが、自分の更新で割り込んでは筋が通らない。
//
// Sparkle は既定だと初回起動で「自動で確認していいか」を尋ねる画面を出すので、
// Info.plist の SUEnableAutomaticChecks を false にして止めてある。

final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()

    /// 起動時の確認で更新が見つかったか。画面を出すのは確認が終わってから
    private var foundUpdate = false

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)

    /// 起動時の確認。何も無ければ黙って終わる
    func checkQuietly() {
        controller.updater.checkForUpdateInformation()
    }

    /// 設定画面の「更新を確認」。最新のときも結果を出す
    func checkNow() {
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    // MARK: - SPUUpdaterDelegate

    /// 黙って確認した結果、更新があった。
    /// ここで画面を出そうとしても、確認の最中なので Sparkle に捨てられる。
    /// 覚えておいて、確認が終わってから改めて頼む
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        nonjaLog.info("更新が見つかった: \(item.displayVersionString, privacy: .public)")
        foundUpdate = true
    }

    /// 確認が終わった。見つからなかった場合や失敗した場合もここに来る
    func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        nonjaLog.info("更新の確認が終わった: \(error.map { "\($0)" } ?? "問題なし", privacy: .public)")
        guard foundUpdate else { return }
        foundUpdate = false

        DispatchQueue.main.async { [weak self] in
            self?.checkNow()
        }
    }
}
