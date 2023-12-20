//
//  FMDemodulateTests.swift
//  SimpleSDR3Tests
//
//  Created by Andy Hooper on 2020-01-27.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import XCTest
import struct Accelerate.vecLib.vDSP.DSPComplex
@testable import sdrlib

class FMDemodulateTests: XCTestCase {

    func runTest(_ modulationFactor:Float) {
        let N = 1024
        // sum of sines from liquid-dsp-1.3.1/src/modem/tests/freqmodem_autotest.c
        let y = [Float]((0..<N).map{let s:Float = 0.3*cosf(2*Float.pi*0.013*Float($0) + 0.0) +
                                                  0.2*cosf(2*Float.pi*0.021*Float($0) + 0.4) +
                                                  0.4*cosf(2*Float.pi*0.037*Float($0) + 1.7)
                                         return s} )
        var phase = Float.zero
        let x = [DSPComplex]((0..<N).map{phase += 2*Float.pi*y[$0]*modulationFactor
                                         return DSPComplex(cosf(phase),sinf(phase))})
        // Test on the whole block
        let fdem = FMDemodulate(source:nil, modulationFactor:modulationFactor)

        var o=RealSamples()
        fdem.process(ComplexSamples(x), &o)
        AssertEqual(Array(o[1..<N]), Array(y[1..<N]), accuracy:1.0e-6)

        // Test on two halves in sequence, to exercise stream overalap
        let f2 = FMDemodulate(source:nil, modulationFactor:modulationFactor)
        assert(x.count == y.count)
        let half = x.count / 2
        var oo=RealSamples(), o2=RealSamples()
        f2.process(ComplexSamples(Array(x[0..<half])), &oo)
        f2.process(ComplexSamples(Array(x[half...])), &o2)
        oo.append(contentsOf: o2)
        AssertEqual(Array(oo[1..<N]), Array(y[1...]), accuracy:1.0e-6)

    }
    
    func testFMDemodulate2() {
        runTest(0.02)
    }
    
    func testFMDemodulate4() {
        runTest(0.04)
    }
    
    func testFMDemodulate8() {
        runTest(0.08)
    }

}
