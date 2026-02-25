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
import MetalKit

struct MetalEmulatorView: UIViewRepresentable {

    let controller: EmulatorController

    func makeCoordinator() -> iOSRenderer {
        return iOSRenderer(emu: controller.emu)
    }

    func makeUIView(context: Context) -> KeyboardResponderView {

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let mtkView = MTKView()
        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60
        mtkView.autoResizeDrawable = true
        mtkView.contentMode = .scaleAspectFit
        mtkView.layer.isOpaque = true
        mtkView.backgroundColor = .black

        context.coordinator.setup(device: device, view: mtkView)

        // Wrap MTKView in a keyboard-responder container
        let container = KeyboardResponderView(keyboard: controller.emu.keyboard)
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mtkView)
        NSLayoutConstraint.activate([
            mtkView.topAnchor.constraint(equalTo: container.topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            mtkView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Boot the emulator after renderer is ready
        Task { @MainActor in
            controller.boot()
            controller.startAudio()
            controller.startMIDI()
        }

        return container
    }

    func updateUIView(_ uiView: KeyboardResponderView, context: Context) {
        // No dynamic updates needed
    }
}

// MARK: - Hardware Keyboard Support

/// Maps UIKit key codes to C64 key numbers (0-65)
private let keyCodeToC64: [UIKeyboardHIDUsage: Int] = [
    // Row 1: left-arrow, 1-0, +, -, pound, HOME, DEL
    .keyboardGraveAccentAndTilde: 0,    // ` → left arrow
    .keyboard1: 1,
    .keyboard2: 2,
    .keyboard3: 3,
    .keyboard4: 4,
    .keyboard5: 5,
    .keyboard6: 6,
    .keyboard7: 7,
    .keyboard8: 8,
    .keyboard9: 9,
    .keyboard0: 10,
    .keyboardEqualSign: 11,             // = → +
    .keyboardHyphen: 12,               // - → -
    .keyboardHome: 14,                 // Home → HOME
    .keyboardDeleteOrBackspace: 15,    // Backspace → DEL

    // Row 2: CTRL, Q-P, @, *, up-arrow
    .keyboardTab: 17,                  // Tab → CTRL
    .keyboardQ: 18,
    .keyboardW: 19,
    .keyboardE: 20,
    .keyboardR: 21,
    .keyboardT: 22,
    .keyboardY: 23,
    .keyboardU: 24,
    .keyboardI: 25,
    .keyboardO: 26,
    .keyboardP: 27,
    .keyboardOpenBracket: 28,          // [ → @
    .keyboardCloseBracket: 29,         // ] → *

    // Row 3: RUN/STOP, A-L, :, ;, =, RETURN
    .keyboardEscape: 33,              // Esc → RUN/STOP
    .keyboardA: 35,
    .keyboardS: 36,
    .keyboardD: 37,
    .keyboardF: 38,
    .keyboardG: 39,
    .keyboardH: 40,
    .keyboardJ: 41,
    .keyboardK: 42,
    .keyboardL: 43,
    .keyboardSemicolon: 45,           // ; → ;
    .keyboardQuote: 44,               // ' → :
    .keyboardBackslash: 46,           // \ → =
    .keyboardReturnOrEnter: 47,       // Return → RETURN

    // Row 4: C=, SHIFT, Z-M, comma, period, /, SHIFT, cursors
    .keyboardZ: 51,
    .keyboardX: 52,
    .keyboardC: 53,
    .keyboardV: 54,
    .keyboardB: 55,
    .keyboardN: 56,
    .keyboardM: 57,
    .keyboardComma: 58,
    .keyboardPeriod: 59,
    .keyboardSlash: 60,
    .keyboardRightArrow: 63,          // → cursor left/right
    .keyboardLeftArrow: 63,           // ← cursor left/right (+ shift handled below)
    .keyboardDownArrow: 62,           // ↓ cursor up/down
    .keyboardUpArrow: 62,             // ↑ cursor up/down (+ shift handled below)

    // Row 5: Function keys, SPACE
    .keyboardF1: 16,
    .keyboardF2: 16,                  // F2 → F1/F2 (+ shift)
    .keyboardF3: 32,
    .keyboardF4: 32,
    .keyboardF5: 48,
    .keyboardF6: 48,
    .keyboardF7: 64,
    .keyboardF8: 64,
    .keyboardSpacebar: 65,
]

/// Keys that need SHIFT held alongside them
private let needsShift: Set<UIKeyboardHIDUsage> = [
    .keyboardLeftArrow,
    .keyboardUpArrow,
    .keyboardF2,
    .keyboardF4,
    .keyboardF6,
    .keyboardF8,
]

/// UIView subclass that captures hardware keyboard events for the C64 emulator
class KeyboardResponderView: UIView {

    private let keyboard: KeyboardProxy

    // Track which keys are pressed to handle shift combos
    private var shiftHeld = false

    init(keyboard: KeyboardProxy) {
        self.keyboard = keyboard
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false

        for press in presses {
            guard let key = press.key else { continue }

            // Handle modifier keys
            switch key.keyCode {
            case .keyboardLeftShift, .keyboardRightShift:
                shiftHeld = true
                keyboard.pressKey(50) // left shift
                handled = true
                continue
            case .keyboardLeftAlt, .keyboardRightAlt:
                keyboard.pressKey(49) // commodore
                handled = true
                continue
            case .keyboardLeftControl, .keyboardRightControl:
                keyboard.pressKey(33) // run/stop
                handled = true
                continue
            default:
                break
            }

            if let c64Nr = keyCodeToC64[key.keyCode] {
                if needsShift.contains(key.keyCode) {
                    keyboard.pressKey(50) // shift
                }
                keyboard.pressKey(c64Nr)
                handled = true
            }
        }

        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false

        for press in presses {
            guard let key = press.key else { continue }

            switch key.keyCode {
            case .keyboardLeftShift, .keyboardRightShift:
                shiftHeld = false
                keyboard.releaseKey(50)
                handled = true
                continue
            case .keyboardLeftAlt, .keyboardRightAlt:
                keyboard.releaseKey(49)
                handled = true
                continue
            case .keyboardLeftControl, .keyboardRightControl:
                keyboard.releaseKey(33)
                handled = true
                continue
            default:
                break
            }

            if let c64Nr = keyCodeToC64[key.keyCode] {
                keyboard.releaseKey(c64Nr)
                if needsShift.contains(key.keyCode) && !shiftHeld {
                    keyboard.releaseKey(50) // release auto-shift
                }
                handled = true
            }
        }

        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        pressesEnded(presses, with: event)
    }
}
