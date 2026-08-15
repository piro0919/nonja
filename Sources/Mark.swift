import AppKit

/// メニューバーの印を図形として描く。
///
/// 生成した絵を縮めると、18 ピクセルでは輪郭がギザつき、左右の非対称も目立った。
/// 形が単純なので、そのつど描いたほうが綺麗で、どの倍率でも崩れない。
///
/// **件数は出さない。** 138 件でも 5 件でも、やることは開いて見るだけで、
/// 数字は判断を変えない。幅が伸び縮みするのも落ち着かない。
/// 未処理があるかないかだけを、塗りと輪郭で言う。
enum Mark {

    // 一辺を 100 とした座標で組み立てる。値の根拠は以下。
    //
    // - 尖りは 46。線幅の半分が外へ出るので、輪郭でも 49 に収まり縁に触れない
    // - 抉りの円は中心から 36 の位置に半径 20。これより浅いと腕が太って手裏剣に見えず、
    //   これより深いと 18pt で腕が消える
    // - 中央の穴は 11。18pt では 2 ピクセルほどになり、これ以上小さいと潰れる
    // - 線幅 6。18pt で約 1 ピクセルに乗る。7 だと細い腕の内側が線で埋まる
    private static let tipRadius: CGFloat = 46
    private static let biteCenter: CGFloat = 36
    private static let biteRadius: CGFloat = 20
    /// 抉りの円のうち、輪郭として使う範囲。中心を向く点から左右にこの角度ぶん
    private static let biteSpan: CGFloat = 60
    private static let holeRadius: CGFloat = 11
    private static let stroke: CGFloat = 6

    /// `rotation` は度。届いたときに短く回すために使う（SPEC.md「届いたら回す」）
    static func menuBarImage(hasItems: Bool, size: CGFloat = 18,
                             rotation: CGFloat = 0) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width / 100
            if rotation != 0 {
                // 中心を軸にする。原点のまま回すと画面の外へ出ていく
                let move = NSAffineTransform()
                move.translateX(by: rect.midX, yBy: rect.midY)
                move.rotate(byDegrees: rotation)
                move.translateX(by: -rect.midX, yBy: -rect.midY)
                move.concat()
            }
            let star = shuriken(scale: s)
            let hole = NSBezierPath(ovalIn: NSRect(
                x: (50 - holeRadius) * s, y: (50 - holeRadius) * s,
                width: holeRadius * 2 * s, height: holeRadius * 2 * s))

            NSColor.black.setFill()
            NSColor.black.setStroke()

            if hasItems {
                // 穴は切り抜き。図形に足して evenOdd で塗ると、外へ出た部分まで塗られる
                let path = star.copy() as! NSBezierPath
                path.append(hole)
                path.windingRule = .evenOdd
                path.fill()
            } else {
                // 空のときは穴を描かない。細い腕の内側と穴の線がぶつかって中央が潰れる
                star.lineWidth = stroke * s
                star.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 四方に尖った手裏剣の輪郭。
    ///
    /// 尖りと尖りの間は、対角線上に置いた円で抉る。腕の縁をその円の接線にすると、
    /// 繋ぎ目に角が出ない。塗りと輪郭で同じ道筋を使いたいので、
    /// 抉りは切り抜きではなく輪郭そのものとして引く（輪郭のときに線が途切れないため）
    private static func shuriken(scale s: CGFloat) -> NSBezierPath {
        let center = NSPoint(x: 50 * s, y: 50 * s)
        func point(_ degrees: CGFloat, _ radius: CGFloat) -> NSPoint {
            let a = degrees * .pi / 180
            return NSPoint(x: center.x + cos(a) * radius * s,
                           y: center.y + sin(a) * radius * s)
        }

        let path = NSBezierPath()
        for arm in 0..<4 {
            let axis = 90 + CGFloat(arm) * 90                 // 上・左・下・右
            let tip = point(axis, tipRadius)
            if arm == 0 { path.move(to: tip) } else { path.line(to: tip) }

            // この腕と次の腕の間を抉る円。中心へ向いた側の弧だけを使う
            let diagonal = axis + 45
            let bite = point(diagonal, biteCenter)
            // 弧は中心を向く点（diagonal + 180）を通す。逆回りにすると腕の外側を回り、
            // 形が裏返る。始点と終点をこの順にして時計回りに引く
            path.appendArc(
                withCenter: bite, radius: biteRadius * s,
                startAngle: diagonal + 180 + biteSpan,
                endAngle: diagonal + 180 - biteSpan,
                clockwise: true)
        }
        path.close()
        return path
    }
}
