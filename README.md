# VirtualC64 — MIDI Edition

A fork of [VirtualC64](https://dirkwhoffmann.github.io/virtualc64), Dirk W. Hoffmann's
cycle-accurate Commodore 64 emulator for macOS, extended with a **virtual DATEL MIDI
cartridge**. Plug in a real MIDI keyboard, attach the cartridge, and play the C64's SID
chip live — turning a 1982 breadbox into a three-voice synth you can actually perform on.
Ideal for driving [Cynthcart](https://www.paulslocum.com/cynthcart/) and other MIDI-aware
C64 software.

This branch (`midi`) contains the macOS implementation. The SwiftUI iOS port lives on the
`ios` branch.

## What this fork adds

- **Virtual DATEL MIDI interface** — a software model of the DATEL MIDI cartridge,
  emulating its ACIA UART so MIDI-aware C64 software sees a real interface.
- **Live CoreMIDI input** — connects to every MIDI source on the system and forwards
  incoming bytes to the emulated C64.
- **Hot-plug support** — MIDI devices connected or removed while running are picked up
  automatically (via the CoreMIDI setup-changed notification).
- **Menu toggle** — enable/disable MIDI from the Cartridge menu; the menu item reflects the
  current attach state.

## How it works

```text
MIDI keyboard → CoreMIDI → MIDIController (Swift) → ExpansionPortProxy (ObjC++)
             → MidiCartridge (C++) → ACIA registers → CPU IRQ → C64 reads MIDI bytes
```

- **`Core/Media/Cartridges/CustomCartridges/Midi.{h,cpp}`** — `MidiCartridge`, a `Cartridge`
  subclass modeling the ACIA. Incoming MIDI bytes land in a **lock-free SPSC ring buffer**
  (CoreMIDI thread produces, emulator thread consumes), so no locks sit on the audio path —
  the SID has waited 40+ years for its notes, it shouldn't have to wait on a mutex too.
- **`GUI/Input/MIDIController.swift`** — creates the CoreMIDI client and input port, connects
  to all sources, parses/logs incoming messages, and feeds raw bytes to the cartridge.
- The cartridge sets `.needsExecution = true`, so `execute()` runs every CPU cycle to drain
  the buffer, set the ACIA's RDRF status bit, and assert an IRQ when a byte is ready.

### ACIA register map (IO1, `$DE00`–`$DEFF`)

| Address | Register | Access |
| ------- | -------- | ------ |
| `$DE04` | Control  | write  |
| `$DE06` | Status   | read   |
| `$DE07` | RX data  | read   |

## Building

Open `VirtualC64.xcodeproj` and build the **VirtualC64** scheme. Requires macOS 13.3+, C++20,
and Xcode with the Metal Toolchain.

Without code signing:

```sh
xcodebuild -scheme VirtualC64 build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

The cross-platform core also builds with CMake:

```sh
mkdir build && cd build && cmake .. && make
```

## Using MIDI

1. Connect a MIDI keyboard (USB or interface).
2. Launch VirtualC64 and load your MIDI software (e.g. Cynthcart).
3. Choose **Cartridge → Attach MIDI (Datel)**. This attaches the virtual cartridge and starts
   CoreMIDI input. Selecting it again detaches and stops MIDI.
4. Play. Note on/off, CC, pitch bend, program change, and aftertouch are all received; MIDI
   activity is logged to the console for debugging.

## License

VirtualC64 is dual-licensed under **GPL-3.0-or-later OR MPL-2.0**. All additions in this fork
carry the same dual license. Copyright for the original emulator belongs to Dirk W. Hoffmann.
