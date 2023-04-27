//
//  WindowFunctionTests.swift
//  sdrlibTests
//
//  Excerpts from https://github.com/scipy/scipy/blob/main/scipy/signal/tests/test_windows.py
//

import XCTest
import func CoreFoundation.exp
import func CoreFoundation.log
import func CoreFoundation.lgammal
@testable import sdrlib

final class WindowFunctionTests: XCTestCase {

    func testRectangular() throws {
        XCTAssertEqual(WindowFunction.Symmetric(6, WindowFunction.rectangular), [1, 1, 1, 1, 1, 1])
        XCTAssertEqual(WindowFunction.Symmetric(7, WindowFunction.rectangular), [1, 1, 1, 1, 1, 1, 1])
        XCTAssertEqual(WindowFunction.Periodic(6, WindowFunction.rectangular), [1, 1, 1, 1, 1, 1])
    }

    func testBartlett() throws {
        AssertEqual(WindowFunction.Symmetric(6, WindowFunction.bartlett),
                    [0.0, 0.4, 0.8, 0.8, 0.4, 0.0],
                    accuracy: 1e-7)
        AssertEqual(WindowFunction.Symmetric(7, WindowFunction.bartlett),
                    [Float](arrayLiteral: 0.0, 1.0/3.0, 2.0/3.0, 1.0, 2.0/3.0, 1/3.0, 0.0),
                    accuracy: 1e-7)
        AssertEqual(WindowFunction.Periodic(6, WindowFunction.bartlett),
                    [Float](arrayLiteral: 0.0, 1.0/3.0, 2.0/3.0, 1.0, 2.0/3.0, 1.0/3.0),
                    accuracy: 1e-7)
    }

    func testHann() throws {
        AssertEqual(WindowFunction.Periodic(6, WindowFunction.hann),
                        [0, 0.25, 0.75, 1.0, 0.75, 0.25],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Periodic(7, WindowFunction.hann),
                        [0, 0.1882550990706332, 0.6112604669781572,
                         0.9504844339512095, 0.9504844339512095,
                         0.6112604669781572, 0.1882550990706332],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(6, WindowFunction.hann),
                        [0, 0.3454915028125263, 0.9045084971874737,
                         0.9045084971874737, 0.3454915028125263, 0],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(7, WindowFunction.hann),
                        [0, 0.25, 0.75, 1.0, 0.75, 0.25, 0],
                    accuracy: 5e-7)
    }
    
    func testHamming() throws {
        AssertEqual(WindowFunction.Periodic(6, WindowFunction.hamming),
                        [0.08, 0.31, 0.77, 1.0, 0.77, 0.31],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Periodic(7, WindowFunction.hamming),
                        [0.08, 0.2531946911449826, 0.6423596296199047,
                         0.9544456792351128, 0.9544456792351128,
                         0.6423596296199047, 0.2531946911449826],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(6, WindowFunction.hamming),
                        [0.08, 0.3978521825875242, 0.9121478174124757,
                         0.9121478174124757, 0.3978521825875242, 0.08],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(7, WindowFunction.hamming),
                        [0.08, 0.31, 0.77, 1.0, 0.77, 0.31, 0.08],
                    accuracy: 5e-7)
    }
    
    func testBlackman() throws {
        AssertEqual(WindowFunction.Periodic(6, WindowFunction.blackman),
                    [0, 0.13, 0.63, 1.0, 0.63, 0.13],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Periodic(7, WindowFunction.blackman),
                        [0, 0.09045342435412804, 0.4591829575459636,
                         0.9203636180999081, 0.9203636180999081,
                         0.4591829575459636, 0.09045342435412804],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(6, WindowFunction.blackman),
                        [0, 0.2007701432625305, 0.8492298567374694,
                         0.8492298567374694, 0.2007701432625305, 0],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(7, WindowFunction.blackman),
                        [0, 0.13, 0.63, 1.0, 0.63, 0.13, 0],
                    accuracy: 5e-7)
    }
    
