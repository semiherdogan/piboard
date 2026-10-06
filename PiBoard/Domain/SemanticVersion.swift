import Foundation

/// `MAJOR.MINOR.PATCH[-PRERELEASE]` per semver 2.0 precedence; build metadata is ignored.
struct SemanticVersion: Comparable, Hashable, Sendable {
    private static let coreSeparator: Character = "."
    private static let preReleaseSeparator: Character = "-"
    private static let buildMetadataSeparator: Character = "+"
    private static let coreComponentCount = 3

    let major: Int
    let minor: Int
    let patch: Int
    let preRelease: [String]

    init?(_ string: String) {
        let withoutBuild = string.split(separator: Self.buildMetadataSeparator, maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = withoutBuild.split(separator: Self.preReleaseSeparator, maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: Self.coreSeparator, omittingEmptySubsequences: false)
        guard core.count == Self.coreComponentCount else { return nil }
        let numbers = core.compactMap(Self.numericIdentifier)
        guard numbers.count == Self.coreComponentCount else { return nil }

        var preRelease: [String] = []
        if parts.count > 1 {
            let identifiers = parts[1].split(separator: Self.coreSeparator, omittingEmptySubsequences: false).map(String.init)
            guard !identifiers.isEmpty, identifiers.allSatisfy(Self.isValidPreReleaseIdentifier) else { return nil }
            preRelease = identifiers
        }

        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
        self.preRelease = preRelease
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // A release outranks any pre-release of the same core version.
        switch (lhs.preRelease.isEmpty, rhs.preRelease.isEmpty) {
        case (true, true), (true, false): return false
        case (false, true): return true
        case (false, false): break
        }
        for (left, right) in zip(lhs.preRelease, rhs.preRelease) where left != right {
            return precedes(left, right)
        }
        return lhs.preRelease.count < rhs.preRelease.count
    }

    // Numeric identifiers compare numerically and always rank below alphanumeric ones.
    private static func precedes(_ left: String, _ right: String) -> Bool {
        switch (Int(left), Int(right)) {
        case let (leftNumber?, rightNumber?): return leftNumber < rightNumber
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return left < right
        }
    }

    private static func numericIdentifier(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(text)
    }

    private static func isValidPreReleaseIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.allSatisfy { $0.isASCIIDigit || $0.isASCIILetter || $0 == preReleaseSeparator }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}
