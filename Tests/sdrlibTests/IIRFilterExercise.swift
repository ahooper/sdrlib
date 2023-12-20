//
//  IIRFilterExercise.swift
//  SimpleSDR3Tests
//
//  Created by Andy Hooper on 2020-04-22.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import XCTest
import struct Accelerate.vecLib.vDSP.DSPComplex
@testable import sdrlib

class IIRFilterExercise: XCTestCase {

    func testExercise() {
        // no result comparision, just ensure no assert fails or other exceptions
        let b:[Float] = [10,11,12,13,14]
        let a:[Float] = [10,11,12,13]
        let x:[Float] = [0,1,2,3,4,5,6,7,8,9,10,11]
        let f = IIRFilter<RealSamples>(source:nil, b, a)
        var o=RealSamples()
        f.process(RealSamples(x), &o)
    }

}
