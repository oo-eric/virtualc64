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

import CoreMIDI

class MIDIController {

    // CoreMIDI client and input port
    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()

    // Reference to the expansion port proxy for sending MIDI bytes
    private weak var expansionPort: ExpansionPortProxy?

    // Whether the controller is currently active
    private(set) var active = false

    func start(expansionPort: ExpansionPortProxy) {

        guard !active else { return }
        self.expansionPort = expansionPort

        // Create MIDI client with notification handler
        let status = MIDIClientCreate(
            "VirtualC64 MIDI" as CFString,
            midiNotifyCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &midiClient
        )

        guard status == noErr else {
            print("MIDIController: Failed to create MIDI client (error \(status))")
            return
        }

        // Create input port with packet handler
        let portStatus = MIDIInputPortCreateWithBlock(
            midiClient,
            "VirtualC64 Input" as CFString,
            &inputPort
        ) { [weak self] packetList, _ in
            self?.handlePacketList(packetList)
        }

        guard portStatus == noErr else {
            print("MIDIController: Failed to create input port (error \(portStatus))")
            MIDIClientDispose(midiClient)
            return
        }

        connectAllSources()
        active = true
    }

    func stop() {

        guard active else { return }

        disconnectAllSources()
        MIDIPortDispose(inputPort)
        MIDIClientDispose(midiClient)

        expansionPort = nil
        active = false
    }

    // MARK: - Source management

    func connectAllSources() {

        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            let status = MIDIPortConnectSource(inputPort, source, nil)
            if status == noErr {
                print("MIDIController: Connected to source \(i)")
            }
        }
    }

    func disconnectAllSources() {

        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            MIDIPortDisconnectSource(inputPort, source)
        }
    }

    // MARK: - MIDI packet handling

    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {

        guard let port = expansionPort else { return }

        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {

            // Access packet data bytes via withUnsafePointer
            withUnsafePointer(to: &packet.data) { tuplePtr in
                tuplePtr.withMemoryRebound(to: UInt8.self, capacity: Int(packet.length)) { ptr in
                    for j in 0..<Int(packet.length) {
                        port.receiveMidiByte(ptr[j])
                    }
                }
            }

            packet = MIDIPacketNext(&packet).pointee
        }
    }

    deinit {
        if active { stop() }
    }
}

// Free function callback for MIDI notifications (hot-plug support)
private func midiNotifyCallback(
    _ notification: UnsafePointer<MIDINotification>,
    _ refCon: UnsafeMutableRawPointer?
) {
    guard notification.pointee.messageID == .msgSetupChanged else { return }
    guard let refCon = refCon else { return }

    let controller = Unmanaged<MIDIController>.fromOpaque(refCon).takeUnretainedValue()

    // Reconnect all sources on setup change (handles hot-plug)
    controller.disconnectAllSources()
    controller.connectAllSources()
}
