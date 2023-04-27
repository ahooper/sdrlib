//
//  AGC.swift
//  rspwwvb1
//
//  Created by Andy Hooper on 2023-04-21.
//

import Foundation

class AGC<Samples:DSPSamples>: Buffered<Samples,Samples> {
    
    var rate: Float         // the update rate of the loop.
    var reference: Float    // reference value to adjust signal power to.
    var gain: Float         // current gain
    var maxGain: Float      // maximum gain value (nan for unlimited)
    
    init(_ source:BufferedSource<Input>?,
         rate: Float = 1e-4,
         reference: Float = 1,
         gain: Float = 1,
         maxGain: Float = Float.nan) {
        self.rate = rate
        self.reference = reference
        self.gain = gain
        self.maxGain = maxGain
        super.init("AGC", source)
    }
    
    override func process(_ x:Samples, _ out:inout Samples) {
        let inCount = x.count
        out.resize(inCount) // output same size as input
        if inCount == 0 { return }

        for i in 0..<inCount {
            out[i] = x[i] * gain
            gain += rate * (reference - out[i].modulus())
            if gain > maxGain {
                gain = maxGain
            }
        }
    }

}
