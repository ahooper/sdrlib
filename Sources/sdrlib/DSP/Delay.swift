//
//  Delay.swift
//  
//
//  Created by Andy Hooper on 2021-04-10.
//

class Delay<Samples:DSPSamples>: Buffered<Samples,Samples> {
    var buffer:Samples
    let P:Int

    init(source:BufferedSource<Input>?, _ P:Int) {
        precondition(P >= 0)
        self.P = P
        buffer = Samples(repeating:Samples.zero, count:P)
        buffer.reserveCapacity(P*2-1)
        super.init("Delay", source)
    }
    
    /*
     buff    x                    buff    out
     0 0 0 | 1 2 3 4 5 6 7 8 9 => 7 8 9 | 0 0 0 1 2 3 4 5 6
     0 0 0 | 1 2 => 0 1 2 | 0 0
     */
    
    override func process(_ x:Samples, _ out:inout Samples) {
        let inCount = x.count
        out.resize(inCount) // output same size as input
        if inCount == 0 { return }
        if inCount >= P {
            // replacing whole buffer
            out.replaceSubrange(0..<P, with: buffer, 0..<P)
            out.replaceSubrange(P..<inCount, with: x, 0..<(inCount-P))
            buffer.replaceSubrange(0..<P, with:x, (inCount-P)..<inCount)
        } else {
            // replacing only part of buffer
            buffer.append(x)
            out.replaceSubrange(0..<inCount, with: buffer, 0..<inCount)
            buffer.removeSubrange(0..<inCount)
        }
    }

}
