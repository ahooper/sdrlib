//
//  DSPSamples.swift
//  SDRplayFM
//
//  Created by Andy Hooper on 2020-03-17.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import struct Accelerate.vecLib.vDSP.DSPComplex
import struct Accelerate.vecLib.vDSP.vDSP_Length
import func Accelerate.vecLib.vDSP.vDSP_dotpr
import func CoreFoundation.cosf
import func CoreFoundation.sinf

public protocol DSPScalar: Numeric {
    init(_ real:Float)
    static func *(lhs:Self, rhs:Float) -> Self
    static func /(lhs:Self, rhs:Float) -> Self
    static func polar(_ phase:Float, _ level:Float) -> Self
    var magnitude: Float { get }
    func modulus()-> Float
}

extension Float: DSPScalar {
    public func modulus() -> Float {
        abs(self)
    }
    public static func polar(_ phase:Float, _ level:Float) -> Self {
        cosf(phase) * level
    }
}

extension DSPComplex: DSPScalar {
    public static func polar(_ phase:Float, _ level:Float) -> Self {
        DSPComplex(cosf(phase) * level,
                   sinf(phase) * level)
    }
}

public protocol DSPSamples: RangeReplaceableCollection, RandomAccessCollection, MutableCollection where Element: DSPScalar, Index == Int {
    static var zero:Element { get }
    static var nan:Element { get }
    mutating func resize(_ newCount:Int)
    //
    mutating func replaceSubrange(_ r:Range<Int>, with:Self, _ w:Range<Int>)
}

public typealias RealSamples = ContiguousArray<Float>

extension RealSamples: DSPSamples {
    public static var zero = Element.zero
    public static var nan = Element.nan
    public mutating func resize(_ newCount:Int) {
        if count > newCount {
            removeSubrange(newCount..<(count))
        } else if count < newCount {
            //if newCount > capacity { reserveCapacity(newCount) }
            append(contentsOf:repeatElement(Element.nan, count:newCount-count))
        }
    }
    // like  replaceSubrange<C, R>(R, with: C) on a slice but without having to implement
    // slices for SplitComplex
    public mutating func replaceSubrange(_ r:Range<Int>, with:Self, _ w:Range<Int>) {
        replaceSubrange(r, with:with[w])
    }
}

public typealias ComplexSamples = SplitComplex
