//
//  SplitComplex.swift
//  sdrx
//
//  Created by Andy Hooper on 2023-12-02.
//

import struct Accelerate.vecLib.vDSP.DSPComplex
import struct Accelerate.vecLib.vDSP.DSPSplitComplex
import struct Accelerate.vecLib.vDSP.vDSP_Length

public struct SplitComplex: DSPSamples {
    public typealias Element = DSPComplex
    public typealias ComponentArray = ContiguousArray<Element.Element>
    var re, im: ComponentArray
    public static let zero = DSPComplex(.zero, .zero)
    public static var nan = DSPComplex(.nan, .nan)

    public init() {
        re = ComponentArray()
        im = ComponentArray()
    }

    public init(repeating: Element, count: Int) {
        re = ComponentArray(repeating: repeating.real, count: count)
        im = ComponentArray(repeating: repeating.imag, count: count)
    }

    public init<T:Sequence<Element>>(_ a: T) {
        re = ComponentArray(a.map{ $0.real })
        im = ComponentArray(a.map{ $0.imag })
    }

    public init(_ a: Array<Element.Element>) {
        re = ComponentArray(a)
        im = ComponentArray(repeating: Float.zero, count: a.count)
    }

    public typealias Index = ComponentArray.Index
    public typealias Indices = ComponentArray.Indices

    public var startIndex: Index { re.startIndex }
    
    public var endIndex: Index { re.endIndex }

    public func index(before i: Index) -> Int { re.index(before: i) }

    public func index(after i: Index) -> Int { re.index(after: i) }

    public subscript(position: ComponentArray.Index) -> DSPComplex {
        get {
            DSPComplex(re[position], im[position])
        }
        set {
            re[position] = newValue.real
            im[position] = newValue.imag
        }
    }
    
    public mutating func replaceSubrange<C>(_ subrange: Range<ComponentArray.Index>, with newElements: C) where C : Collection, DSPComplex == C.Element {
        //print("\(#function) Collection")
        re.replaceSubrange(subrange, with: newElements.map{ $0.real })
        im.replaceSubrange(subrange, with: newElements.map{ $0.imag })
    }
    
    public mutating func replaceSubrange(_ r: Range<Int>, with: SplitComplex, _ w: Range<Int>) {
        // could eliminate this function by implementing SubSequence
        re.replaceSubrange(r, with: with.re[w])
        im.replaceSubrange(r, with: with.im[w])
    }

    public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        re.removeAll(keepingCapacity: keepCapacity)
        im.removeAll(keepingCapacity: keepCapacity)
    }
    
    public mutating func reserveCapacity(_ n: Int) {
        re.reserveCapacity(n)
        im.reserveCapacity(n)
    }
    
    var capacity: Int { re.capacity }
    
    public mutating func append(_ newElement: Element) {
        re.append(newElement.real)
        im.append(newElement.imag)
    }
    
    public mutating func append(contentsOf newElements: Self) {
        re.append(contentsOf: newElements.re)
        im.append(contentsOf: newElements.im)
    }

    public mutating func append<T:Sequence<Element>>(contentsOf a: T) {
        re.append(contentsOf: a.map{ $0.real })
        im.append(contentsOf: a.map{ $0.imag })
    }

    public mutating func append<T:Sequence<Element.Element>>(real: T, imag: T) {
        re.append(contentsOf: real)
        im.append(contentsOf: imag)
        assert(re.count == im.count)
    }
    
    public mutating func append(rangeOf X:Self, _ range:Range<Int>) {
        re.append(contentsOf: X.re[range])
        im.append(contentsOf: X.im[range])
        assert(re.count == im.count)
    }
    
    public mutating func resize(_ newCount:Int) {
        if count > newCount {
            removeSubrange(newCount..<(count))
        } else if count < newCount {
            append(contentsOf:repeatElement(Element.nan, count:newCount-count))
        }
    }

    public func withUnsafeBufferPointers<Result>(_ body: (UnsafeBufferPointer<Element.Element>,
                                                          UnsafeBufferPointer<Element.Element>
                                                                    ) throws -> Result) rethrows -> Result? {
        try re.withUnsafeBufferPointer { reBuf in
            try im.withUnsafeBufferPointer { imBuf in
                return try body(reBuf, imBuf)
            }
        }
    }
    
    public func withUnsafeSplitPointers<Result>(_ body: (UnsafePointer<DSPSplitComplex>) throws -> Result) rethrows -> Result? {
        try withUnsafeBufferPointers { reBuf, imBuf in
            var split = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: reBuf.baseAddress! + reBuf.startIndex),
                                        imagp: UnsafeMutablePointer(mutating: imBuf.baseAddress! + imBuf.startIndex))
            return try body(&split)
        }
    }

    public func zip()->[Element] {
        Swift.zip(re,im).map{Element($0.0,$0.1)}
    }

}
