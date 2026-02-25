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

import Metal
import MetalKit

/// Simplified Metal renderer for iOS that displays the C64 emulator texture.
/// This is a stripped-down version of the macOS Renderer, focused only on
/// rendering the emulator's video output without effects layers.
class iOSRenderer: NSObject, MTKViewDelegate {

    let emu: EmulatorProxy

    // Metal objects
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var emulatorTexture: MTLTexture!
    private var sampler: MTLSamplerState!

    // Vertex buffer for a fullscreen quad
    private var vertexBuffer: MTLBuffer!

    // Frame synchronization (triple buffering)
    private let semaphore = DispatchSemaphore(value: 3)

    // Texture dimensions from the emulator
    private let texWidth: Int
    private let texHeight: Int

    // Track frame numbers to detect duplicates
    private var prevNr: Int = 0

    init(emu: EmulatorProxy) {
        self.emu = emu
        self.texWidth = Int(Constants.texWidth)
        self.texHeight = Int(Constants.texHeight)
        super.init()
    }

    func setup(device: MTLDevice, view: MTKView) {

        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        buildTexture()
        buildSampler()
        buildVertexBuffer()
        buildPipeline(view: view)
    }

    // MARK: - Metal Setup

    private func buildTexture() {

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: texWidth,
            height: texHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        emulatorTexture = device.makeTexture(descriptor: desc)
    }

    private func buildSampler() {

        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.sAddressMode = .clampToZero
        desc.tAddressMode = .clampToZero
        sampler = device.makeSamplerState(descriptor: desc)
    }

    private func buildVertexBuffer() {

        // Allocate buffer for a fullscreen quad: 4 vertices * 4 floats (x, y, u, v)
        let bufferSize = 16 * MemoryLayout<Float>.size
        vertexBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        updateVertexBuffer()
    }

    private func updateVertexBuffer() {

        // PAL visible area within the 520x312 texture (matches macOS TextureRect.swift)
        let u0 = Float(104.0 / 520.0)
        let u1 = Float(487.0 / 520.0)
        let v0 = Float(16.0 / 312.0)
        let v1 = Float(299.0 / 312.0)

        let vertices: [Float] = [
            // x,    y,   u,   v
            -1.0,  1.0,  u0,  v0,   // top-left
             1.0,  1.0,  u1,  v0,   // top-right
            -1.0, -1.0,  u0,  v1,   // bottom-left
             1.0, -1.0,  u1,  v1,   // bottom-right
        ]

        memcpy(vertexBuffer.contents(), vertices, vertices.count * MemoryLayout<Float>.size)
    }

    private func buildPipeline(view: MTKView) {

        // Load the default Metal library
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to load Metal shader library")
        }

        // Use simple passthrough shaders
        guard let vertexFunc = library.makeFunction(name: "iosVertexShader"),
              let fragmentFunc = library.makeFunction(name: "iosFragmentShader") else {
            fatalError("Failed to load iOS shader functions")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragmentFunc
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create render pipeline: \(error)")
        }
    }

    // MARK: - Texture Update

    private func updateTexture() {

        var buffer: UnsafePointer<UInt32>!
        var nr = 0

        emu.videoPort.lockTexture()
        emu.videoPort.texture(&buffer, nr: &nr)

        if buffer != nil {
            let region = MTLRegionMake2D(0, 0, texWidth, texHeight)
            let bytesPerRow = 4 * texWidth
            emulatorTexture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: buffer,
                bytesPerRow: bytesPerRow
            )
        }

        prevNr = nr
        emu.videoPort.unlockTexture()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No action needed — the quad fills the view
    }

    func draw(in view: MTKView) {

        semaphore.wait()

        // Update the emulator texture with the latest frame
        updateTexture()

        // Wake the emulator to produce the next frame
        emu.wakeUp()

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else {
            semaphore.signal()
            return
        }

        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            semaphore.signal()
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(emulatorTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.semaphore.signal()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
