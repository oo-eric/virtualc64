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

#include "config.h"
#include "C64.h"

namespace vc64 {

void
MidiCartridge::_didReset(bool hard)
{
    controlReg = 0;
    statusReg = 0;
    rxDataReg = 0;
    rdrf = false;

    if (irqAsserted) {
        cpu.releaseIrqLine(INTSRC_EXP);
        irqAsserted = false;
    }

    clearBuffer();
}

u8
MidiCartridge::peekIO1(u16 addr)
{
    u8 offset = addr & 0xFF;

    switch (offset) {

        case 0x06: // Status register
        {
            u8 result = statusReg;
            return result;
        }

        case 0x07: // RX Data register
        {
            u8 result = rxDataReg;

            // Clear RDRF and release IRQ
            rdrf = false;
            statusReg &= ~0x01;

            if (irqAsserted) {
                cpu.releaseIrqLine(INTSRC_EXP);
                irqAsserted = false;
            }

            return result;
        }

        default:
            return 0;
    }
}

u8
MidiCartridge::spypeekIO1(u16 addr) const
{
    u8 offset = addr & 0xFF;

    switch (offset) {

        case 0x06: return statusReg;
        case 0x07: return rxDataReg;
        default:   return 0;
    }
}

void
MidiCartridge::pokeIO1(u16 addr, u8 value)
{
    u8 offset = addr & 0xFF;

    switch (offset) {

        case 0x04: // Control register
        {
            controlReg = value;

            if (value == 0x03) {

                // Master reset: clear status, release IRQ, clear buffer
                statusReg = 0x00;
                rdrf = false;

                if (irqAsserted) {
                    cpu.releaseIrqLine(INTSRC_EXP);
                    irqAsserted = false;
                }

                clearBuffer();

            } else {

                // Enable mode: set TDRE (Transmit Data Register Empty) bit
                statusReg = 0x02;
            }
            break;
        }

        case 0x05: // TX Data register (ignored — we don't send MIDI out)
            break;

        default:
            break;
    }
}

void
MidiCartridge::execute()
{
    // If RDRF is clear and there's data in the buffer, load next byte
    if (!rdrf) {

        u8 byte;
        if (readBuffer(byte)) {

            rxDataReg = byte;
            rdrf = true;
            statusReg |= 0x01; // Set RDRF bit

            // Assert IRQ
            if (!irqAsserted) {
                cpu.pullDownIrqLine(INTSRC_EXP);
                irqAsserted = true;
            }
        }
    }
}

void
MidiCartridge::receiveMidiByte(u8 byte)
{
    // Called from CoreMIDI thread — lock-free push to ring buffer
    isize h = head.load(std::memory_order_relaxed);
    isize nextH = (h + 1) % BUFFER_SIZE;

    if (nextH != tail.load(std::memory_order_acquire)) {
        buffer[h] = byte;
        head.store(nextH, std::memory_order_release);
    }
    // If buffer is full, drop the byte (MIDI flow control)
}

bool
MidiCartridge::bufferIsEmpty() const
{
    return head.load(std::memory_order_acquire) == tail.load(std::memory_order_acquire);
}

bool
MidiCartridge::bufferIsFull() const
{
    isize h = head.load(std::memory_order_acquire);
    return ((h + 1) % BUFFER_SIZE) == tail.load(std::memory_order_acquire);
}

bool
MidiCartridge::readBuffer(u8 &byte)
{
    isize t = tail.load(std::memory_order_relaxed);

    if (t == head.load(std::memory_order_acquire)) {
        return false; // Buffer empty
    }

    byte = buffer[t];
    tail.store((t + 1) % BUFFER_SIZE, std::memory_order_release);
    return true;
}

void
MidiCartridge::clearBuffer()
{
    head.store(0, std::memory_order_relaxed);
    tail.store(0, std::memory_order_relaxed);
}

}
