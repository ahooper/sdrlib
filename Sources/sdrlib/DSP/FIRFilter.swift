//
//  FIRFilter.swift
//  SimpleSDR3
//
//  Created by Andy Hooper on 2019-12-15.
//  Copyright © 2019 Andy Hooper. All rights reserved.
//

public class FIRFilter<Samples:DSPSamples>: Buffered<Samples,Samples> where Samples:DotProduct {
    let reversedCoefficients:[Float]
    let P, Pminus1:Int
    private var overlap:Samples

    public init(source:BufferedSource<Input>?, _ coefficients:[Float]) {
        precondition(coefficients.count >= 1)
        reversedCoefficients = coefficients.reversed()
        P = coefficients.count
        Pminus1 = P - 1
        overlap = Samples(repeating:Samples.zero, count:Pminus1*2)
        super.init("FIRFilter", source)
    }
    
    override public func process(_ x:Input, _ output:inout Output) {
        let inCount = x.count
        output.resize(inCount) // output same size as input
        if inCount == 0 { return }
        if inCount >= Pminus1 {
            overlap.replaceSubrange(Pminus1..<overlap.count, with:x, 0..<Pminus1)
            for i in 0..<Pminus1 {
                output[i] = overlap.dotProduct(at:i, reversedCoefficients)
            }
            for i in Pminus1..<inCount {
                output[i] = x.dotProduct(at:i-Pminus1, reversedCoefficients)
            }
            overlap.replaceSubrange(0..<Pminus1, with:x, (inCount-Pminus1)..<inCount)
        } else {
            overlap.replaceSubrange(Pminus1..<overlap.count, with: x, 0..<inCount)
            for i in 0..<inCount {
                output[i] = overlap.dotProduct(at:i, reversedCoefficients)
            }
            overlap.removeSubrange(0..<inCount)
        }
    }
}
