//
//  ArrayAndComplexAsserts.swift
//  SimpleSDR3Tests
//
//  Created by Andy Hooper on 2020-01-24.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import XCTest
import struct Accelerate.vecLib.vDSP.DSPComplex
@testable import sdrlib

// TODO: floating point relative tolerance tests https://randomascii.wordpress.com/2012/02/25/comparing-floating-point-numbers-2012-edition/

func AssertEqual(_ a: [Float], _ b: [Float], accuracy:Float,
                             file:StaticString=#file, line:UInt=#line) {
    XCTAssertEqual(a.count, b.count, "count", file:file, line:line)
    for i in 0..<min(a.count,b.count) {
        XCTAssertEqual(a[i], b[i], accuracy:accuracy,
                       "element[\(i)]", file:file, line:line)
    }
}

func AssertEqual(_ a: [Double], _ b: [Double], accuracy: Double,
                             file: StaticString=#file, line: UInt=#line) {
    XCTAssertEqual(a.count, b.count, "count", file:file, line:line)
    for i in 0..<min(a.count,b.count) {
        XCTAssertEqual(a[i], b[i], accuracy:accuracy,
                       "element[\(i)]", file:file, line:line)
    }
}

func AssertEqual(_ a: RealSamples, _ b: [Float], accuracy:Float,
                             file:StaticString=#file, line:UInt=#line) {
    XCTAssertEqual(a.count, b.count, "count", file:file, line:line)
    for i in 0..<min(a.count,b.count) {
        XCTAssertEqual(a[i], b[i], accuracy:accuracy,
                       "element[\(i)]", file:file, line:line)
    }
}

func AssertEqual(_ a: [Float], _ b: RealSamples, accuracy:Float,
                             file:StaticString=#file, line:UInt=#line) {
    XCTAssertEqual(a.count, b.count, "count", file:file, line:line)
    for i in 0..<min(a.count,b.count) {
        XCTAssertEqual(a[i], b[i], accuracy:accuracy,
                       "element[\(i)]", file:file, line:line)
    }
}

func AssertEqual(_ a: DSPComplex, _ b: DSPComplex, accuracy:Float,
                             _ message: @escaping @autoclosure () -> String = "",
                             file:StaticString=#file, line:UInt=#line) {
    XCTAssertEqual((a - b).modulus(), 0.0, accuracy:accuracy,
                   "\(message()) \(a) \(b)", file:file, line:line)
}

func AssertEqual(_ a: [DSPComplex], _ b: [DSPComplex], accuracy:Float,
                             file:StaticString=#file, line:UInt=#line) {
    XCTAssertEqual(a.count, b.count, "count", file:file, line:line)
    for i in 0..<min(a.count,b.count) {
        AssertEqual(a[i], b[i], accuracy:accuracy,
                       "element[\(i)]", file:file, line:line)
    }
}

func AssertEqual(_ a: ComplexSamples, _ b: [DSPComplex], accuracy:Float,
                             file:StaticString=#file, line:UInt=#line) {
    XCTAssertEqual(a.count, b.count, "count", file:file, line:line)
    for i in 0..<min(a.count,b.count) {
        AssertEqual(a[i], b[i], accuracy:accuracy,
                       "element[\(i)]", file:file, line:line)
    }
}
