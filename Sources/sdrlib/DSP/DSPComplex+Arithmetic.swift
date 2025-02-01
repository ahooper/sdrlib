//
//  DSPComplexArithmetic.swift
//  SimpleSDR
//
//  https://algs4.cs.princeton.edu/code/edu/princeton/cs/algs4/Complex.java.html
//  https://github.com/dankogai/swift-complex/blob/master/Sources/Complex/Complex.swift
//  https://github.com/apple/swift-numerics
//  https://github.com/gongzhang/swift-complex-number
//
//  Created by Andy Hooper on 2019-10-13.
//  Copyright © 2019 Andy Hooper. All rights reserved.
//

import func CoreFoundation.hypotf
import func CoreFoundation.atan2f
import func CoreFoundation.expf
import func CoreFoundation.cosf
import func CoreFoundation.sinf
import func CoreFoundation.coshf
import func CoreFoundation.sinhf
import struct Accelerate.vecLib.vDSP.DSPComplex

extension DSPComplex: @retroactive Numeric, @retroactive Equatable, @retroactive CustomStringConvertible, @retroactive CustomDebugStringConvertible {
    public typealias Element = Float
    public typealias Magnitude = Float

    public init(_ r:Element, _ i:Element) {
        self.init(real:r, imag:i)
    }
    
    public init(_ r:Element) {
        self.init(real:r, imag:0)
    }
    
    // required by Numeric, seems like a wart
    public init?<T>(exactly source: T) where T : BinaryInteger {
        if let exact = Element(exactly: source) {
            self.init(real:exact, imag:Element.zero)
        } else {
            return nil
        }
    }
    // required by Numeric, seems like a wart
    public typealias IntegerLiteralType = Element.IntegerLiteralType
    public init(integerLiteral value: DSPComplex.Element.IntegerLiteralType) {
        self.init(real:Element(value), imag:Element.zero)
    }

    public static let zero = DSPComplex(Element.zero, Element.zero)
    public static let nan = DSPComplex(Element.nan, Element.nan)

    public static func ==(_ a:Self, _ b:Self)->Bool {
        return a.real==b.real && a.imag==b.imag
    }

    public static func +(_ a:Self, _ b:Self)->Self {
        return Self(a.real+b.real, a.imag+b.imag)
    }
    
    public static func +(_ a:Self, _ b:Element)->Self {
        return Self(a.real+b, a.imag)
    }
    
    public static func +(_ a:Element, _ b:Self)->Self {
        return Self(a+b.real, b.imag)
    }

    public static func +=(_ a:inout Self, _ b:Self) {
        a = a + b
    }
    
    public static func +=(_ a:inout Self, _ b:Element) {
        a = a + b
    }

    public static func -(_ a:Self, _ b:Self)->Self {
        return Self(a.real-b.real, a.imag-b.imag)
    }

    public static func -(_ a:Self, _ b:Element)->Self {
        return Self(a.real-b, a.imag)
    }
    
    public static func -(_ a:Element, _ b:Self)->Self {
        return Self(a-b.real, -b.imag)
    }
    
    public static prefix func -(_ a:Self)->Self {
        return Self(-a.real, -a.imag)
    }

    public static func -=(_ a:inout Self, _ b:Self) {
        a = a - b
    }
    
    public static func -=(_ a:inout Self, _ b:Element) {
        a = a - b
    }

    public static func *(_ a:Self, _ b:Self)->Self {
        return Self(a.real*b.real - a.imag*b.imag, a.real*b.imag + a.imag*b.real)
    }
    
    public static func *(_ a:Self, _ b:Element)->Self {
        return Self(a.real*b, a.imag*b)
    }
    
    public static func *(_ a:Element, _ b:Self)->Self {
        return Self(a*b.real, a*b.imag)
    }

    public static func *=(_ a:inout Self, _ b:Self) {
        a = a * b
    }
    
    public static func *=(_ a:inout Self, _ b:Element) {
        a = a * b
    }
    
    public static func /(_ a:Self, _ b:Self)->Self {
        return a * b.reciprocal()
    }

    public static func /(_ a:Self, _ b:Element)->Self {
        return Self(a.real/b, a.imag/b)
    }

    public static func /(_ a:Element, _ b:Self)->Self {
        return Self(a,0) / b
    }

    public static func /=(_ a:inout Self, _ b:Self) {
        a = a / b
    }

    public static func /=(_ a:inout Self, _ b:Element) {
        a = a / b
    }
    
    /// The ∞-norm of the value (`max(abs(real), abs(imaginary))`).
    public var magnitude: Magnitude {
        // https://github.com/apple/swift-numerics/blob/master/Sources/ComplexModule/Complex.swift
        return max(abs(real), abs(imag))
    }
    
    /// aka. magnitude, norm
    public func modulus()->Element {
        return (imag.isZero) ? abs(real) : hypotf(real, imag)
    }

    /// aka. phase
    public func argument()->Element {
        return atan2f(imag, real)
    }
    
    public func conjugate()->Self {
        return Self(real, -imag)
    }

    public func reciprocal()->Self {
        let s = real*real + imag*imag
        return Self(real/s, -imag/s)
    }

    public static func exp(_ a:Self)->Self {
        let e = expf(a.real)
        return Self(e*cosf(a.imag), e*sinf(a.imag))
    }
    
    public static func sin(_ a:Self)->Self {
        return Self(sinf(a.real)*coshf(a.imag), cosf(a.real)*sinhf(a.imag));
    }
    
    public static func cos(_ a:Self)->Self {
        return Self(cosf(a.real)*coshf(a.imag), -sinf(a.real)*sinhf(a.imag))
    }
    
    public static func tan(_ a:Self)->Self {
        return sin(a) / cos(a)
    }
    
    public func isAlmostEqual(_ b:Self, tolerance:Element=Element.ulpOfOne.squareRoot())->Bool {
        return (self-b).modulus() < tolerance
    }
    
    public var description:String {
        let sig = (imag.sign == .minus) ? "-" : "+"
        return "(\(real)\(sig)i\(imag.magnitude))"
    }
    
    public var debugDescription:String {
        let sig = (imag.sign == .minus) ? "-" : "+"
        return "(\(real)\(sig)i\(imag.magnitude))"
    }

}
