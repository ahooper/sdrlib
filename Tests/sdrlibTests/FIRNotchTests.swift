//
//  FIRNotchTests.swift
//  SimpleSDR3Tests
//
//  Created by Andy Hooper on 2020-04-21.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import XCTest
import struct Accelerate.vecLib.vDSP.DSPComplex
@testable import sdrlib

class FIRNotchTests: XCTestCase {
    
    fileprivate func runTest(_ semiLength:Int, _ attentuation:Float, _ frequency:Float) {
        let NUM_SAMPLES = 500
        let H = FIRKernel.notch(filterSemiLength: semiLength,
                                normalizedNotchFrequency: frequency,
                                stopBandAttenuation: attentuation)
        let q = FIRFilter(source:NilSource<ComplexSamples>.Complex(), H)
        let x = ComplexSamples((0..<(NUM_SAMPLES+H.count)).map{DSPComplex.exp(DSPComplex(0, 2*Float.pi*frequency*Float($0)))})
        var o = ComplexSamples()
        q.process(x,&o)
        var x2:Float=0, o2:Float=0
        for i in (H.count)..<x.count {
            x2 += pow(x[i].modulus(),2)
            o2 += pow(o[i].modulus(),2)
        }
        x2 = sqrt(x2/Float(NUM_SAMPLES))
        o2 = sqrt(o2/Float(NUM_SAMPLES))
        print("f0", frequency, "x2", x2, "o2", o2)
        XCTAssertEqual(x2, 1.0, accuracy: 1e-3)
        XCTAssertEqual(o2, 0.0, accuracy: 1e-3)
    }
    
    func testNotch0() {
        runTest(20, 60, 0.000)
    }
    
    func testNotch1() {
        runTest(20, 60, 0.100)
    }
    
    func testNotch2() {
        runTest(20, 60, 0.456)
    }
    
    func testNotch3() {
        runTest(20, 60, 0.500)
    }
    
    func testNotch4() {
        runTest(20, 60, -0.250)
    }
    
    func testNotch5() {
        runTest(20, 60, -0.389)
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

}
