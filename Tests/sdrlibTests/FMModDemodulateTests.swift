//
//  FMModDemodulateTests.swift
//  SimpleSDR3Tests
//
//  Created by Andy Hooper on 2020-01-27.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import XCTest
import struct Accelerate.vecLib.vDSP.DSPComplex
@testable import sdrlib

//extension FMDemodulate {
//    var output:SplitComplex { buffers[processIndex] }
//}

class FMModDemodulateTests: XCTestCase {

    func runTest(_ modulationFactor:Float) {
        let N = 1024
        // sum of sines from liquid-dsp-1.3.1/src/modem/tests/freqmodem_autotest.c
        let y = [Float]((0..<N).map{let s:Float = 0.3*cosf(2*Float.pi*0.013*Float($0) + 0.0) +
                                                  0.2*cosf(2*Float.pi*0.021*Float($0) + 0.4) +
                                                  0.4*cosf(2*Float.pi*0.037*Float($0) + 1.7)
                                         return s} )
        let x = y
        // Test on the whole block
        let fmod = FMTestBaseband(source:NilSource<RealSamples>.Real(), modulationFactor:modulationFactor)
        let fdem = FMDemodulate(source:fmod, modulationFactor:modulationFactor)
        fmod.process(RealSamples(x))
        let o = fdem.produceBuffer
        //print(o)
        AssertEqual(Array(o[1..<N]), Array(y[1...]), accuracy:1.0e-6)

        // Test on two halves in sequence, to exercise stream overalap
        let fm2 = FMTestBaseband(source:NilSource<RealSamples>.Real(), modulationFactor:modulationFactor)
        let fd2 = FMDemodulate(source:fm2, modulationFactor:modulationFactor)
        assert(x.count == y.count)
        let half = x.count / 2
        fm2.process(RealSamples(Array(x[0..<half])))
        let o1 = fd2.produceBuffer
        fm2.process(RealSamples(Array(x[half...])))
        let o2 = fd2.produceBuffer
        var oo = RealSamples()
        oo.append(o1)
        oo.append(o2)
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
