//
//  MovingAverageTests.swift
//  SimpleSDR3Tests
//
//  Created by Andy Hooper on 2020-02-21.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import XCTest
import struct Accelerate.vecLib.vDSP.DSPComplex
@testable import sdrlib

class MovingAverageTests: XCTestCase {
    
    func runTest(_ D:Int, _ X:[Float], _ Y:[Float]) {
        let ma = MovingAverage<RealSamples>(D)
        var o = [Float](repeating:Float.nan, count:X.count)
        for i in 0..<X.count {
            o[i] = ma.proc(X[i])
        }
        //print(o)
        AssertEqual(o, Y, accuracy:1e-6)
    }
    
    func runTest(_ D:Int, _ X:[DSPComplex], _ Y:[DSPComplex]) {
        let ma = MovingAverage<ComplexSamples>(D)
        var o = [DSPComplex](repeating:DSPComplex.nan, count:X.count)
        for i in 0..<X.count {
            o[i] = ma.proc(X[i])
        }
        //print(o)
        AssertEqual(o, Y, accuracy:1e-6)
    }

    func testReal1() {
        runTest(3,
                [1, 1, 1, 1, 1, 1],
                [0.333333, 0.666666, 1.0, 1.0, 1.0, 1.0])
        }

    func testReal2() {
        runTest(3,
                [4, 8, 6, -1, -2, -3, -1, 3, 4, 5],
                [1.333333, 4.0, 6.0, 4.333333, 1.0, -2.0, -2.0, -0.333333, 2.0, 4.0])
    }
    
    func testComplex1() {
        runTest(3,
                [DSPComplex(4,1),
                 DSPComplex(8,1),
                 DSPComplex(6,1),
                 DSPComplex(-1,1),
                 DSPComplex(-2,1),
                 DSPComplex(-3,1),
                 DSPComplex(-1,1),
                 DSPComplex(3,1),
                 DSPComplex(4,1),
                 DSPComplex(5,1)],
                [DSPComplex(1.333333,0.333333),
                DSPComplex(4.0,0.666666),
                DSPComplex(6.0,1.0),
                DSPComplex(4.333333,1.0),
                DSPComplex(1.0,1.0),
                DSPComplex(-2.0,1.0),
                DSPComplex(-2.0,1.0),
                DSPComplex(-0.333333,1.0),
                DSPComplex(2.0,1.0),
                DSPComplex(4.0,1.0)])
    }

}
