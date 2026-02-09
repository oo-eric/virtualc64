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

#pragma once

#include "Cartridge.h"
#include <atomic>

namespace vc64 {

class MidiCartridge final : public Cartridge {

    CartridgeTraits traits = {

        .type           = CartridgeType::MIDI_DATEL,
        .title          = "MIDI (Datel)",
        .needsExecution = true
    };

    virtual const CartridgeTraits &getCartridgeTraits() const override { return traits; }

private:

    //
    // ACIA registers
    //

    // Control register (written via $DE04)
    u8 controlReg = 0;

    // Status register (read via $DE06)
    u8 statusReg = 0;

    // RX data register (read via $DE07)
    u8 rxDataReg = 0;

    // Whether RDRF (Receive Data Register Full) is set
    bool rdrf = false;

    // Whether an IRQ is currently asserted
    bool irqAsserted = false;


    //
    // Lock-free SPSC ring buffer for MIDI bytes
    //

    static constexpr isize BUFFER_SIZE = 1024;
    u8 buffer[BUFFER_SIZE] = {};
    std::atomic<isize> head{0};  // Written by producer (CoreMIDI thread)
    std::atomic<isize> tail{0};  // Written by consumer (emulator thread)


    //
    // Initializing
    //

public:

    using Cartridge::Cartridge;


    //
    // Methods from CoreComponent
    //

public:

    MidiCartridge& operator= (const MidiCartridge& other) {

        Cartridge::operator=(other);

        CLONE(controlReg)
        CLONE(statusReg)
        CLONE(rxDataReg)
        CLONE(rdrf)
        CLONE(irqAsserted)

        return *this;
    }
    virtual void clone(const Cartridge &other) override { *this = (const MidiCartridge &)other; }

    template <class T>
    void serialize(T& worker)
    {
        if (isResetter(worker)) return;

        worker

        << controlReg
        << statusReg
        << rxDataReg
        << rdrf
        << irqAsserted;

    } CARTRIDGE_SERIALIZERS(serialize);

    void _didReset(bool hard) override;


    //
    // Accessing cartridge memory (ACIA registers at IO1: $DE00-$DEFF)
    //

public:

    u8 peekIO1(u16 addr) override;
    u8 spypeekIO1(u16 addr) const override;
    void pokeIO1(u16 addr, u8 value) override;


    //
    // Execution
    //

    void execute() override;


    //
    // Receiving MIDI data (thread-safe, called from CoreMIDI thread)
    //

    void receiveMidiByte(u8 byte);

private:

    bool bufferIsEmpty() const;
    bool bufferIsFull() const;
    bool readBuffer(u8 &byte);
    void clearBuffer();
};

}
