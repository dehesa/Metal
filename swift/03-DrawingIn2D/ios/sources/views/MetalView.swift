import UIKit
import Metal
import simd

final class MetalView : UIView {
    
    // MARK: Definitions
    
    private struct Vertex {
        var position : float4
        var color : float4
    }
    
    override static func layerClass() -> AnyClass { return CAMetalLayer.self }
    
    // MARK: Properties
    
    private var metalLayer : CAMetalLayer { return self.layer as! CAMetalLayer }
    private let device : MTLDevice
    private var pipeline : MTLRenderPipelineState
    private var commandQueue : MTLCommandQueue
    private var vertexBuffer : MTLBuffer
    private var displayLink : CADisplayLink?
    
    // MARK: Functionality
    
    required init?(coder aDecoder: NSCoder) {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.newCommandQueue()
        
        // Setup buffer (non-transient)
        let vertices = [    // Coordinates defined in clip space: [-1,+1]
            Vertex(position: [ 0,    0.5, 0, 1], color: [1,0,0,1]),
            Vertex(position: [-0.5, -0.5, 0, 1], color: [0,1,0,1]),
            Vertex(position: [ 0.5, -0.5, 0, 1], color: [0,0,1,1])
        ]
        vertexBuffer = device.newBufferWithBytes(vertices, length: sizeof(Vertex) * vertices.count, options: .CPUCacheModeDefaultCache)
        
        // Setup shader library
        guard let library = device.newDefaultLibrary() else { fatalError("No default library") }
        guard let vertexFunc: MTLFunction   = library.newFunctionWithName("vertex_main"),
              let fragmentFunc: MTLFunction = library.newFunctionWithName("fragment_main") else { fatalError("Shader not found") }
        
        // Setup pipeline (non-transient)
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = .BGRA8Unorm   // 8-bit unsigned integer [0, 255]
        pipeline = try! device.newRenderPipelineStateWithDescriptor(pipelineDescriptor)
        
        super.init(coder: aDecoder)
        
        // Setup Core Animation related functionality
        self.metalLayer.device = device
        self.metalLayer.pixelFormat = .BGRA8Unorm
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        if let window = self.window {
            self.metalLayer.contentsScale = window.screen.nativeScale
            
            if let dl = self.displayLink { dl.invalidate() }
            self.displayLink = CADisplayLink(target: self, selector: "displayLinkDidFire:")
            self.displayLink!.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        } else {
            self.displayLink?.invalidate()
            self.displayLink = nil
        }
    }
    
    func displayLinkDidFire(displayLink: CADisplayLink) {
        redraw()
    }
    
    private func redraw() {
        guard let drawable = self.metalLayer.nextDrawable() else { return }
        let framebufferTexture = drawable.texture
        
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = framebufferTexture
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        renderPass.colorAttachments[0].loadAction = .Clear
        renderPass.colorAttachments[0].storeAction = .Store
        
        // Setup Command Buffers (transient)
        let cmdBuffer = self.commandQueue.commandBuffer()
        
        // Setup Command Encoders (transient)
        let encoder = cmdBuffer.renderCommandEncoderWithDescriptor(renderPass)
        encoder.setRenderPipelineState(self.pipeline)
        encoder.setVertexBuffer(self.vertexBuffer, offset: 0, atIndex: 0)
        encoder.drawPrimitives(.Triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        
        // Present drawable is a convenience completion block that will get executed once your command buffer finishes, and will output the final texture to screen.
        cmdBuffer.presentDrawable(drawable)
        cmdBuffer.commit()
    }
}
