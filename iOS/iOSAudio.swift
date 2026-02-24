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

import AVFoundation
import AudioToolbox

class iOSAudio {

    private let audioPort: AudioPortProxy
    private var audiounit: AUAudioUnit?
    private var running = false

    private let emu: EmulatorProxy

    init(emu: EmulatorProxy) {
        self.emu = emu
        self.audioPort = emu.audioPort
    }

    @MainActor
    func start() {

        guard !running else { return }

        // Configure audio session for iOS
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: session
            )
        } catch {
            print("iOSAudio: Failed to configure audio session: \(error)")
            return
        }

        // Create RemoteIO audio unit (iOS equivalent of DefaultOutput)
        let compDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        do {
            audiounit = try AUAudioUnit(componentDescription: compDesc)
        } catch {
            print("iOSAudio: Failed to create audio unit: \(error)")
            return
        }

        guard let audiounit = audiounit else { return }

        // Query hardware format
        let hardwareFormat = audiounit.outputBusses[0].format
        let channels = hardwareFormat.channelCount
        let sampleRate = hardwareFormat.sampleRate
        let stereo = channels > 1

        print("iOSAudio: Hardware format: \(sampleRate)Hz, \(channels)ch")

        // Tell the emulator about the sample rate
        emu.set(.HOST_SAMPLE_RATE, value: Int(sampleRate))

        // Configure render format
        let renderFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: stereo ? 2 : 1
        )

        do {
            try audiounit.inputBusses[0].setFormat(renderFormat!)
        } catch {
            print("iOSAudio: Failed to set render format: \(error)")
            return
        }

        // Capture audioPort for use in render callbacks (thread-safe C++ ring buffer)
        let port = self.audioPort

        // Register render callback
        if stereo {
            audiounit.outputProvider = { (
                actionFlags,
                timestamp,
                frameCount,
                inputBusNumber,
                inputDataList
            ) -> AUAudioUnitStatus in

                let bufferList = UnsafeMutableAudioBufferListPointer(inputDataList)

                if bufferList.count >= 2 {
                    guard let ptr1 = bufferList[0].mData?.assumingMemoryBound(to: Float.self),
                          let ptr2 = bufferList[1].mData?.assumingMemoryBound(to: Float.self) else {
                        return -1
                    }
                    port.copyStereo(ptr1, buffer2: ptr2, size: Int(frameCount))
                } else {
                    guard let ptr = bufferList[0].mData?.assumingMemoryBound(to: Float.self) else {
                        return -1
                    }
                    port.copyMono(ptr, size: Int(frameCount))
                }

                return noErr
            }
        } else {
            audiounit.outputProvider = { (
                actionFlags,
                timestamp,
                frameCount,
                inputBusNumber,
                inputDataList
            ) -> AUAudioUnitStatus in

                let bufferList = UnsafeMutableAudioBufferListPointer(inputDataList)
                guard let ptr = bufferList[0].mData?.assumingMemoryBound(to: Float.self) else {
                    return -1
                }
                port.copyMono(ptr, size: Int(frameCount))

                return noErr
            }
        }

        // Start
        do {
            try audiounit.allocateRenderResources()
            try audiounit.startHardware()
            running = true
            print("iOSAudio: Started (\(sampleRate)Hz, \(channels)ch)")
        } catch {
            print("iOSAudio: Failed to start: \(error)")
        }
    }

    func stop() {

        guard running else { return }

        audiounit?.stopHardware()
        running = false

        NotificationCenter.default.removeObserver(self)
        print("iOSAudio: Stopped")
    }

    // MARK: - Interruption Handling

    @objc private func handleInterruption(notification: Notification) {

        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("iOSAudio: Interruption began")

        case .ended:
            print("iOSAudio: Interruption ended")
            try? AVAudioSession.sharedInstance().setActive(true)

        @unknown default:
            break
        }
    }

    deinit {
        if running {
            audiounit?.stopHardware()
        }
    }
}
