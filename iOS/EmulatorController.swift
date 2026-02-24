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

import Foundation
import Metal

@MainActor
class EmulatorController: ObservableObject {

    let emu: EmulatorProxy

    @Published var isRunning = false
    @Published var midiConnected = false

    private var midiController: MIDIController?
    private var audio: iOSAudio?

    init() {
        emu = EmulatorProxy()
    }

    func boot() {

        guard !isRunning else { return }

        // Install open-source ROMs
        emu.installOpenRoms()

        // Attach MIDI cartridge for Cynthcart
        emu.expansionport.attachMidiCartridge()

        // Launch the emulator with message callback
        let myself = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        try? emu.launch(myself) { (ptr, msg: Message) in
            let me = Unmanaged<EmulatorController>.fromOpaque(ptr!).takeUnretainedValue()
            Task { @MainActor in me.processMessage(msg) }
        }

        // Power on and run
        try? emu.powerOn()
        try? emu.run()

        isRunning = true
    }

    func loadCynthcart() {

        guard let url = Bundle.main.url(forResource: "cynthcart2.0", withExtension: "prg") else {
            print("EmulatorController: cynthcart2.0.prg not found in bundle")
            return
        }

        do {
            let file = try MediaFileProxy.make(with: url)
            let volume = try FileSystemProxy.make(with: file)
            try emu.flash(volume, item: 0)
            emu.keyboard.autoType("run\n")
        } catch {
            print("EmulatorController: Failed to load Cynthcart: \(error)")
        }
    }

    func startAudio() {
        audio = iOSAudio(emu: emu)
        audio?.start()
    }

    func startMIDI() {
        midiController = MIDIController()
        midiController?.start(expansionPort: emu.expansionport)
        midiConnected = (midiController?.active == true)
    }

    func shutdown() {
        audio?.stop()
        midiController?.stop()

        if isRunning {
            emu.halt()
            isRunning = false
        }
    }

    private func processMessage(_ msg: Message) {

        switch msg.type {

        case .POWER:
            if msg.value != 0 {
                // Emulator just powered on — load Cynthcart after a short delay
                // to let the C64 boot sequence complete
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    self.loadCynthcart()
                }
            }

        default:
            break
        }
    }

    deinit {
        // Note: deinit won't be called on @MainActor but cleanup is in shutdown()
    }
}
