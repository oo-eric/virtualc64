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

struct ContentView: View {

    @EnvironmentObject var controller: EmulatorController

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let keyboardHeight = isLandscape
                ? geometry.size.height * 0.45
                : geometry.size.height * 0.35

            VStack(spacing: 0) {
                // C64 emulator screen
                MetalEmulatorView(controller: controller)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)

                // MIDI status bar
                HStack {
                    Circle()
                        .fill(controller.midiConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(controller.midiConnected ? "MIDI Connected" : "MIDI: No devices")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.8))

                // C64 virtual keyboard
                C64KeyboardView(controller: controller)
                    .frame(height: keyboardHeight)
                    .background(Color(white: 0.15))
            }
            .background(Color.black)
            .ignoresSafeArea(.keyboard)
        }
    }
}
