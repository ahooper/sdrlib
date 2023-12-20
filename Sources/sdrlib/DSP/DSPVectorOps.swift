//
//  DSPVectorOps.swift
//  sdrplay1
//
//  Created by Andy Hooper on 2023-02-03.
//

import Accelerate.vecLib.vDSP

#if false
extension ComplexSamples {
    
    mutating func withUnsafeMutablePointers<R>(_ body: (_ split:DSPSplitComplex) throws -> R) rethrows -> R {
        try real.withUnsafeMutableBufferPointer { real_bp in
            try imag.withUnsafeMutableBufferPointer { imag_bp in
                return try body(DSPSplitComplex(realp: real_bp.baseAddress!,
                                                imagp: imag_bp.baseAddress!))
            }
        }
    }
    
    func withUnsafePointers(_ body: (_ real:UnsafePointer<Element.Element>,
                                     _ imag:UnsafePointer<Element.Element>) -> Void) {
        real.withUnsafeBufferPointer { real_bp in
            imag.withUnsafeBufferPointer { imag_bp in
                return body(real_bp.baseAddress!, imag_bp.baseAddress!)
            }
        }
    }
    
}
#endif
#if false
struct DSPVectorOps {
    
    static public func add(_ a:RealSamples, _ b:RealSamples, _ sum:inout RealSamples) {
        let n = Swift.min(a.count, b.count)
        precondition(n <= sum.count)
        a.real.withUnsafeBufferPointer { a_bp in
            b.real.withUnsafeBufferPointer { b_bp in
                sum.real.withUnsafeMutableBufferPointer { sum_bp in
                    vDSP_vadd(a_bp.baseAddress!, 1,
                              b_bp.baseAddress!, 1,
                              sum_bp.baseAddress!, 1,
                              vDSP_Length(n))
                }
            }
        }
    }
    
    static public func add(_ a:RealSamples.ElementArray, _ b:[Float], _ sum:inout [Float]) {
        let n = Swift.min(a.count, b.count)
        precondition(n <= sum.count)
        a.withUnsafeBufferPointer { a_bp in
            b.withUnsafeBufferPointer { b_bp in
                sum.withUnsafeMutableBufferPointer { sum_bp in
                    vDSP_vadd(a_bp.baseAddress!, 1,
                              b_bp.baseAddress!, 1,
                              sum_bp.baseAddress!, 1,
                              vDSP_Length(n))
                }
            }
        }
    }

    static public func add(_ a:inout ComplexSamples, _ b:inout ComplexSamples, _ sum:inout ComplexSamples) {
        let n = Swift.min(a.count, b.count)
        precondition(n <= sum.count)
        a.withUnsafeMutablePointers { a_sp in
            b.withUnsafeMutablePointers { b_sp in
                sum.withUnsafeMutablePointers { sum_sp in
                    // need mutables for vDSP arguments
                    var a_msp = a_sp, b_msp = b_sp, sum_msp = sum_sp
                    vDSP_zvadd(&a_msp, 1,
                               &b_msp, 1,
                               &sum_msp, 1,
                               vDSP_Length(n))
                }
            }
        }
    }
        
    static public func multiply(_ a:inout ComplexSamples, aConjugate:Bool=false, _ b:inout ComplexSamples, _ prod:inout ComplexSamples) {
        let n = Swift.min(a.count, b.count)
        precondition(n <= prod.count)
        a.withUnsafeMutablePointers { a_sp in
            b.withUnsafeMutablePointers { b_sp in
                prod.withUnsafeMutablePointers { sum_sp in
                    // need mutables for vDSP arguments
                    var a_msp = a_sp, b_msp = b_sp, sum_msp = sum_sp
                    vDSP_zvmul(&a_msp, 1,
                               &b_msp, 1,
                               &sum_msp, 1,
                               vDSP_Length(n),
                               aConjugate ? -1 : +1)
                }
            }
        }
    }

}
#endif
