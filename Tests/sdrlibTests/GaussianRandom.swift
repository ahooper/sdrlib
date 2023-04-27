//
//  GaussianRandom.swift
//  SimpleSDR3Tests
//
//  https://stackoverflow.com/a/49471411/302852
//
//  Created by Andy Hooper on 2020-02-23.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//
import class GameplayKit.GKRandomSource
import class GameplayKit.GKLinearCongruentialRandomSource
import Foundation
import struct Accelerate.vecLib.vDSP.DSPComplex

class GaussianRandom {
    private let randomSource: GKRandomSource
    let mean, deviation:Float

    init(randomSource:GKRandomSource=GKLinearCongruentialRandomSource(),
         mean:Float=0.0,
         deviation:Float=1.0) {
        self.randomSource = randomSource
        self.mean = mean
        self.deviation = deviation
    }

    func nextFloat()->Float {
        var u1, u2:Float

        repeat {
            u1 = randomSource.nextUniform() // a random number within the range [0.0, 1.0]
        } while u1 == Float.zero
        u2 = randomSource.nextUniform() // a random number within the range [0.0, 1.0]
        let z1 = sqrtf(-2 * logf(u1)) * cosf(2 * Float.pi * u2) // z1 is normally distributed
        // Convert z1 from the Standard Normal Distribution to our Normal Distribution
        return z1 * deviation + mean
    }
    
    func nextCircular()->DSPComplex {
        // http://mathworld.wolfram.com/Box-MullerTransformation.html
        var u1, u2:Float

        repeat {
            u1 = randomSource.nextUniform() // a random number within the range [0.0, 1.0]
        } while u1 == Float.zero
        u2 = randomSource.nextUniform() // a random number within the range [0.0, 1.0]
        let z1 = sqrtf(-2 * logf(u1)) * cosf(2 * Float.pi * u2)
        let z2 = sqrtf(-2 * logf(u1)) * sinf(2 * Float.pi * u2)
        return DSPComplex(z1,z2)
    }
}
