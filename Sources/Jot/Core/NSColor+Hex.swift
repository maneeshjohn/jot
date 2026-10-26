import AppKit

extension NSColor {
  /// Creates an sRGB color from a hex string: `#RGB`, `#RGBA`, `#RRGGBB` or
  /// `#RRGGBBAA` (the `#` is optional). Returns `nil` for anything else.
  convenience init?(hex: String) {
    var digits = hex.trimmingCharacters(in: .whitespaces)
    if digits.hasPrefix("#") { digits.removeFirst() }

    // Expand shorthand: "f0a" → "ff00aa"
    if digits.count == 3 || digits.count == 4 {
      digits = digits.map { "\($0)\($0)" }.joined()
    }

    guard digits.count == 6 || digits.count == 8,
      digits.allSatisfy(\.isHexDigit),
      var value = UInt64(digits, radix: 16)
    else { return nil }

    if digits.count == 6 {
      value = (value << 8) | 0xFF  // fully opaque
    }

    func component(_ shift: UInt64) -> CGFloat {
      CGFloat((value >> shift) & 0xFF) / 255
    }

    self.init(srgbRed: component(24), green: component(16), blue: component(8), alpha: component(0))
  }
}
