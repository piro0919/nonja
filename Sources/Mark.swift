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

    static func menuBarImage(hasItems: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width / 100  // 100 を一辺とした座標で組み立てる
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }

            // 胴。裾から左を上がり、頂点を回って右へ下りる。一本の閉じた形として引く
            let bell = NSBezierPath()
            bell.move(to: p(20, 26))
            bell.curve(to: p(26, 54), controlPoint1: p(20, 40), controlPoint2: p(25, 44))
            bell.curve(to: p(50, 82), controlPoint1: p(27, 70), controlPoint2: p(36, 82))
            bell.curve(to: p(74, 54), controlPoint1: p(64, 82), controlPoint2: p(73, 70))
            bell.curve(to: p(80, 26), controlPoint1: p(75, 44), controlPoint2: p(80, 40))
            // 裾は少し外へ張り出して、丸めた角で閉じる
            bell.curve(to: p(84, 20), controlPoint1: p(84, 26), controlPoint2: p(84, 24))
            bell.line(to: p(16, 20))
            bell.curve(to: p(20, 26), controlPoint1: p(16, 24), controlPoint2: p(16, 26))
            bell.close()
            bell.appendOval(in: NSRect(x: 44 * s, y: 79 * s, width: 12 * s, height: 12 * s))
            bell.appendOval(in: NSRect(x: 41 * s, y: 6 * s, width: 18 * s, height: 18 * s))

            // 覆面のスリット。丸めた端を胴の中に置くと両脇に黒い出っ張りが残るので、
            // 胴より外まで伸ばした真っ直ぐな帯で断ち切る
            let slit = NSRect(x: 0, y: 45 * s, width: 100 * s, height: 10 * s)

            NSColor.black.setFill()
            NSColor.black.setStroke()

            // 帯は切り抜きであって形の一部ではない。塗りにも輪郭にも同じ切り抜きを当てる。
            // 帯を足して evenOdd で塗ると、胴の外へ出た帯まで塗られて横棒が刺さる
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(rect: rect)
            clip.appendRect(slit)
            clip.windingRule = .evenOdd
            clip.setClip()
            if hasItems {
                bell.fill()
            } else {
                // 何も溜まっていないときは輪郭だけ
                bell.lineWidth = 7 * s
                bell.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
