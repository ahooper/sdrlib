//
//  AMModulate.swift
//  
//
//  Created by Andy Hooper on 2020-09-08.
//

public class AMModulate: Buffered<RealSamples,ComplexSamples> {
    let carrier: Oscillator<ComplexSamples>,
        factor: Float,
        suppressedCarrier: Bool
    private var carr: ComplexSamples

    public init(source:BufferedSource<Input>?,
         factor:Float=1,
         carrierHz:Double,
         suppressedCarrier:Bool=false,
         carrierlevel:Float=1.0) {
        self.carrier =  Oscillator<ComplexSamples>(signalHz: carrierHz,
                                                   sampleHz: source!.sampleFrequency(),
                                                   level: carrierlevel)
        self.factor = factor
        self.suppressedCarrier = suppressedCarrier
        self.carr = ComplexSamples()
        super.init("AMModulate", source)
     }
    
    override public func process(_ x:Input, _ output: inout Output) {
        let inCount = x.count
        output.resize(inCount) // output same size as input
        if inCount == 0 { return }
        carr.removeAll(keepingCapacity: true)
        carrier.generate(inCount, &carr)
        for i in 0..<inCount {
            let s = (suppressedCarrier ? Input.Element(0) : Input.Element(1)) + x[i]*factor
            output[i] = carr[i] * s
        }
    }
}