    func testBlackmanharris() throws {
        AssertEqual(WindowFunction.Periodic(6, WindowFunction.blackmanharris),
                        [6.0e-05, 0.055645, 0.520575, 1.0, 0.520575, 0.055645],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Periodic(7, WindowFunction.blackmanharris),
                        [6.0e-05, 0.03339172347815117, 0.332833504298565,
                         0.8893697722232837, 0.8893697722232838,
                         0.3328335042985652, 0.03339172347815122],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(6, WindowFunction.blackmanharris),
                        [6.0e-05, 0.1030114893456638, 0.7938335106543362,
                         0.7938335106543364, 0.1030114893456638, 6.0e-05],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(7, WindowFunction.blackmanharris),
                        [6.0e-05, 0.055645, 0.520575, 1.0, 0.520575, 0.055645,
                         6.0e-05],
                    accuracy: 5e-7)
    }
    
    func testNutall() throws {
        AssertEqual(WindowFunction.Periodic(6, WindowFunction.nuttall37),
                        [0.0003628, 0.0613345, 0.5292298, 1.0, 0.5292298,
                         0.0613345],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Periodic(7, WindowFunction.nuttall37),
                        [0.0003628, 0.03777576895352025, 0.3427276199688195,
                         0.8918518610776603, 0.8918518610776603,
                         0.3427276199688196, 0.0377757689535203],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(6, WindowFunction.nuttall37),
                        [0.0003628, 0.1105152530498718, 0.7982580969501282,
                         0.7982580969501283, 0.1105152530498719, 0.0003628],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(7, WindowFunction.nuttall37),
                        [0.0003628, 0.0613345, 0.5292298, 1.0, 0.5292298,
                         0.0613345, 0.0003628],
                    accuracy: 5e-7)
    }
    
    func testFlattop() throws {
        AssertEqual(WindowFunction.Periodic(6, WindowFunction.flattop),
                        [-0.000421051, -0.051263156, 0.19821053, 1.0,
                         0.19821053, -0.051263156],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Periodic(7, WindowFunction.flattop),
                        [-0.000421051, -0.03684078115492348,
                         0.01070371671615342, 0.7808739149387698,
                         0.7808739149387698, 0.01070371671615342,
                         -0.03684078115492348],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(6, WindowFunction.flattop),
                        [-0.000421051, -0.0677142520762119, 0.6068721525762117,
                         0.6068721525762117, -0.0677142520762119,
                         -0.000421051],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(7, WindowFunction.flattop),
                        [-0.000421051, -0.051263156, 0.19821053, 1.0,
                         0.19821053, -0.051263156, -0.000421051],
                    accuracy: 5e-7)
    }
    
    func testKaiser() throws {
        AssertEqual(WindowFunction.Symmetric(6, WindowFunction.kaiser(beta: 0.5)),
                        [0.9403061933191572, 0.9782962393705389,
                         0.9975765035372042, 0.9975765035372042,
                         0.9782962393705389, 0.9403061933191572],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(7, WindowFunction.kaiser(beta: 0.5)),
                        [0.9403061933191572, 0.9732402256999829,
                         0.9932754654413773, 1.0, 0.9932754654413773,
                         0.9732402256999829, 0.9403061933191572],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(6, WindowFunction.kaiser(beta: 2.7)),
                        [0.2603047507678832, 0.6648106293528054,
                         0.9582099802511439, 0.9582099802511439,
                         0.6648106293528054, 0.2603047507678832],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Symmetric(7, WindowFunction.kaiser(beta: 2.7)),
                        [0.2603047507678832, 0.5985765418119844,
                         0.8868495172060835, 1.0, 0.8868495172060835,
                         0.5985765418119844, 0.2603047507678832],
                    accuracy: 5e-7)
        AssertEqual(WindowFunction.Periodic(6, WindowFunction.kaiser(beta: 2.7)),
                        [0.2603047507678832, 0.5985765418119844,
                         0.8868495172060835, 1.0, 0.8868495172060835,
                         0.5985765418119844],
                    accuracy: 5e-7)
    }
    
    func caseBessi0(_ z:Double) {
        // https://github.com/scipy/scipy/blob/main/scipy/special/tests/test_basic.py:2901,2910
        let n = 200, v = 0.0
        let s: [Double] = (0..<n).map { k in
            exp(  (v+2*Double(k))*log(0.5*z)
                - lgammal(Double(k+1))
                - lgammal(v+Double(k+1)) )
        }
        let ss: Double = s.reduce(0,+)
        XCTAssertEqual(WindowFunction.bessI0(z), ss, accuracy: ss*4e-7)
    }
    
    func testBessi0() throws {
        XCTAssertEqual(WindowFunction.bessI0(0), 1.0)
        caseBessi0(1.0)
        caseBessi0(10.0)
        caseBessi0(200.5)
    }

}
