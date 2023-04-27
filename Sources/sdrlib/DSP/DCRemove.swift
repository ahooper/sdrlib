//
//  DCRemove.swift
//  SimpleSDR3
//
//  https://www.dsprelated.com/showarticle/58.php
//  gnuradio-3.7.9/gr-filter/lib/dc_blocker_cc_impl.cc
//
//  Created by Andy Hooper on 2020-02-20.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

/*private*/ class MovingAverage<Samples:DSPSamples> {
    let D:Int
    var window:Samples // circular buffer
    var winsum:Samples.Element
    var w:Int
    
    init(_ D:Int) {
        self.D = D
        window = Samples(repeating:Samples.zero, count:D)
        w = 0
        winsum = Samples.Element.zero
    }
    
    /* Example D=6
    n   window after process
    .   0   0   0   0   0   0
    0   x0  0   0   0   0   0
    1   x0  x1  0   0   0   0
    2   x0  x1  x2  0   0   0
    3   x0  x1  x2  x3  0   0
    4   x0  x1  x2  x3  x4  0
    5   x0  x1  x2  x3  x4  x5
    6   x6  x1  x2  x3  x4  x5
    7   x6  x7  x2  x3  x4  x5
    8   x6  x7  x8  x3  x4  x5
    9   x6  x7  x8  x9  x4  x5
    10  x6  x7  x8  x9  x10 x5
    11  x6  x7  x8  x9  x10 x11
    12  x12 x7  x8  x9  x10 x11
    */

    func proc(_ x:Samples.Element)->Samples.Element {
        let xD = window[w]
        window[w] = x
        w = (w + 1) % D
        let s = winsum - xD + x
        winsum = s
        return s / Float(D)
    }

    var x_Dplus1:Samples.Element { window[w] }
}

class DCRemove<Samples:DSPSamples>: Buffered<Samples,Samples> {
    private var ma1, ma2:MovingAverage<Samples>
    
    init(source:BufferedSource<Input>?, _ D:Int) {
        ma1 = MovingAverage<Samples>(D)
        ma2 = MovingAverage<Samples>(D)
        super.init("DCRemove", source)
    }
    
    override func process(_ x:Samples, _ out:inout Samples) {
        let inCount = x.count
        out.resize(inCount) // output same size as input
        if inCount == 0 { return }
        for i in 0..<inCount {
            let a1 = ma1.proc(x[i])
            let a2 = ma2.proc(a1)
            out[i] = ma1.x_Dplus1 - a2
        }
    }
}
