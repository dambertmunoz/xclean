import Foundation

enum ANSI {
    static var isEnabled: Bool = {
        guard isatty(fileno(stdout)) != 0 else { return false }
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        if ProcessInfo.processInfo.environment["TERM"] == "dumb" { return false }
        return true
    }()

    private static func wrap(_ code: String, _ text: String) -> String {
        guard isEnabled else { return text }
        return "\u{1B}[\(code)m\(text)\u{1B}[0m"
    }

    static func bold(_ s: String) -> String   { wrap("1", s) }
    static func dim(_ s: String) -> String    { wrap("2", s) }
    static func red(_ s: String) -> String    { wrap("31", s) }
    static func green(_ s: String) -> String  { wrap("32", s) }
    static func yellow(_ s: String) -> String { wrap("33", s) }
    static func blue(_ s: String) -> String   { wrap("34", s) }
    static func magenta(_ s: String) -> String { wrap("35", s) }
    static func cyan(_ s: String) -> String   { wrap("36", s) }
    static func gray(_ s: String) -> String   { wrap("90", s) }
}

private let stdout = Darwin.stdout
