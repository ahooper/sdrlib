//
//  DotProduct.swift
//  sdrx2
//
//  Created by Andy Hooper on 2023-12-17.
//

import struct Accelerate.vecLib.vDSP.DSPComplex
import struct Accelerate.vecLib.vDSP.DSPSplitComplex
import struct Accelerate.vecLib.vDSP.vDSP_Length
import func Accelerate.vecLib.vDSP.vDSP_dotpr
import func Accelerate.vecLib.vDSP.vDSP_zdotpr

extension RealSamples {
    public func dotProduct(at: Index, _ h: [Float]) -> Element {
        withContiguousStorageIfAvailable { xbuf in
            h.withUnsafeBufferPointer { hbuf in
                var o = Element.zero
                vDSP_dotpr(xbuf.baseAddress! + xbuf.startIndex + at, 1,
                           hbuf.baseAddress!, 1,
                           &o, vDSP_Length(hbuf.count))
                return o
            }
        }! // must have ContiguousStorage
    }
    public func dotProduct(at: Int, _ h: SplitComplex) -> DSPComplex {
        fatalError("\(#function) not implemented")
    }
}

extension SplitComplex {
    public func dotProduct(at: Index, _ h: [Float]) -> Element {
        withUnsafeBufferPointers { rebuf, imbuf in
            h.withUnsafeBufferPointer { hbuf in
                var o = DSPComplex.zero
                vDSP_dotpr(rebuf.baseAddress! + rebuf.startIndex + at, 1,
                           hbuf.baseAddress!, 1,
                           &o.real, vDSP_Length(hbuf.count))
                vDSP_dotpr(imbuf.baseAddress! + imbuf.startIndex + at, 1,
                           hbuf.baseAddress!, 1,
                           &o.imag, vDSP_Length(hbuf.count))
                return o
            }
        }! // must succeed
    }
    
    public func dotProduct(at: Int, _ h: SplitComplex) -> DSPComplex {
        withUnsafeSplitPointers { xsplit in
            h.withUnsafeSplitPointers { hsplit in
                let o = SplitComplex([Float.zero])
                o.withUnsafeSplitPointers { osplit in
                    vDSP_zdotpr(xsplit + at, 1, hsplit, 1, osplit, vDSP_Length(h.count))
                }! // must succeed
                return o[0]
            }! // must succeed
        }! // must succeed
    }
}
