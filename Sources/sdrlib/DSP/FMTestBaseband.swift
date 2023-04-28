//
//  FMTestBaseband.swift
//  SimpleSDR3
//
//  Created by Andy Hooper on 2020-01-25.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import func CoreFoundation.cosf
import func CoreFoundation.sinf

class FMTestBaseband: Buffered<RealSamples,ComplexSamples> {
    let modulationFactor:Float
    let factor:Float
    private var phase:Float

    public init(source:BufferedSource<Input>?,
         modulationFactor:Float) {
        self.modulationFactor = modulationFactor
        self.factor = 2 * Float.pi * modulationFactor
        phase = Float(0)
        super.init("FMTestBaseband", source)
    }
    
    override public func process(_ x:RealSamples, _ out:inout ComplexSamples) {
        let inCount = x.count
        out.resize(inCount) // output same size as input
        if inCount == 0 { return }
        for i in 0..<inCount {
            phase = phase + x[i] * factor
            out[i] =  ComplexSamples.Element(cosf(phase),sinf(phase))
        }
    }
}
