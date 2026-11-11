import Foundation

/// An open-ended JSON document; RPC records are too loose for fixed `Codable` shapes.
enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init?(data: Data) {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        self.init(any: any)
    }

    private init?(any: Any) {
        switch any {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.compactMap { JSONValue(any: $0) })
        case let object as [String: Any]:
            self = .object(object.compactMapValues { JSONValue(any: $0) })
        case is NSNull:
            self = .null
        default:
            return nil
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var double: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var int: Int? {
        double.flatMap { Int(exactly: $0.rounded()) }
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Compact JSON with stable key order, so equal arguments always produce equal text.
    var serialized: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: foundationObject,
            options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.foundationObject)
        case .object(let values): values.mapValues(\.foundationObject)
        }
    }
}
