//
//  FMDemodulate.swift
//  SimpleSDR3
//
//  http://www.hyperdynelabs.com/dspdude/papers/DigRadio_w_mathcad.pdf
//
//  Created by Andy Hooper on 2020-01-25.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

class FMDemodulate: Buffered<ComplexSamples,RealSamples> {
    let modulationFactor:Float
    let factor:Float
    private var overlap:ComplexSamples.Element
    
    init(source:BufferedSource<Input>?,
         modulationFactor:Float) {
        self.modulationFactor = modulationFactor
        self.factor = 1 / (2 * Float.pi * modulationFactor)
        overlap = Input.zero
        super.init("FMDemodulate", source)
    }
    
    override func process(_ x:Input, _ output:inout Output) {
        let inCount = x.count
        output.resize(inCount) // output same size as input
        if inCount == 0 { return }
        for i in 0..<inCount {
            // polar discriminator
            let w = overlap.conjugate() * x[i]
            let phase = w.argument()
            overlap = x[i]
            output[i] = phase * factor
        }
    }
}
