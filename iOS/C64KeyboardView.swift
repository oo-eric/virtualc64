// -----------------------------------------------------------------------------
// This file is part of VirtualC64
//
// Copyright (C) Dirk W. Hoffmann. www.dirkwhoffmann.de
// This FILE is dual-licensed. You are free to choose between:
//
//     - The GNU General Public License v3 (or any later version)
//     - The Mozilla Public License v2
//
// SPDX-License-Identifier: GPL-3.0-or-later OR MPL-2.0
// -----------------------------------------------------------------------------

import SwiftUI

// MARK: - Key Layout Definition

/// Represents a single key in the C64 keyboard layout
struct C64KeyDef: Identifiable {
    let id: Int          // C64Key.nr (0-65)
    let label: String    // Primary label
    let width: CGFloat   // Relative width (1.0 = standard key)
    let isModifier: Bool // Sticky modifier key

    init(_ nr: Int, _ label: String, width: CGFloat = 1.0, modifier: Bool = false) {
        self.id = nr
        self.label = label
        self.width = width
        self.isModifier = modifier
    }
}

/// C64 keyboard layout organized by row
private let keyboardRows: [[C64KeyDef]] = [
    // Row 1: Arrow-left, 1-0, +, -, Pound, HOME, DEL
    [
        C64KeyDef(0, "\u{2190}"),          // left arrow
        C64KeyDef(1, "1"), C64KeyDef(2, "2"), C64KeyDef(3, "3"), C64KeyDef(4, "4"),
        C64KeyDef(5, "5"), C64KeyDef(6, "6"), C64KeyDef(7, "7"), C64KeyDef(8, "8"),
        C64KeyDef(9, "9"), C64KeyDef(10, "0"),
        C64KeyDef(11, "+"), C64KeyDef(12, "-"), C64KeyDef(13, "\u{00a3}"),
        C64KeyDef(14, "HOME"), C64KeyDef(15, "DEL"),
    ],
    // Row 2: CTRL, Q-P, @, *, Up-arrow, RESTORE
    [
        C64KeyDef(17, "CTRL", width: 1.3, modifier: true),
        C64KeyDef(18, "Q"), C64KeyDef(19, "W"), C64KeyDef(20, "E"), C64KeyDef(21, "R"),
        C64KeyDef(22, "T"), C64KeyDef(23, "Y"), C64KeyDef(24, "U"), C64KeyDef(25, "I"),
        C64KeyDef(26, "O"), C64KeyDef(27, "P"),
        C64KeyDef(28, "@"), C64KeyDef(29, "*"), C64KeyDef(30, "\u{2191}"),
        C64KeyDef(31, "RST"),
    ],
    // Row 3: RUN/STOP, SHIFT LOCK, A-L, :, ;, =, RETURN
    [
        C64KeyDef(33, "R/S"),
        C64KeyDef(34, "S/L", modifier: true),
        C64KeyDef(35, "A"), C64KeyDef(36, "S"), C64KeyDef(37, "D"), C64KeyDef(38, "F"),
        C64KeyDef(39, "G"), C64KeyDef(40, "H"), C64KeyDef(41, "J"), C64KeyDef(42, "K"),
        C64KeyDef(43, "L"),
        C64KeyDef(44, ":"), C64KeyDef(45, ";"), C64KeyDef(46, "="),
        C64KeyDef(47, "RETRN", width: 1.5),
    ],
    // Row 4: C=, SHIFT, Z-M, comma, period, /, SHIFT, Cursor UD, Cursor LR
    [
        C64KeyDef(49, "C\u{2550}", width: 1.2, modifier: true),
        C64KeyDef(50, "SHIFT", width: 1.2, modifier: true),
        C64KeyDef(51, "Z"), C64KeyDef(52, "X"), C64KeyDef(53, "C"), C64KeyDef(54, "V"),
        C64KeyDef(55, "B"), C64KeyDef(56, "N"), C64KeyDef(57, "M"),
        C64KeyDef(58, ","), C64KeyDef(59, "."), C64KeyDef(60, "/"),
        C64KeyDef(61, "SHIFT", width: 1.2, modifier: true),
        C64KeyDef(62, "\u{2195}"), C64KeyDef(63, "\u{2194}"),
    ],
    // Row 5: Function keys + SPACE
    [
        C64KeyDef(16, "F1"), C64KeyDef(32, "F3"),
        C64KeyDef(48, "F5"), C64KeyDef(64, "F7"),
        C64KeyDef(65, "SPACE", width: 5.0),
    ],
]

// MARK: - Keyboard View

struct C64KeyboardView: View {

    let controller: EmulatorController
    @State private var activeModifiers: Set<Int> = []

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<keyboardRows.count, id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    ForEach(keyboardRows[rowIndex]) { key in
                        C64KeyButton(
                            key: key,
                            isActive: activeModifiers.contains(key.id),
                            onPress: { pressKey(key) },
                            onRelease: { releaseKey(key) }
                        )
                    }
                }
            }
        }
        .padding(4)
    }

    private func pressKey(_ key: C64KeyDef) {
        let keyboard = controller.emu.keyboard!

        if key.isModifier {
            // Toggle modifier
            if activeModifiers.contains(key.id) {
                activeModifiers.remove(key.id)
                keyboard.releaseKey(key.id)
            } else {
                activeModifiers.insert(key.id)
                keyboard.pressKey(key.id)
            }
        } else {
            keyboard.pressKey(key.id)
        }
    }

    private func releaseKey(_ key: C64KeyDef) {
        if !key.isModifier {
            let keyboard = controller.emu.keyboard!
            keyboard.releaseKey(key.id)

            // Auto-release modifiers after a non-modifier key press
            // (except SHIFT LOCK which is a toggle)
            for mod in activeModifiers where mod != 34 {
                keyboard.releaseKey(mod)
            }
            activeModifiers = activeModifiers.filter { $0 == 34 }
        }
    }
}

// MARK: - Key Button

struct C64KeyButton: View {

    let key: C64KeyDef
    let isActive: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        Text(key.label)
            .font(.system(size: keyFontSize, weight: .medium, design: .monospaced))
            .foregroundColor(isActive ? .black : .white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .frame(maxWidth: .infinity)
            .frame(minWidth: 0)
            .layoutPriority(Double(key.width))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPress()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onRelease()
                    }
            )
    }

    private var backgroundColor: Color {
        if isActive {
            return Color(white: 0.8)
        }
        if isPressed {
            return Color(white: 0.35)
        }
        if key.isModifier {
            return Color(white: 0.22)
        }
        return Color(white: 0.25)
    }

    private var keyFontSize: CGFloat {
        if key.label.count <= 1 { return 14 }
        if key.label.count <= 3 { return 11 }
        return 9
    }
}
