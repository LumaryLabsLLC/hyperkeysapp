import EventEngine
import Foundation

public struct KeyDefinition: Sendable {
    public let keyCode: KeyCode?
    public let label: String
    public let width: CGFloat   // relative width, 1.0 = standard key
    public let height: CGFloat  // relative height, 1.0 = standard, 0.5 = half-height
    public let row: Int
    public let isSpacer: Bool   // non-interactive gap between function key groups

    public init(
        keyCode: KeyCode? = nil,
        label: String,
        width: CGFloat = 1.0,
        height: CGFloat = 1.0,
        row: Int,
        isSpacer: Bool = false
    ) {
        self.keyCode = keyCode
        self.label = label
        self.width = width
        self.height = height
        self.row = row
        self.isSpacer = isSpacer
    }
}

// All rows sum to 14.5 units wide to stay aligned.
public enum KeyboardLayout {

    // Row 0: Function row (half-height) — total 14.5
    // esc(1.0) + gap(0.1) + F1-F4(4×1.0) + gap(0.15) + F5-F8(4×1.0) + gap(0.15) + F9-F12(4×1.0) + gap(0.1) + power(1.0)
    public static let macbookProRows: [[KeyDefinition]] = [
        [
            KeyDefinition(keyCode: .escape, label: "esc", width: 1.0, height: 0.5, row: 0),
            KeyDefinition(label: "", width: 0.1, height: 0.5, row: 0, isSpacer: true),
            KeyDefinition(keyCode: .f1, label: "F1", height: 0.5, row: 0),
            KeyDefinition(keyCode: .f2, label: "F2", height: 0.5, row: 0),
            KeyDefinition(keyCode: .f3, label: "F3", height: 0.5, row: 0),
            KeyDefinition(keyCode: .f4, label: "F4", height: 0.5, row: 0),
            KeyDefinition(label: "", width: 0.15, height: 0.5, row: 0, isSpacer: true),
            KeyDefinition(keyCode: .f5, label: "F5", height: 0.5, row: 0),
            KeyDefinition(keyCode: .f6, label: "F6", height: 0.5, row: 0),
            KeyDefinition(keyCode: .f7, label: "F7", height: 0.5, row: 0),
            KeyDefinition(keyCode: .f8, label: "F8", height: 0.5, row: 0),
            KeyDefinition(label: "", width: 0.15, height: 0.5, row: 0, isSpacer: true),
            KeyDefinition(keyCode: .f9, label: "F9", height: 0.5, row: 0),
            KeyDefinition(keyCode: .f10, label: "F10", height: 0.5, row: 0),
            KeyDefinition(keyCode: .f11, label: "F11", height: 0.5, row: 0),
            KeyDefinition(keyCode: .f12, label: "F12", height: 0.5, row: 0),
            KeyDefinition(label: "", width: 0.1, height: 0.5, row: 0, isSpacer: true),
            KeyDefinition(label: "⏻", width: 1.0, height: 0.5, row: 0),
        ],
        // Row 1: Number row — total 14.5
        // 13×1.0 + delete(1.5) = 14.5
        [
            KeyDefinition(keyCode: .grave, label: "~\n`", row: 1),
            KeyDefinition(keyCode: .one, label: "!\n1", row: 1),
            KeyDefinition(keyCode: .two, label: "@\n2", row: 1),
            KeyDefinition(keyCode: .three, label: "#\n3", row: 1),
            KeyDefinition(keyCode: .four, label: "$\n4", row: 1),
            KeyDefinition(keyCode: .five, label: "%\n5", row: 1),
            KeyDefinition(keyCode: .six, label: "^\n6", row: 1),
            KeyDefinition(keyCode: .seven, label: "&\n7", row: 1),
            KeyDefinition(keyCode: .eight, label: "*\n8", row: 1),
            KeyDefinition(keyCode: .nine, label: "(\n9", row: 1),
            KeyDefinition(keyCode: .zero, label: ")\n0", row: 1),
            KeyDefinition(keyCode: .minus, label: "_\n-", row: 1),
            KeyDefinition(keyCode: .equal, label: "+\n=", row: 1),
            KeyDefinition(keyCode: .delete, label: "delete", width: 1.5, row: 1),
        ],
        // Row 2: QWERTY — total 14.5
        // tab(1.5) + 13×1.0 = 14.5
        [
            KeyDefinition(keyCode: .tab, label: "tab", width: 1.5, row: 2),
            KeyDefinition(keyCode: .q, label: "Q", row: 2),
            KeyDefinition(keyCode: .w, label: "W", row: 2),
            KeyDefinition(keyCode: .e, label: "E", row: 2),
            KeyDefinition(keyCode: .r, label: "R", row: 2),
            KeyDefinition(keyCode: .t, label: "T", row: 2),
            KeyDefinition(keyCode: .y, label: "Y", row: 2),
            KeyDefinition(keyCode: .u, label: "U", row: 2),
            KeyDefinition(keyCode: .i, label: "I", row: 2),
            KeyDefinition(keyCode: .o, label: "O", row: 2),
            KeyDefinition(keyCode: .p, label: "P", row: 2),
            KeyDefinition(keyCode: .leftBracket, label: "{\n[", row: 2),
            KeyDefinition(keyCode: .rightBracket, label: "}\n]", row: 2),
            KeyDefinition(keyCode: .backslash, label: "|\n\\", row: 2),
        ],
        // Row 3: ASDF — total 14.5
        // caps(1.75) + 11×1.0 + return(1.75) = 14.5
        [
            KeyDefinition(label: "caps lock", width: 1.75, row: 3),
            KeyDefinition(keyCode: .a, label: "A", row: 3),
            KeyDefinition(keyCode: .s, label: "S", row: 3),
            KeyDefinition(keyCode: .d, label: "D", row: 3),
            KeyDefinition(keyCode: .f, label: "F", row: 3),
            KeyDefinition(keyCode: .g, label: "G", row: 3),
            KeyDefinition(keyCode: .h, label: "H", row: 3),
            KeyDefinition(keyCode: .j, label: "J", row: 3),
            KeyDefinition(keyCode: .k, label: "K", row: 3),
            KeyDefinition(keyCode: .l, label: "L", row: 3),
            KeyDefinition(keyCode: .semicolon, label: ":\n;", row: 3),
            KeyDefinition(keyCode: .quote, label: "\"\n'", row: 3),
            KeyDefinition(keyCode: .returnKey, label: "return", width: 1.75, row: 3),
        ],
        // Row 4: ZXCV — total 14.5
        // shift(2.25) + 10×1.0 + shift(2.25) = 14.5
        [
            KeyDefinition(label: "shift", width: 2.25, row: 4),
            KeyDefinition(keyCode: .z, label: "Z", row: 4),
            KeyDefinition(keyCode: .x, label: "X", row: 4),
            KeyDefinition(keyCode: .c, label: "C", row: 4),
            KeyDefinition(keyCode: .v, label: "V", row: 4),
            KeyDefinition(keyCode: .b, label: "B", row: 4),
            KeyDefinition(keyCode: .n, label: "N", row: 4),
            KeyDefinition(keyCode: .m, label: "M", row: 4),
            KeyDefinition(keyCode: .comma, label: "<\n,", row: 4),
            KeyDefinition(keyCode: .period, label: ">\n.", row: 4),
            KeyDefinition(keyCode: .slash, label: "?\n/", row: 4),
            KeyDefinition(label: "shift", width: 2.25, row: 4),
        ],
    ]

