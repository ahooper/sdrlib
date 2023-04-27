//
//  FIRKernelTests.swift
//  SimpleSDR3Tests
//
//  Created by Andy Hooper on 2020-04-21.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import XCTest
@testable import sdrlib

class FIRKernelTests: XCTestCase {

    func testLowPassRectangular() {
        // Low Pass Filter Example from http://www.labbookpages.co.uk/audio/firWindowing.html
        let f = FIRKernel.sincKernel(filterLength: 21,
                                     normalizedTransitionFrequency: 460.0 / 2000.0,
                                     highNotLowPass: false,
                                     windowFunction: WindowFunction.rectangular,
                                     gain: Float.nan)
        //FIRKernel.plotFrequencyResponse(f, title: "Low pass filter example")
        let v: [Float] = [
                0.030273, 0.015059, -0.033595, -0.028985, 0.036316,
                0.051504, -0.038337, -0.098652, 0.039580, 0.315800, 0.460000,
                0.315800, 0.039580, -0.098652, -0.038337, 0.051504,
                0.036316, -0.028985, -0.033595, 0.015059, 0.030273]
        //print(f)
        AssertEqual(f, v, accuracy: 1e-6);
    }
    
    func testLowPassKaiser() {
        // Kaiser Window example from http://www.labbookpages.co.uk/audio/firWindowing.html
        let rippledB = -20 * log10f(0.01),
              width = 100.0/1000.0*2.0
        let (length,beta) = FIRKernel.kaiser_parameters(ripple: rippledB, width: Float(width))
        XCTAssertEqual(beta, 3.395321, accuracy:1e-6)
        let f = FIRKernel.sincKernel(filterLength: length,
                                     normalizedTransitionFrequency: 250.0 / 1000.0,
                                     highNotLowPass: false,
                                     windowFunction: WindowFunction.kaiser(beta: beta),
                                     gain: Float.nan)
        let v: [Float] = [
                -0.002896, -0.004885,  0.007528,  0.010980, -0.015463,
                -0.021317,  0.029123,  0.039980, -0.056254, -0.084142,
                 0.146464,  0.448952,  0.448952,  0.146464, -0.084142,
                -0.056254,  0.039980,  0.029123, -0.021317, -0.015463,
                 0.010980,  0.007528, -0.004885, -0.002896]
        //print(f)
        AssertEqual(f, v, accuracy: 1e-3);
    }

    func testPolyphaseBank() {
        // test data from liquid-dsp-1.3.1/src/filter/tests/firpfb_autotest.c
        let M = 4
        let h: [Float] = [
         -0.033116,  -0.024181,  -0.006284,   0.018261,
          0.045016,   0.068033,   0.080919,   0.078177,
          0.056597,   0.016403,  -0.038106,  -0.098610,
         -0.153600,  -0.189940,  -0.194900,  -0.158390,
         -0.075002,   0.054511,   0.222690,   0.415800,
          0.615340,   0.800390,   0.950380,   1.048100,
          1.082000,   1.048100,   0.950380,   0.800390,
          0.615340,   0.415800,   0.222690,   0.054511,
         -0.075002,  -0.158390,  -0.194900,  -0.189940,
         -0.153600,  -0.098610,  -0.038106,   0.016403,
          0.056597,   0.078177,   0.080919,   0.068033,
          0.045016,   0.018261,  -0.006284,  -0.024181]
        let X = RealSamples([
          0.438310,   1.001900,   0.200600,   0.790040,
          1.134200,   1.592200,  -0.702980,  -0.937560,
         -0.511270,  -1.684700,   0.328940,  -0.387780])
        let test = RealSamples([
            2.05558467194397,
            1.56922189602661,
            0.998479744645138,
            0.386125857849177])
        let FB = FIRKernel.polyphaseBank(M, h)
        //print(FB)
        for j in 0..<M {
            let y = X.weightedSum(at:0, FB[j])
            XCTAssertEqual(y, test[j], accuracy:5e-5)
        }
    }

}
