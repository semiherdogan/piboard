import Foundation

/// What a one-shot Pi run loads on top of its locked-down defaults. Both default to empty,
/// which leaves model choice to Pi and loads no extensions.
struct PiHeadlessOptions: Equatable, Sendable {
    var model: String? = nil
    var extensions: [String] = []
}
