import Foundation

/// How one JSON value should be rendered in tree mode.
///
/// Extracted from `JSONTreeView.valueView`, which tested `value as? Bool`
/// before `value as? NSNumber`. `JSONSerialization` returns every number as an
/// `NSNumber`, and `NSNumber(1) as? Bool` succeeds — so the integers 1 and 0
/// rendered as `true` and `false`, coloured like real booleans. The formatted
/// and minified tabs showed the same document correctly, so one item read two
/// different ways depending on the selected tab.
enum JSONValueRendering: Equatable {
    case boolean(String)
    case number(String)
    case string(String)
    case null
    case dictionary(count: Int)
    case array(count: Int)
    case unknown(String)

    static func describe(_ value: Any) -> JSONValueRendering {
        if value is NSNull { return .null }

        // NSNumber BEFORE Bool, and distinguish a real boolean by its CFType
        // rather than by a bridging cast that 1 and 0 also satisfy.
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue ? "true" : "false")
            }
            return .number(number.stringValue)
        }

        if let bool = value as? Bool { return .boolean(bool ? "true" : "false") }
        if let string = value as? String { return .string(string) }
        if let dict = value as? [String: Any] { return .dictionary(count: dict.count) }
        if let array = value as? [Any] { return .array(count: array.count) }
        return .unknown(String(describing: value))
    }
}
