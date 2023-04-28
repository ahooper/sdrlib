//
//  AutoGainControl.swift
//  SimpleSDR3
//
//  https://www.embedded.com/a-simple-way-to-add-agc-to-your-communications-receiver-design/
//  CubicSDR-0.2.5/src/modules/modem/ModemAnalog.cpp
//
//  Created by Andy Hooper on 2020-02-27.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import func CoreFoundation.log10

public class AutoGainControl<Samples:DSPSamples>: Buffered<Samples,Samples> {
    var gain:Float
    var isLocked:Bool
    var ceil, ceilMA, ceilMAA:Float

    public init(_ source:BufferedSource<Input>?, gain:Float=0.5) {
        self.gain = gain
        ceil = 1 / gain
        ceilMA = 1 / gain
        ceilMAA = 1 / gain
        isLocked = false
        super.init("AutoGainControl", source)
    }
    
    override public func process(_ x:Samples, _ out:inout Samples) {
        let inCount = x.count
        out.resize(inCount) // output same size as input
        if inCount == 0 { return }

        // advance moving averages
        if !isLocked {
            ceilMA = ceilMA + (ceil - ceilMA) * Float(0.025)
            ceilMAA = ceilMAA + (ceilMA - ceilMAA) * Float(0.025)
            ceil = 0
            for i in 0..<inCount {
                let mag = x[i].magnitude
                if mag > ceil { ceil = mag }
            }
            gain = 0.5 / Float(ceilMAA)
            //print("AutoGainControl", gain, ceilMAA, ceilMA)
        }

        // apply gain
        for i in 0..<inCount {
            out[i] = x[i] * gain
        }
    }

    public func getSignalLevel()->Float {
        return 1.0 / gain
    }
    
    public func getRSSI()->Float {
        return -20.0 * log10(gain)
    }
}
