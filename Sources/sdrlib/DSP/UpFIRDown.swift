//
//  UpFIRDown.swift
//  SimpleSDR3
//
//  Resampler.h from https://code.google.com/archive/p/upfirdn/
//  https://apps.dtic.mil/dtic/tr/fulltext/u2/a393274.pdf
//  https://www.ece.ucsb.edu/Faculty/Rabiner/ece259/Reprints/179_interpolation_decimation.pdf
//
//  Created by Andy Hooper on 2019-12-15.
//  Copyright © 2019 Andy Hooper. All rights reserved.
//

class UpFIRDown<Samples:DSPSamples>: Buffered<Samples,Samples> {
    let up, down, Q, Qminus1:Int
    var polyphase:[[Float]]
    var p, offset:Int
    private var overlap:Samples

    init(source:BufferedSource<Input>?,
         _ upRate:Int,
         _ coefficients:[Float],
         _ downRate:Int) {
        precondition(upRate >= 1, "UpFIRDown interpolation factor must be >= 1")
        precondition(downRate >= 1, "UpFIRDown decimation factor must be >= 1")
        precondition(coefficients.count >= 1, "UpFIRDown FIR filter coefficients must not be empty")
        
        // reduce rates by greatest common divisor
        let c = UpFIRDown.gcd(upRate, downRate)
        up = upRate / c
        down = downRate / c
        
        // transpose prototype coefficients into polyphase bank
        polyphase = FIRKernel.polyphaseBank(up, coefficients, scale:Float(up))
        //for i in 0..<polyphase.count { print(i,polyphase[i]) }
        Q = polyphase[0].count  // length of sub-filters
        Qminus1 = Q - 1
        print("UpFIRDown", "up", up, "down", down, "Q", Q)

        p = 0
        offset = 0
        overlap = Samples(repeating:Samples.zero, count:Qminus1*2)
        super.init("UpFIRDown", source)
    }
    
    init(source:BufferedSource<Input>?,
         _ upRate:Int,
         _ downRate:Int,
         _ filterSemiLength:Int=12,
         _ normalizedTransitionFrequency:Float=0.5,
         windowFunction:WindowFunction.Function=WindowFunction.blackman) {
        precondition(upRate >= 1, "UpFIRDown interpolation factor must be >= 1")
        precondition(downRate >= 1, "UpFIRDown decimation factor must be >= 1")
        precondition(filterSemiLength >= 1, "UpFIRDown FIR filter coefficients must not be empty")
        precondition(normalizedTransitionFrequency <= 0.5 && normalizedTransitionFrequency > 0.0,
                     "UpFIRDown transition frequency out of range (0, 0.5)")
        
        // reduce rates by greatest common divisor
        let c = UpFIRDown.gcd(upRate, downRate)
        up = upRate / c
        down = downRate / c
        /* https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.resample_poly.html
         "... the FIR filter is applied after the upsampling step, so it should be
         designed to operate on a signal at a sampling frequency higher than the original
         by a factor of up//gcd(up, down). ... it is best to pass a symmetric filter
         with an odd number of samples if, as is usually the case, a zero-phase filter is desired."
         https://www.mathworks.com/help/signal/ref/resample.html#mw_7adbf990-9b5e-4677-ac50-8997f886114c
         */
        let maxUpDown = max(up,down)
        let coefficients = FIRKernel.sincKernel(filterLength: 2*filterSemiLength*maxUpDown,
                                                normalizedTransitionFrequency:
                                                            normalizedTransitionFrequency/Float(maxUpDown),
                                                highNotLowPass: false,
                                                windowFunction: windowFunction)
        // The ideal antialiasing filter has normalized cutoff frequency fc = π/max(p,q) rad/sample and gain p.
        // The filter order is 2 × n × max(p,q).
        // https://www.mathworks.com/help/signal/ref/resample.html#mw_7adbf990-9b5e-4677-ac50-8997f886114c
        // https://www.mathworks.com/help/signal/examples/resampling-uniformly-sampled-signals.html

        // transpose prototype coefficients into polyphase bank
        polyphase = FIRKernel.polyphaseBank(up, coefficients, scale:Float(up))
        Q = polyphase[0].count  // length of sub-filters
        Qminus1 = Q - 1
        print("UpFIRDown", "up", up, "down", down, "Q", Q)

        p = 0
        offset = 0
        overlap = Samples(repeating:Samples.zero, count:Qminus1*2)
        super.init("UpFIRDown", source)
    }

    /// Compute greatest common divisor of two integers by Euclidean algorithm
    // https://en.wikipedia.org/wiki/Euclidean_algorithm
    public static func gcd(_ a:Int, _ b:Int)->Int {
        var va=a, vb=b, t:Int
        while vb != 0 {
            t = vb
            vb = va % vb
            va = t
        }
        //print("gcd",a,b,va)
        return va
    }

    override public func sampleFrequency() -> Double {
        return source!.sampleFrequency() * Double(up) / Double(down)
    }
    
    func outputCount(_ inputCount:Int)->Int {
        let np = inputCount * up
        let oc = np / down
               + ((p + up * offset) < (np % down) ? 1 : 0)
        //print("UpFIRDown", "outputCount", inputCount, p, offset, oc)
        return oc
    }
    
    override public func process(_ x:Input, _ output:inout Output) {
        let inCount = x.count,
            outCount = outputCount(inCount)
        output.resize(outCount)
        if inCount == 0 { return }
        var y = 0,          // output index
            i = offset      // last input index to form part of that output
        if i < Qminus1 {
            // will need to draw from the state buffer
            overlap.replaceSubrange(Qminus1..<overlap.count, with:x, 0..<min(Qminus1,inCount))
        }
        while i < inCount {
            //print(p, "y(\(y))", terminator:"")
            if i < Qminus1 {
                // need to draw from the state buffer
                output[y] = overlap.weightedSum(at:i, polyphase[p])
            } else {
                output[y] = x.weightedSum(at:i-Qminus1, polyphase[p])
            }
            y += 1
            p += down
            let adv = p / up
            i += adv
            p %= up
        }
        offset = i - inCount

        let retain = Qminus1 - inCount // amount of state buffer to retain
        if retain > 0 {
            // for inCount smaller than state buffer, copy end of buffer
            // to beginning:
            overlap.removeSubrange(0..<(Qminus1-retain))
            // Then, copy the entire (short) input to end of buffer
            overlap.append(x)
        } else {
            // just copy last input samples into state buffer
            overlap.replaceSubrange(0..<Qminus1, with:x, (inCount-Qminus1)..<inCount)
        }
        //print("UpFIRDown", "phase", p, "offset", offset, "retain", retain)//, overlap.prefix(Qminus1))
    }

}
