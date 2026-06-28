/// Pure function that converts a selected string to a display string in "U+XXXX ..." format.
enum CodePointFormatter {
    static let maxScalars = 24

    /// Lists each scalar as U+XXXX. When there is exactly one scalar, appends the Unicode name.
    /// Empty input returns an empty string. When the count exceeds maxScalars, returns the first maxScalars entries plus " … (+N)".
    static func describe(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        if scalars.isEmpty { return "" }

        var parts = scalars.prefix(maxScalars).map(hex)
        if scalars.count == 1, let name = scalars[0].properties.name, !name.isEmpty {
            parts[0] += " " + name
        }

        var result = parts.joined(separator: " ")
        if scalars.count > maxScalars {
            result += " … (+\(scalars.count - maxScalars))"
        }
        return result
    }

    /// Formats a scalar as "U+XXXX" with at least 4 uppercase hex digits.
    private static func hex(_ scalar: Unicode.Scalar) -> String {
        let digits = String(scalar.value, radix: 16, uppercase: true)
        let padded = digits.count < 4
            ? String(repeating: "0", count: 4 - digits.count) + digits
            : digits
        return "U+" + padded
    }
}
