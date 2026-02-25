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
    private var expansionPort: ExpansionPortProxy?

    // Whether the controller is currently active
    private(set) var active = false

    // Called when the number of connected sources changes
    var onSourcesChanged: ((Int) -> Void)?

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

        let sourceCount = MIDIGetNumberOfSources()
        print("MIDIController: Started (sources: \(sourceCount))")
        onSourcesChanged?(sourceCount)
    }

    func stop() {

        guard active else { return }

        disconnectAllSources()
        MIDIPortDispose(inputPort)
        MIDIClientDispose(midiClient)

        expansionPort = nil
        active = false

        print("MIDIController: Stopped")
    }

    // MARK: - Source management

    func connectAllSources() {

        let sourceCount = MIDIGetNumberOfSources()
        print("MIDIController: Connecting to \(sourceCount) source(s)")

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)

            // Log source name
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name)
            let sourceName = name?.takeRetainedValue() as String? ?? "Unknown"

            let status = MIDIPortConnectSource(inputPort, source, nil)
            if status == noErr {
                print("MIDIController: Connected to '\(sourceName)' (source \(i))")
            } else {
                print("MIDIController: Failed to connect to '\(sourceName)' (error \(status))")
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

        guard let port = expansionPort else {
            print("MIDIController: expansionPort is nil, dropping MIDI data")
            return
        }

        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {

            let length = Int(packet.length)

            withUnsafePointer(to: &packet.data) { tuplePtr in
                tuplePtr.withMemoryRebound(to: UInt8.self, capacity: length) { ptr in

                    logMidiBytes(ptr, length: length)

                    for j in 0..<length {
                        port.receiveMidiByte(ptr[j])
                    }
                }
            }

            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func logMidiBytes(_ ptr: UnsafePointer<UInt8>, length: Int) {

        var i = 0
        while i < length {
            let status = ptr[i]
            let msgType = status & 0xF0
            let channel = (status & 0x0F) + 1

            switch msgType {
            case 0x90 where i + 2 < length:
                let note = ptr[i + 1]
                let velocity = ptr[i + 2]
                if velocity > 0 {
                    print("MIDI: Note ON  ch=\(channel) note=\(note) vel=\(velocity)")
                } else {
                    print("MIDI: Note OFF ch=\(channel) note=\(note)")
                }
                i += 3

            case 0x80 where i + 2 < length:
                let note = ptr[i + 1]
                let velocity = ptr[i + 2]
                print("MIDI: Note OFF ch=\(channel) note=\(note) vel=\(velocity)")
                i += 3

            case 0xB0 where i + 2 < length:
                let cc = ptr[i + 1]
                let value = ptr[i + 2]
                print("MIDI: CC      ch=\(channel) cc=\(cc) value=\(value)")
                i += 3

            case 0xE0 where i + 2 < length:
                let lsb = ptr[i + 1]
                let msb = ptr[i + 2]
                let bend = (Int(msb) << 7 | Int(lsb)) - 8192
                print("MIDI: Pitch Bend ch=\(channel) value=\(bend)")
                i += 3

            case 0xC0 where i + 1 < length:
                let program = ptr[i + 1]
                print("MIDI: Program Change ch=\(channel) program=\(program)")
                i += 2

            case 0xD0 where i + 1 < length:
                let pressure = ptr[i + 1]
                print("MIDI: Ch Pressure ch=\(channel) pressure=\(pressure)")
                i += 2

            case 0xA0 where i + 2 < length:
                let note = ptr[i + 1]
                let pressure = ptr[i + 2]
                print("MIDI: Poly Pressure ch=\(channel) note=\(note) pressure=\(pressure)")
                i += 3

            case 0xF0:
                // System messages
                switch status {
                case 0xF8: break // Timing clock — skip silently (very frequent)
                case 0xFE: break // Active sensing — skip silently
                default:
                    let hex = String(format: "0x%02X", status)
                    print("MIDI: System \(hex)")
                }
                i += 1

            default:
                let hex = String(format: "0x%02X", status)
                print("MIDI: Unknown \(hex)")
                i += 1
            }
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

    print("MIDIController: MIDI setup changed, reconnecting sources")
    controller.disconnectAllSources()
    controller.connectAllSources()
    controller.onSourcesChanged?(MIDIGetNumberOfSources())
}
