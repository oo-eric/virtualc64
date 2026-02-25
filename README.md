# VirtualC64

A Commodore 64 emulator for macOS and iOS, built on a cycle-accurate C++20 emulation engine with Metal rendering.

## Targets

- **VirtualC64** — Full-featured macOS emulator with shader effects, inspector, and gamepad support
- **CynthcartApp** — iOS app focused on running [Cynthcart](https://www.cynthcart.com), a C64 MIDI synthesizer
- **Headless** — CLI tool for regression testing

## Architecture

Three-layer design with strict separation:

1. **Core** (`Core/`) — Pure C++20 emulation engine. CPU (Peddle), VICII, SID, CIA, memory, drives, cartridges. No platform dependencies.
2. **ObjC++ Proxy** (`ObjCProxy/`) — Bridge layer. `EmulatorProxy.h/.mm` wraps the C++ API for Swift consumption.
3. **GUI** (`GUI/`) — Swift/AppKit macOS frontend with Metal rendering, preferences, and debugging tools.
4. **iOS** (`iOS/`) — Swift/SwiftUI iOS frontend with Metal rendering, on-screen C64 keyboard, and MIDI support.

The Core and ObjC++ Proxy are shared across all targets.

## Building

### Requirements

- macOS 13.3+
- Xcode with Metal Toolchain
- C++20

Metal Toolchain may need manual install:

```sh
xcodebuild -downloadComponent MetalToolchain
```

### macOS

```sh
xcodebuild -scheme VirtualC64 build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### iOS (Simulator)

```sh
xcodebuild -target CynthcartApp -sdk iphonesimulator -arch arm64 build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### CMake (Core only, cross-platform)

```sh
mkdir build && cd build && cmake .. && make
```

## MIDI Support

Both the macOS and iOS targets include a virtual DATEL MIDI cartridge for use with Cynthcart. MIDI input from CoreMIDI devices is fed through a lock-free ring buffer into the emulated ACIA chip, which triggers IRQs for the C64 to read.

- Connects to any class-compliant USB MIDI keyboard
- Hot-plug support with automatic device reconnection
- Works in the iOS Simulator using MIDI devices connected to the host Mac
- Physical iOS devices require a powered USB hub (iPhone/iPad don't supply enough bus power for most keyboards)

## License

Dual-licensed under [GPL-3.0-or-later](https://www.gnu.org/licenses/gpl-3.0.html) OR [MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/).

Based on [VirtualC64](https://dirkwhoffmann.github.io/virtualc64) by Dirk W. Hoffmann.
