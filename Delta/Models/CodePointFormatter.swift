/// 選択文字列を「U+XXXX ...」の表示文字列にする純粋関数。
enum CodePointFormatter {
    static let maxScalars = 24

    /// 各スカラーを U+XXXX で列挙する。ちょうど1スカラーのときは Unicode 名を併記。
    /// 空入力は空文字。maxScalars を超える場合は先頭 maxScalars 個＋" … (+N)"。
    static func describe(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        if scalars.isEmpty { return "" }

        var parts = scalars.prefix(maxScalars).map(hex)
        if scalars.count == 1, let name = scalars.first?.properties.name, !name.isEmpty {
            parts[0] += " " + name
        }

        var result = parts.joined(separator: " ")
        if scalars.count > maxScalars {
            result += " … (+\(scalars.count - maxScalars))"
        }
        return result
    }

    /// スカラーを最小4桁の "U+XXXX"（大文字16進）にする。
    private static func hex(_ scalar: Unicode.Scalar) -> String {
        let digits = String(scalar.value, radix: 16, uppercase: true)
        let padded = digits.count < 4
            ? String(repeating: "0", count: 4 - digits.count) + digits
            : digits
        return "U+" + padded
    }
}
