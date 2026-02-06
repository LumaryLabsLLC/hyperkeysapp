import Carbon.HIToolbox

public enum KeyCode: UInt16, CaseIterable, Codable, Sendable {
    // Letters
    case a = 0x00
    case s = 0x01
    case d = 0x02
    case f = 0x03
    case h = 0x04
    case g = 0x05
    case z = 0x06
    case x = 0x07
    case c = 0x08
    case v = 0x09
    case b = 0x0B
    case q = 0x0C
    case w = 0x0D
    case e = 0x0E
    case r = 0x0F
    case y = 0x10
    case t = 0x11
    case o = 0x1F
    case u = 0x20
    case i = 0x22
    case p = 0x23
    case l = 0x25
    case j = 0x26
    case k = 0x28
    case n = 0x2D
    case m = 0x2E

    // Numbers
    case one = 0x12
    case two = 0x13
    case three = 0x14
    case four = 0x15
    case five = 0x17
    case six = 0x16
    case seven = 0x1A
    case eight = 0x1C
    case nine = 0x19
    case zero = 0x1D

    // Symbols
    case minus = 0x1B
    case equal = 0x18
    case leftBracket = 0x21
    case rightBracket = 0x1E
    case backslash = 0x2A
    case semicolon = 0x29
    case quote = 0x27
    case comma = 0x2B
    case period = 0x2F
    case slash = 0x2C
    case grave = 0x32

    // Special
    case capsLock = 0x39
    case tab = 0x30
    case space = 0x31
    case returnKey = 0x24
    case delete = 0x33
    case escape = 0x35
    case forwardDelete = 0x75
    case f18 = 0x4F

    // Arrows
    case leftArrow = 0x7B
    case rightArrow = 0x7C
    case downArrow = 0x7D
    case upArrow = 0x7E

    // Function keys
    case f1 = 0x7A
    case f2 = 0x78
    case f3 = 0x63
    case f4 = 0x76
    case f5 = 0x60
    case f6 = 0x61
    case f7 = 0x62
    case f8 = 0x64
    case f9 = 0x65
    case f10 = 0x6D
    case f11 = 0x67
    case f12 = 0x6F

    public var displayLabel: String {
        switch self {
        case .a: "A"
        case .s: "S"
        case .d: "D"
        case .f: "F"
        case .h: "H"
        case .g: "G"
        case .z: "Z"
        case .x: "X"
        case .c: "C"
        case .v: "V"
        case .b: "B"
        case .q: "Q"
        case .w: "W"
        case .e: "E"
        case .r: "R"
        case .y: "Y"
        case .t: "T"
        case .o: "O"
        case .u: "U"
        case .i: "I"
        case .p: "P"
        case .l: "L"
        case .j: "J"
        case .k: "K"
        case .n: "N"
        case .m: "M"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        case .zero: "0"
        case .minus: "-"
        case .equal: "="
        case .leftBracket: "["
        case .rightBracket: "]"
        case .backslash: "\\"
        case .semicolon: ";"
        case .quote: "'"
        case .comma: ","
        case .period: "."
        case .slash: "/"
        case .grave: "`"
        case .capsLock: "⇪"
        case .tab: "⇥"
        case .space: "Space"
        case .returnKey: "⏎"
        case .delete: "⌫"
        case .escape: "⎋"
        case .forwardDelete: "⌦"
        case .f18: "F18"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .downArrow: "↓"
        case .upArrow: "↑"
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        case .f6: "F6"
        case .f7: "F7"
        case .f8: "F8"
        case .f9: "F9"
        case .f10: "F10"
        case .f11: "F11"
        case .f12: "F12"
        }
    }

    /// Keys that can be bound to Hyper+ actions (excludes escape)
    public var isBindable: Bool {
        switch self {
        case .escape:
            return false
        default:
            return true
        }
    }
}
