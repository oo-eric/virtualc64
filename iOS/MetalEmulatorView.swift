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

    func makeUIView(context: Context) -> MTKView {

        let mtkView = MTKView()

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60
        mtkView.autoResizeDrawable = true
        mtkView.contentMode = .scaleAspectFit

        // Transparent background so the black VStack shows through
        mtkView.layer.isOpaque = true
        mtkView.backgroundColor = .black

        // Initialize the renderer with the Metal device
        context.coordinator.setup(device: device, view: mtkView)

        // Boot the emulator after renderer is ready
        Task { @MainActor in
            controller.boot()
            controller.startAudio()
            controller.startMIDI()
        }

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // No dynamic updates needed
    }
}
