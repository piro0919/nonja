import AppKit
import Foundation

// アイコンの下ごしらえ。生成した絵はそのままでは使えないので二つの処理を用意する。
//
//   template <入力> <出力>  白地を抜いて、残りを真っ黒にする（メニューバー用）
//   square   <入力> <出力>  透過を背景色で埋めて、透明の無い正方形にする（アプリ本体用）
//
// 元絵の色空間はまちまちで、`NSBitmapImageRep.colorAt` は扱えないことがある
// （実際に -1 の色空間が来て全画素が読めなかった）。
// そこで必ず一度 sRGB の RGBA へ描き直してから、生のバイト列を触る。

/// 入力を sRGB の RGBA8 に正規化して読み込む
func loadPixels(_ path: String) -> (bytes: [UInt8], width: Int, height: Int) {
    guard let data = FileManager.default.contents(atPath: path),
          let source = NSBitmapImageRep(data: data) else {
        FileHandle.standardError.write("読めません: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    let width = source.pixelsWide, height = source.pixelsHigh
    var bytes = [UInt8](repeating: 0, count: width * height * 4)

    bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            FileHandle.standardError.write("描き直せません\n".data(using: .utf8)!)
            exit(1)
        }
        if let cg = source.cgImage {
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    return (bytes, width, height)
}

func writePNG(_ bytes: [UInt8], width: Int, height: Int, to path: String) {
    var mutable = bytes
    let image: CGImage? = mutable.withUnsafeMutableBytes { raw -> CGImage? in
        guard let context = CGContext(
            data: raw.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        return context.makeImage()
    }
    guard let cg = image else { exit(1) }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: path))
}

/// 明るい画素を透明にし、それ以外を真っ黒にする。
/// メニューバーのアイコンは色を持てず、形と透明度だけで表される
func template(_ input: String, _ output: String) {
    var (bytes, width, height) = loadPixels(input)
    for i in stride(from: 0, to: bytes.count, by: 4) {
        let a = Int(bytes[i + 3])
        let brightness = (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
        // 元が透明ならそのまま透明。明るいところも背景とみなして抜く
        let keep = a > 127 && brightness < 128
        bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0
        bytes[i + 3] = keep ? 255 : 0
    }
    writePNG(bytes, width: width, height: height, to: output)
}

/// 透明を背景色で埋める。macOS 26 のアイコンは透明を持てない
func square(_ input: String, _ output: String) {
    var (bytes, width, height) = loadPixels(input)
    // 埋める色は左上の画素から取る。背景が単色でなくても近い色になる
    let corner = (r: Int(bytes[0]), g: Int(bytes[1]), b: Int(bytes[2]))
    for i in stride(from: 0, to: bytes.count, by: 4) {
        let a = Int(bytes[i + 3])
        if a == 255 { continue }
        // premultiplied なので、足りないぶんを背景色で補う
        bytes[i] = UInt8(min(255, Int(bytes[i]) + corner.r * (255 - a) / 255))
        bytes[i + 1] = UInt8(min(255, Int(bytes[i + 1]) + corner.g * (255 - a) / 255))
        bytes[i + 2] = UInt8(min(255, Int(bytes[i + 2]) + corner.b * (255 - a) / 255))
        bytes[i + 3] = 255
    }
    writePNG(bytes, width: width, height: height, to: output)
}

let args = CommandLine.arguments
guard args.count == 4 else {
    print("使い方: icon template|square <入力> <出力>")
    exit(1)
}
switch args[1] {
case "template": template(args[2], args[3])
case "square": square(args[2], args[3])
default:
    print("不明な指定: \(args[1])")
    exit(1)
}
