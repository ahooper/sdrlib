//
//  IIRFilter.swift
//  SimpleSDR3
//
//  Created by Andy Hooper on 2020-04-21.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

public class IIRFilter<Samples:DSPSamples>: Buffered<Samples,Samples> where Samples:DotProduct {
    let reversedForward, reversedBackward:[Float]
    let numForward, numForwardMinus1, numBackward, numBackwardMinus1:Int
    let backwardCoefficient0:Float
    private var overlapIn, overlapOut:Samples

    init(source:BufferedSource<Input>?, _ forwardCoefficients:[Float], _ backwardCoefficients:[Float]) {
        precondition(forwardCoefficients.count >= 1)
        precondition(backwardCoefficients.count >= 1)
        numForward = forwardCoefficients.count
        numForwardMinus1 = numForward - 1
        reversedForward = forwardCoefficients.reversed()
        overlapIn = Samples(repeating:Samples.zero, count:numForwardMinus1*2)
        numBackward = backwardCoefficients.count
        numBackwardMinus1 = numBackward - 1
        reversedBackward = backwardCoefficients[1...].reversed()
        backwardCoefficient0 = backwardCoefficients[0]
        overlapOut = Samples(repeating:Samples.zero, count:numBackwardMinus1*2)
        super.init("IIRFilter", source)
    }
    
    private func trace(_ o:String, _ v:String, _ at:Int, _ wa:[Float], _ wn:String, _ wb:Int=0, _ d:String="") {
        print(o,terminator:"")
        for j in 0..<wa.count {
            print(" \(v)\(j+at)*\(wn)\(wa.count-1-j+wb)",terminator:"")
        }
        print(d)
    }
    
    override public func process(_ x:Samples, _ out:inout Samples) {
        let count = x.count
        out.resize(count) // output same size as input
        if count == 0 { return }
        if count >= numForwardMinus1 {
            overlapIn.replaceSubrange(numForwardMinus1..<overlapIn.count, with:x, 0..<numForwardMinus1)
            for i in 0..<numForwardMinus1 {
                //trace("y\(i) =", "x", i-numForwardMinus1, reversedForward, "b")
                out[i] = overlapIn.dotProduct(at:i, reversedForward)
            }
            for i in numForwardMinus1..<count {
                //trace("y\(i) =", "x", i-numForwardMinus1, reversedForward, "b")
                out[i] = x.dotProduct(at:i-numForwardMinus1, reversedForward)
            }
            overlapIn.replaceSubrange(0..<numForwardMinus1, with:x, (count-numForwardMinus1)..<count)
        } else {
            overlapIn.replaceSubrange(numForwardMinus1..<overlapIn.count, with: x, 0..<count)
            for i in 0..<count {
                //trace("y\(i) =", "x", i-numForwardMinus1, reversedForward, "b")
                out[i] = overlapIn.dotProduct(at:i, reversedForward)
            }
            overlapIn.removeSubrange(0..<count)
        }
        //for j in 0..<reversedBackward.count { print("",overlapOut[j],terminator:"") }; print()
        if count >= numBackwardMinus1 {
            for i in 0..<numBackwardMinus1 {
                //trace("y\(i) = (y\(i) - (", "y", i-numBackwardMinus1, reversedBackward, "a", 1, ")) / a0")
                let oi = (out[i] - overlapOut.dotProduct(at: i, reversedBackward)) / backwardCoefficient0
                out[i] = oi
                overlapOut[i+numBackwardMinus1] = oi
            }
            for i in numBackwardMinus1..<count {
                //trace("y\(i) = (y\(i) - (", "y", i-numBackwardMinus1, reversedBackward, "a", 1, ")) / a0")
                out[i] = (out[i] - out.dotProduct(at: i-numBackwardMinus1, reversedBackward)) / backwardCoefficient0
            }
            overlapOut.replaceSubrange(0..<numBackwardMinus1, with:out, (count-numBackwardMinus1)..<count)
        } else {
            for i in 0..<count {
                //trace("y\(i) = (y\(i) - (", "y", i-numBackwardMinus1, reversedBackward, "a", 1, ")) / a0")
                let oi = (out[i] - overlapOut.dotProduct(at: i, reversedBackward)) / backwardCoefficient0
                out[i] = oi
                overlapOut[i+numBackwardMinus1] = oi
            }
            overlapOut.replaceSubrange(0..<numBackwardMinus1, with:overlapOut, count..<(count+numBackwardMinus1))
        }
        //for j in 0..<reversedBackward.count { print("",overlapOut[j],terminator:"") }; print()
    }
}

public class IIR22Filter<Samples:DSPSamples>: Buffered<Samples,Samples> {
    // Specialization of IIRFilter for 2 forward coefficients, 2 backward coefficients, backward[0] == 1.0
    let b0, b1, a1:Float
    private var overlapIn, overlapOut:Samples.Element

    public init(source:BufferedSource<Samples>?, _ forwardCoefficients:[Float], _ backwardCoefficients:[Float]) {
        precondition(forwardCoefficients.count == 2)
        precondition(backwardCoefficients.count == 2)
        precondition(backwardCoefficients[0] == 1.0)
        b0 = forwardCoefficients[0]
        b1 = forwardCoefficients[1]
        a1 = backwardCoefficients[1]
        overlapIn = Samples.Element.zero
        overlapOut = Samples.Element.zero
        super.init("IIR22Filter", source)
    }
    
    override public func process(_ x:Samples, _ out:inout Samples) {
        let count = x.count
        out.resize(count) // output same size as input
        if count == 0 { return }
        //TODO: vDSP vector operations
        out[0] = overlapIn*b1 + x[0]*b0
        for i in 1..<count {
            out[i] = x[i-1]*b1 + x[i]*b0
        }
        overlapIn = x[count-1]
        out[0] = out[0] - overlapOut*a1
        for i in 1..<count {
            out[i] = out[i] - out[i-1]*a1
        }
        overlapOut = out[count-1]
    }
}
