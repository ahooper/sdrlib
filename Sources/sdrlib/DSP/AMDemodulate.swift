//
//  AMDemodulate.swift
//  
//
//  Created by Andy Hooper on 2020-05-05.
//

import Accelerate

public class AMDemodulate: Buffered<ComplexSamples,RealSamples> {
    let factor:Float
    
    public init(_ name:String, _ source:BufferedSource<Input>?,
         factor:Float=1) {
        self.factor = factor
        super.init(name, source)
    }
}


public class AMEnvDemodulate: AMDemodulate {
    
    public init(source:BufferedSource<Input>?,
         factor:Float=1) {
        super.init("AMEnvDemodulate", source, factor:factor)
    }
    
    override public func process(_ x:ComplexSamples, _ out:inout RealSamples) {
        let inCount = x.count
        out.resize(inCount) // output same size as input
        if inCount == 0 { return }

        var xmean = ComplexSamples.zero // input average
        x.withUnsafePointers { real, imag in
            vDSP_meanv(real, 1, &xmean.real, vDSP_Length(inCount))
            vDSP_meanv(imag, 1, &xmean.imag, vDSP_Length(inCount))
        }
        
        var osum = Float.zero
        for i in 0..<inCount {
            let m = (x[i] - xmean).modulus() / factor   // envelope
            out[i] = m
            osum += m
        }
        
        var osub = -(osum / Float(inCount)) // output average
        out.real.withUnsafeMutableBufferPointer { obp in
            vDSP_vsadd(obp.baseAddress!, 1, &osub, obp.baseAddress!, 1, vDSP_Length(inCount))
        }
        
        //out.real.forEach { print(String(format: "%.3f", $0), terminator: " ")}; print()
        //print(osub, out.real[0])
    }
}


public class AMEnvDemodulateX: AMDemodulate {
    
    public init(source:BufferedSource<Input>?,
         factor:Float=1) {
        super.init("AMEnvDemodulateX", source, factor:factor)
    }
    
    override func process(_ x:ComplexSamples, _ out:inout RealSamples) {
        let inCount = x.count
        out.resize(inCount) // output same size as input
        if inCount == 0 { return }
        for i in 0..<inCount {
            // envelope
            out[i] = x[i].modulus() / factor
            //print(String(format:"%d %.3f", i, out[i]))
        }
        //out.real.forEach { print(String(format: "%.3f", $0), terminator: " ")}; print()
        //print(out.real[0])
    }
}

#if false
public class AMSyncDemodulate: AMDemodulate {
    let osc:Mixer

    init(source:BufferedSource<Input>?,
         factor:Float=1) {
        osc = Mixer(source: source!, signalHz: 0, pllErrorEstimator: { y in
            (y.conjugate()).argument()
        })
        super.init("AMSyncDemodulate", source, factor:factor)
    }
    
    override public func process(_ x:ComplexSamples, _ out:inout RealSamples) {
        let inCount = x.count
        out.resize(inCount) // output same size as input
        if inCount == 0 { return }
        assert(osc.produceBuffer.count == inCount)
        for i in 0..<inCount {
            out[i] = (x[i] * osc.produceBuffer[i].conjugate()).magnitude / factor
        }
    }
}

public class AMCostasDemodulate:AMDemodulate {
    let osc:PLL

    public init(source:BufferedSource<Input>?,
         factor:Float=1) {
        osc = PLL(source: source, signalHz: 0, errorEstimator: { y in
            let v = y.conjugate()
            return v.imag * (v.real > 0 ? 1 : -1)
        })
        super.init("AMCostasDemodulate", source, factor:factor)
    }
    
    override public func process(_ x:ComplexSamples, _ out:inout RealSamples) {
        let inCount = x.count
        out.resize(inCount) // output same size as input
        if inCount == 0 { return }
        assert(osc.produceBuffer.count == inCount)
        for i in 0..<inCount {
            out[i] = (x[i] * osc.produceBuffer[i].conjugate()).real / factor
        }
    }
}
#endif
