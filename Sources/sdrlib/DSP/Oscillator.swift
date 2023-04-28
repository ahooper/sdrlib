//
//  Oscillator.swift
//  SimpleSDR3
//
//  Created by Andy Hooper on 2020-01-22.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

fileprivate let TABLE_SIZE = 1024

import func CoreFoundation.tanhf

public struct OscillatorLookup<Element:DSPScalar>: IteratorProtocol {
    let table: [Element]
    var phase, step: Float // 0..<TABLE_SIZE corresponds to one cycle
            // could use fixed point for slightly greater accuracy and speed
    let RADIANS_TO_INDEX: Float = Float(TABLE_SIZE) / (2 * Float.pi)
    let INDEX_TO_RADIANS: Float = (2 * Float.pi) / Float(TABLE_SIZE)

    public init(signalHz:Double, sampleHz:Double, level:Float=1.0) {
        precondition(sampleHz >= signalHz * 2, "sampleHz must be >= 2 * signalHz")
        table = (0..<TABLE_SIZE).map{Element.oscillator(2*Float.pi*Float($0)/Float(TABLE_SIZE), level)}
        phase = 0
        step = Float(TABLE_SIZE) * Float(signalHz / sampleHz)
    }

    public mutating func next()->Element? {
        // this infinite sequence never returns nil, but Optional is
        // required for protocol conformance
        while phase < -0.5 {
            phase += Float(TABLE_SIZE)
        }
        while (phase+0.5) >= Float(TABLE_SIZE) {
            phase -= Float(TABLE_SIZE)
        }
        let v = table[Int(phase+0.5)]
        phase += step
        return v
    }
    
    public mutating func setFrequency(_ f:Float) {
        step = RADIANS_TO_INDEX * f
    }
    
    public mutating func setPhase(_ p:Float) {
        phase = RADIANS_TO_INDEX * p
    }
    
    public mutating func adjustFrequency(_ d:Float) {
        step += RADIANS_TO_INDEX * d
    }
    
    public mutating func adjustPhase(_ d:Float) {
        phase += RADIANS_TO_INDEX * d
    }
    
    public func getPhase()->Float {
        return INDEX_TO_RADIANS * phase
    }
    
    public func getFrequency()->Float {
        let f = INDEX_TO_RADIANS * step
        return (f > Float.pi) ? (f - 2*Float.pi) : f
    }

}

public class Oscillator<Output:DSPSamples>: BufferedSource<Output> {
    let signalHz, sampleHz: Double
    var level:Float
    private var osc: OscillatorLookup<Output.Element>

    public init(signalHz:Double, sampleHz:Double, level:Float=1.0) {
        precondition(sampleHz >= signalHz * 2, "sampleHz must be >= 2 * signalHz")
        self.signalHz = signalHz
        self.sampleHz = sampleHz
        self.level = level
        osc = OscillatorLookup<Output.Element>(signalHz: signalHz, sampleHz: sampleHz, level: level)
        bufferSize = Int(sampleHz / signalHz * 10 + 0.5)
        super.init(name: "Oscillator")
    }

    public func next()->Output.Element? {
        // this infinite sequence never returns nil, but Optional is
        // required for protocol conformance
        osc.next()
    }

    public func generate(_ numSamples:Int) {
        assert(outputBuffer.isEmpty)
        outputBuffer.reserveCapacity(numSamples)
        // passing the output buffer as an argument, instead of accessing the class property,
        // reduces calls to Swift's exclusive access checks (swift_beginAccess/swift_endAccess)
        generate(numSamples, &outputBuffer)
        produce(clear: true)
    }
    
    func generate(_ numSamples: Int, _ output: inout Output) {
        for _ in 0..<numSamples {
            let n:Output.Element = osc.next()!
            output.append(n)
        }
    }
    
    public var bufferSize: Int
    
    override public func sampleFrequency() -> Double {
        return Double(sampleHz)
    }
    
    public func setFrequency(_ d:Float) {
        osc.setFrequency(d) //TODO / sampleHz
    }
    
    public func setPhase(_ d:Float) {
        osc.setPhase(d)
    }
    
    public func adjustFrequency(_ d:Float) {
        osc.adjustFrequency(d) //TODO / sampleHz
    }
    
    public func adjustPhase(_ d:Float) {
        osc.adjustPhase(d)
    }
    
    public func getPhase()->Float {
        osc.getPhase()
    }
    
    public func getFrequency()->Float {
        osc.getFrequency() //TODO * sampleHz
    }

}

public class OscillatorPrecise<Output:DSPSamples>: BufferedSource<Output> {
    let signalHz, sampleHz: Double
    var level:Float
    var phase, step: Float
    
    public init(signalHz:Double, sampleHz:Double, level:Float=1.0) {
        precondition(sampleHz >= signalHz * 2, "sampleHz must be >= 2 * signalHz")
        self.signalHz = signalHz
        self.sampleHz = sampleHz
        self.level = level
        phase = 0
        step = 2*Float.pi*Float(signalHz / sampleHz)
        bufferSize = Int(sampleHz / signalHz * 10 + 0.5)
        super.init(name: "OscillatorPrecise")
    }

    public func next()->Output.Element? {
        // this infinite sequence never returns nil, but Optional is
        // required for protocol conformance
        while phase < -Float.pi {
            phase += Float.pi
        }
        while phase >= Float.pi {
            phase -= Float.pi
        }
        let v = Output.Element.oscillator(phase, level)
        phase += step
        return v
    }

