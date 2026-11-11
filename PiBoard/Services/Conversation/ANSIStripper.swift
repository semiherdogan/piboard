import Foundation

/// Extension status text is written for a terminal footer, so it carries color and link escapes.
enum ANSIStripper {
    private static let escape: Unicode.Scalar = "\u{1B}"
    private static let bell: Unicode.Scalar = "\u{07}"
    private static let csiIntroducer: Unicode.Scalar = "["
    private static let oscIntroducer: Unicode.Scalar = "]"
    private static let csiFinalBytes: ClosedRange<UInt32> = 0x40...0x7E

    /// Removes CSI and OSC sequences; any other escape drops itself and the byte after it.
    static func strip(_ text: String) -> String {
        guard text.unicodeScalars.contains(escape) else { return text }
        var result = String.UnicodeScalarView()
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            guard scalar == escape else {
                result.append(scalar)
                continue
            }
            guard let introducer = iterator.next() else { break }
            switch introducer {
            case csiIntroducer:
                while let next = iterator.next(), !csiFinalBytes.contains(next.value) {}
            case oscIntroducer:
                // An OSC ends at BEL or at ESC followed by a backslash.
                while let next = iterator.next() {
                    if next == bell { break }
                    if next == escape {
                        _ = iterator.next()
                        break
                    }
                }
            default:
                break
            }
        }
        return String(result)
    }
}