    // Row 5: Bottom row — total 14.5
    // fn(1.0) + ctrl(1.0) + opt(1.25) + cmd(1.5) + space(4.0) + cmd(1.5) + opt(1.25) + arrows(3.0)
    public static let bottomRow: [KeyDefinition] = [
        KeyDefinition(label: "fn", width: 1.0, row: 5),
        KeyDefinition(label: "^\ncontrol", width: 1.0, row: 5),
        KeyDefinition(label: "⌥\noption", width: 1.25, row: 5),
        KeyDefinition(label: "⌘\ncommand", width: 1.5, row: 5),
        KeyDefinition(keyCode: .space, label: "", width: 4.0, row: 5),
        KeyDefinition(label: "⌘\ncommand", width: 1.5, row: 5),
        KeyDefinition(label: "⌥\noption", width: 1.25, row: 5),
    ]

    public static let arrowUp = KeyDefinition(keyCode: .upArrow, label: "▲", height: 0.5, row: 5)
    public static let arrowDown = KeyDefinition(keyCode: .downArrow, label: "▼", height: 0.5, row: 5)
    public static let arrowLeft = KeyDefinition(keyCode: .leftArrow, label: "◀", row: 5)
    public static let arrowRight = KeyDefinition(keyCode: .rightArrow, label: "▶", row: 5)
}