    public func generate(_ numSamples:Int) {
        assert(outputBuffer.isEmpty)
        outputBuffer.reserveCapacity(numSamples)
        // passing the output buffer as an argument, instead of accessing the class property,
        // reduces calls to Swift's exclusive access checks (swift_beginAccess/swift_endAccess)
        generate(numSamples, &outputBuffer)
        produce(clear: true)
    }
    
    public func generate(_ numSamples: Int, _ output: inout Output) {
        for _ in 0..<numSamples {
            let n:Output.Element = next()!
            output.append(n)
        }
    }
    
    var bufferSize: Int
    
    override public func sampleFrequency() -> Double {
        return Double(sampleHz)
    }
      
    public func setFrequency(_ f:Float) {
        step = f
    }
    
    public func setPhase(_ p:Float) {
        phase = p
    }
    
    public func adjustFrequency(_ d:Float) {
        step += d
    }
    
    public func adjustPhase(_ d:Float) {
        phase += d
    }
    
    public func getPhase()->Float {
        return phase
    }
    
    public func getFrequency()->Float {
        let f = step
        return (f > Float.pi) ? (f - 2*Float.pi) : f
    }

}

public class Mixer: Buffered<ComplexSamples,ComplexSamples> {
    var osc: OscillatorLookup<Output.Element>
    public typealias ErrorEstimator = (Input.Element,Output.Element)->Float
    let errorEstimator: ErrorEstimator?
    var alpha, beta: Float // control loop bandwidth
    public static let DEFAULT_LOOP_BANDWIDTH = Float(0.1)

    public init(source:BufferedSource<Input>,
         signalHz:Double,
         level:Float=1.0,
         controlLoopBandwidth:Float=DEFAULT_LOOP_BANDWIDTH,
         errorEstimator: ErrorEstimator? = nil) {
        let sampleHz = source.sampleFrequency()
        osc = OscillatorLookup(signalHz: signalHz, sampleHz: sampleHz, level: level)
        self.errorEstimator = errorEstimator
        alpha = controlLoopBandwidth
        beta = alpha.squareRoot()
        super.init("Mixer", source)
    }

    public func setLoopBandwidth(_ loopBandwidth: Float) {
        self.alpha = loopBandwidth
        self.beta = self.alpha.squareRoot()
    }

    override public func process(_ x:Input, _ output:inout Output) {
        let inCount = x.count
        output.resize(inCount) // output same size as input
        if inCount == 0 { return }
        output.removeAll()
        if let errorEstimator = errorEstimator {
            for v in x {
                let o = osc.next()!
                output.append(v * o)
                let e = errorEstimator(v, o)
                osc.adjustFrequency(e * alpha)
                osc.adjustPhase(e * beta)
            }
        } else {
            for v in x {
                let o = osc.next()!
                output.append(v * o)
            }
        }
    }

}

struct tanhLookup {
    static let table = (0..<TABLE_SIZE).map{i in tanhf(Float(i)/Float(TABLE_SIZE-1)*4-2)}

    public func tanh(_ x:Float)->Float {
        if x > 2 { return 1 }
        if x < -2 { return -1 }
        let index = Int(Float(TABLE_SIZE / 2) + Float(TABLE_SIZE / 4) * x)
        return tanhLookup.table[index]
    }
}

public class CostasLoop: Buffered<ComplexSamples,ComplexSamples> {
    var osc: OscillatorLookup<Output.Element>
    public typealias ErrorEstimator = (Output.Element)->Float
    let errorEstimator: ErrorEstimator
    var alpha, beta: Float // control loop bandwidth
    public static let DEFAULT_LOOP_BANDWIDTH = Float(0.1)
    static let tanh = tanhLookup()
    var noise: Float
    var scopeData: ScopeData?

    public init(source:BufferedSource<Input>,
         signalHz:Double,
         level:Float=1.0,
         controlLoopBandwidth:Float=DEFAULT_LOOP_BANDWIDTH,
         errorEstimator: @escaping ErrorEstimator) {
        let sampleHz = source.sampleFrequency()
        osc = OscillatorLookup(signalHz: signalHz, sampleHz: sampleHz, level: level)
        self.errorEstimator = errorEstimator
        alpha = controlLoopBandwidth
        beta = alpha.squareRoot()
        noise = 1
        scopeData = nil
        super.init("CostasLoop", source)
    }

    public func setLoopBandwidth(_ loopBandwidth: Float) {
        self.alpha = loopBandwidth
        self.beta = self.alpha.squareRoot()
    }

    public static func errorEstimator2(_ o:Output.Element)->Float {
        return o.real * o.imag
    }
    
    public func errorEstimatorSNR2(_ o:Output.Element)->Float {
        let snr = o.modulus() / noise
        return CostasLoop.tanh.tanh(snr * o.real) * o.imag
    }
    
    public static func errorEstimator2s(_ o:Output.Element)->Float {
        let snr = o.modulus()
        return CostasLoop.tanh.tanh(snr * o.real) * o.imag
    }

    override public func process(_ x:Input, _ output:inout Output) {
        let inCount = x.count
        output.resize(inCount) // output same size as input
        if inCount == 0 { return }
        output.removeAll()
        for v in x {
            let o = osc.next()!, vo = v * o
            output.append(vo)
            let e = errorEstimator(vo)
            osc.adjustFrequency(e * alpha)
            osc.adjustPhase(e * beta)
            scopeData?.sample([osc.getFrequency(), osc.getPhase()/(2*Float.pi), e])
        }
    }

}
