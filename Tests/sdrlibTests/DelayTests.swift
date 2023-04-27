//
//  DelayTests.swift
//  SimpleSDRLibraryTests
//
//  Created by Andy Hooper on 2021-04-10.
//

import XCTest
@testable import sdrlib

class DelayTests: XCTestCase {
    
    func runTest(_ D:Int, _ x:[Float], _ y:[Float]) {
        let d = Delay(source:NilSource<RealSamples>.Real(), D)
        var o=RealSamples()
        d.process(RealSamples(x), &o)
        AssertEqual(o, y, accuracy:Float.zero)
    }

    func test1() throws {
        runTest(4, [1], [0])
    }

    func test2() throws {
        runTest(4,
                [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
                [0, 0, 0, 0, 1, 2, 3, 4, 5, 6])
    }

    func test3() throws {
        runTest(4,
                [1, 2, 3],
                [0, 0, 0])
    }

    func test4() throws {
        let d = Delay(source:NilSource<RealSamples>.Real(), 4)
        var o=RealSamples()
        d.process(RealSamples([1,2,3]), &o)
        AssertEqual(o, [0,0,0], accuracy:Float.zero)
        d.process(RealSamples([4,5,6]), &o)
        AssertEqual(o, [0,1,2], accuracy:Float.zero)
        d.process(RealSamples([7,8,9,10,11,12]), &o)
        AssertEqual(o, [3,4,5,6,7,8], accuracy:Float.zero)
    }

}
