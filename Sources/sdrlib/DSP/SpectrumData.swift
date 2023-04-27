//
//  SpectrumData.swift
//  SimpleSDR3
//
//  Created by Andy Hooper on 2020-02-07.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//
//  liquid-dsp-1.3.1/src/fft/src/spgram.c
//
//  https://developer.apple.com/library/archive/documentation/Performance/Conceptual/vDSP_Programming_Guide/Introduction/Introduction.html
//  https://developer.apple.com/documentation/accelerate/vdsp/fast_fourier_transforms/finding_the_component_frequencies_in_a_composite_sine_wave?language=objc
//  https://developer.apple.com/documentation/accelerate/vdsp/vector_generation/using_windowing_with_discrete_fourier_transforms
//
//  Apple doc. says "Use the DFT routines instead of these wherever possible.", but does not explain why.
//  Answer in forum https://forums.developer.apple.com/thread/23321
//
//  Various similar vDSP FFT usage:
//  http://www.myuiviews.com/2016/03/04/visualizing-audio-frequency-spectrum-on-ios-via-accelerate-vdsp-fast-fourier-transform.html
//  https://github.com/AlbanPerli/iOS-Spectrogram
//  https://gist.github.com/hotpaw2/f108a3c785c7287293d7e1e81390c20b
//  https://stackoverflow.com/q/32891012
//  https://github.com/jasminlapalme/caplaythrough-swift/blob/master/CAPlayThroughSwift/FFTHelper.swift
//  https://github.com/liscio/SMUGMath-Swift/blob/master/SMUGMath/FFTOperations.swift

import Accelerate.vecLib.vDSP
import class Foundation.NSLock

#if false
// exponential averaging
class SpectrumDataE: Sink<ComplexSamples> {
    let N:Int, /// FFT length
        D:Int  /// FFT segment spacing
    private let dft:vDSP_DFT_Setup
    private var window:[Float]
    private var fftTime, fftFreq, fftFMagSq: ComplexSamples
    private var fftAverage, fftDb:[Float]
    var alpha:Float // exponential averaging (first-order IIR), mutable for vDSP argument
    var numberSummed:UInt
    private var carry:Input
    private var zeroReference:[Float]
    private let readLock:NSLock
    private var initialValue = Float(1.0e-15) //-150dB ensure non-zero for logarithm, need a var for vDSP_vfill
    var centreHz:Double = 0

    /// The supported values for fftLength are f * 2**n, where f is 1, 3, 5, or 15 and n is at least 3.
    init(source:BufferedSource<Input>?, fftLength:UInt, overlap:UInt=0, windowFunction:WindowFunction.Function=WindowFunction.hann) {
        N = Int(fftLength)
        // let vDSP_DFT_zop_CreateSetup check fftLength
        precondition(overlap < fftLength)
        D = Int(fftLength - overlap)
        let noPrevious = OpaquePointer(bitPattern: 0) // NULL
        dft = vDSP_DFT_zop_CreateSetup(noPrevious, vDSP_Length(N), vDSP_DFT_Direction.FORWARD)!
        window = WindowFunction.Periodic(N, windowFunction)
        var sumsq: Float = 0 // scale to unit window, and apply FFT factor
        vDSP_svesq(window, 1, /*output*/&sumsq, vDSP_Length(N))
        var scale = sqrtf(2) / ( sqrtf(sumsq / Float(window.count)) * sqrtf(Float(N)) )
        vDSP_vsmul(window, 1, &scale, &window, 1, vDSP_Length(window.count))
        // initializing with NaN gives an exception for debugging if a value
        // is read before being set
        fftTime = ComplexSamples(repeating:Input.nan, count:N)
        fftFreq = ComplexSamples(repeating:Input.nan, count:N)
        fftFMagSq = ComplexSamples(repeating:Input.zero, count:N)
        fftAverage = [Float](repeating:initialValue, count:N)
        fftDb = [Float](repeating:Float.signalingNaN, count:N)
        carry = Input()
        carry.reserveCapacity(N)
        alpha = 0.1
        numberSummed = 0
        zeroReference = [Float](repeating:1.0, count:N)  // 1 = full scale
        readLock = NSLock()
        super.init("SpectrumData", source)
    }
    
    deinit {
        vDSP_DFT_DestroySetup(dft)
    }
    
    /// run one FFT block and sum the result for averaging
    func transformAndSum(_ samples: Input, _ range:Range<Int>) {
        //print("SpectrumData transformAndSum",samples.count,range)
        precondition(range.count == N)
        // apply window
        assert(fftTime.count==N)
        // can't use vDSP_zrvmul as samples is not mutable, but I and Q can
        // be multiplied independently since window coefficients are real
        samples.real.withUnsafeBufferPointer { in_sp in
            fftTime.real.withUnsafeMutableBufferPointer { out_sp in
                vDSP_vmul(in_sp.baseAddress!.advanced(by: range.startIndex), 1,
                          window, 1,
                          out_sp.baseAddress!, 1,
                          vDSP_Length(N))
            }
        }
        samples.imag.withUnsafeBufferPointer { in_sp in
            fftTime.imag.withUnsafeMutableBufferPointer { out_sp in
                vDSP_vmul(in_sp.baseAddress!.advanced(by: range.startIndex), 1,
                          window, 1,
                          out_sp.baseAddress!, 1,
                          vDSP_Length(N))
            }
        }
        // perform FFT
        assert(fftTime.count==N && fftFreq.count==N)
        fftTime.withUnsafeMutablePointers { in_sp in
            fftFreq.withUnsafeMutablePointers { out_sp in
                vDSP_DFT_Execute(dft, in_sp.realp, in_sp.imagp, out_sp.realp, out_sp.imagp)
            }
        }
        // multiply by conjugate to get magnitude squared, which will be in the real part
        fftFreq.withUnsafeMutablePointers { f_sp in
            fftFMagSq.withUnsafeMutablePointers { msq_sp in
                // need mutables for vDSP arguments
                var f_msp = f_sp, msq_msp = msq_sp
                vDSP_zvmul(&f_msp, 1,
                           &f_msp, 1,
                           &msq_msp, 1,
                           vDSP_Length(N),
                           /*aConjugate*/-1)
            }
        }

        // multiply and add to average
        fftFMagSq.real.withUnsafeMutableBufferPointer { msq_bp in
            fftAverage.withUnsafeMutableBufferPointer { avg_bp in
                // avg = avg*(1-α) + msq*α
                var oneMinusAlpha = 1 - alpha // vDSP needs mutable
                // E[n] = A[n]*B + C[n]*D;
                vDSP_vsmsma(/*A*/avg_bp.baseAddress!, 1,
                            /*B*/&oneMinusAlpha,
                            /*C*/msq_bp.baseAddress!, 1,
                            /*D*/&alpha,
                            /*E*/avg_bp.baseAddress!, 1,
                            /*N*/vDSP_Length(N))
            }
        }

    }

    /// match sample stream to FFT size
    // most of the FFT calls are made directly from the input area,
    // with a carry over between calls for the remainder

    override func process(_ input:Input) {
        //print(name, "process", input.count)
        var sampleIndex = 0
        readLock.lock(); defer {readLock.unlock()}
        
        /*
         N = 8, D = 4
         ccccciiiiiiiiiiiii scenario 5 in carry, 13 input
         --------           transform 8 from carry 0..<8
             --------       transform 8 from carry plus input 4..<12
                 --------   transform 8 from input 3..<11
                     cccccc 6 input to carry
        */
        if carry.count > 0 {
            var carryIndex = 0
            let ni = N - (carry.count % D) // number of samples to complete carry
            sampleIndex = N - (carry.count % N) // where transforms will start after carry processed
            //print("SpectrumData process", carry.count, input.count, ni, sampleIndex)
            if ni > input.count {
                // insufficient input to perform a transform, carry all to next call
                carry.append(rangeOf:input, 0..<input.count)
                return
            }
            carry.append(rangeOf:input, 0..<ni)
            while carryIndex + N <= carry.count {
                //print("SpectrumData process", carryIndex)
                transformAndSum(carry, carryIndex..<(carryIndex+N))
                carryIndex += D
            }
            carry.removeAll(keepingCapacity:true)
        }
        while sampleIndex + N <= input.count {
            transformAndSum(input, sampleIndex..<(sampleIndex+N))
            sampleIndex += D
        }
        // carry to next call
        if sampleIndex < input.count {
            precondition(carry.isEmpty)
            carry.append(rangeOf:input, sampleIndex..<input.count)
        }
        
        numberSummed += 1
    }
    
    /// Convert running average magnitude squared to decibels, and rotate
    /// 0 frequency to the middle for display.
    func getdBandClear(_ data :inout [Float]) {
        precondition(data.count == N)
        assert(fftAverage.count == N)
        readLock.lock(); defer {readLock.unlock()}
        // calculate log10(magnitude squared)*10 (decibels)
        // the squaring is not scaled out so this is now 20*log(magnitude), i.e. power
        vDSP_vdbcon(&fftAverage, 1,
                    &zeroReference,
                    /*output*/&fftDb, 1,
                    vDSP_Length(N), 0/*amplitude*/)
        var scale = Float(1)
        // rotate freq[0] to centre of data array [N/2]
        let Nover2 = N/2
        data.withUnsafeMutableBufferPointer { dataPtr in
            fftDb.withUnsafeBufferPointer { dbPtr in
                vDSP_vsadd(dbPtr.baseAddress!, 1,
                           &scale,
                           /*output*/dataPtr.baseAddress!.advanced(by: Int(Nover2)), 1,
                           vDSP_Length(Nover2))
                vDSP_vsadd(dbPtr.baseAddress!.advanced(by: Int(Nover2)), 1,
                           &scale,
                           /*output*/dataPtr.baseAddress!, 1,
                           vDSP_Length(Nover2))
            }
        }
        // TODO: reset fftAverage?
        numberSummed = 0
    }
    
    func sampleFrequency()-> Double {
        source!.sampleFrequency()
    }

    static func mock()->SpectrumDataE {
        let mockSource = Oscillator<ComplexSamples>(signalHz: 0, sampleHz: 1)
        return SpectrumDataE(source: mockSource, fftLength: 4)
    }

}
#endif

// Arithmetic average
class SpectrumData: Sink<ComplexSamples> {
    let N:Int, /// FFT length
        D:Int  /// FFT segment spacing
    private let dft:vDSP_DFT_Setup
    private var window:[Float]
    private var fftTime, fftFreq, fftFMagSq: ComplexSamples
    private var fftSum:[Float]
    var numberSummed:UInt
    private var carry:Input
    private var zeroReference:[Float]
    private let readLock:NSLock
    private var sumInitialValue = Float(1.0e-15) //-150dB ensure non-zero for logarithm, need a var for vDSP_vfill
    var centreHz:Double = 0

    /// The supported values for fftLength are f * 2**n, where f is 1, 3, 5, or 15 and n is at least 3.
    init(source:BufferedSource<Input>?, fftLength:UInt, overlap:UInt=0, windowFunction:WindowFunction.Function=WindowFunction.hann) {
        N = Int(fftLength)
        // let vDSP_DFT_zop_CreateSetup check fftLength
        precondition(overlap < fftLength)
        D = Int(fftLength - overlap)
        let noPrevious = OpaquePointer(bitPattern: 0) // NULL
        dft = vDSP_DFT_zop_CreateSetup(noPrevious, vDSP_Length(N), vDSP_DFT_Direction.FORWARD)!
        window = WindowFunction.Periodic(N, windowFunction)
        var sumsq: Float = 0 // scale to unit window, and apply FFT factor
        vDSP_svesq(window, 1, /*output*/&sumsq, vDSP_Length(N))
        var scale = sqrtf(2) / ( sqrtf(sumsq / Float(window.count)) * sqrtf(Float(N)) )
        vDSP_vsmul(window, 1, &scale, &window, 1, vDSP_Length(window.count))
        // initializing with NaN gives an exception for debugging if a value
        // is read before being set
        fftTime = ComplexSamples(repeating:Input.nan, count:N)
        fftFreq = ComplexSamples(repeating:Input.nan, count:N)
        fftFMagSq = ComplexSamples(repeating:Input.zero, count:N)
        fftSum = [Float](repeating:sumInitialValue, count:N)
        carry = Input()
        carry.reserveCapacity(N)
        numberSummed = 0
        zeroReference = [Float](repeating:1.0, count:N)  // 1 = full scale
        readLock = NSLock()
        super.init("SpectrumData", source)
    }
    
    deinit {
        vDSP_DFT_DestroySetup(dft)
    }
    
    /// run one FFT block and sum the result for averaging
    func transformAndSum(_ samples: Input, _ range:Range<Int>) {
        //print("SpectrumData transformAndSum",samples.count,range)
        precondition(range.count == N)
        // apply window
        assert(fftTime.count==N)
        // can't use vDSP_zrvmul as samples is not mutable, but I and Q can
        // be multiplied independently since window coefficients are real
        samples.real.withUnsafeBufferPointer { in_sp in
            fftTime.real.withUnsafeMutableBufferPointer { out_sp in
                vDSP_vmul(in_sp.baseAddress!.advanced(by: range.startIndex), 1,
                          window, 1,
                          out_sp.baseAddress!, 1,
                          vDSP_Length(N))
            }
        }
        samples.imag.withUnsafeBufferPointer { in_sp in
            fftTime.imag.withUnsafeMutableBufferPointer { out_sp in
                vDSP_vmul(in_sp.baseAddress!.advanced(by: range.startIndex), 1,
                          window, 1,
                          out_sp.baseAddress!, 1,
                          vDSP_Length(N))
            }
        }
        // perform FFT
        assert(fftTime.count==N && fftFreq.count==N)
        fftTime.withUnsafeMutablePointers { in_sp in
            fftFreq.withUnsafeMutablePointers { out_sp in
                vDSP_DFT_Execute(dft, in_sp.realp, in_sp.imagp, out_sp.realp, out_sp.imagp)
            }
        }
        // multiply by conjugate to get magnitude squared, which will be in the real part
        fftFreq.withUnsafeMutablePointers { f_sp in
            fftFMagSq.withUnsafeMutablePointers { msq_sp in
                // need mutables for vDSP arguments
                var f_msp = f_sp, msq_msp = msq_sp
                vDSP_zvmul(&f_msp, 1,
                           &f_msp, 1,
                           &msq_msp, 1,
                           vDSP_Length(N),
                           /*aConjugate*/-1)
            }
        }

        // add to sum for averaging TODO: integrating factors gamma,alpha
        fftFMagSq.real.withUnsafeBufferPointer { msq_bp in
            fftSum.withUnsafeMutableBufferPointer { sum_bp in
                vDSP_vadd(msq_bp.baseAddress!, 1,
                          sum_bp.baseAddress!, 1,
                          sum_bp.baseAddress!, 1,
                          vDSP_Length(N))
            }
        }

        numberSummed += 1
    }

    /// match sample stream to FFT size
    // most of the FFT calls are made directly from the input area,
    // with a carry over between calls for the remainder

    override func process(_ input:Input) {
        var sampleIndex = 0
        readLock.lock(); defer {readLock.unlock()}
        
        /*
         N = 8, D = 4
         ccccciiiiiiiiiiiii scenario 5 in carry, 13 input
         --------           transform 8 from carry 0..<8
             --------       transform 8 from carry plus input 4..<12
                 --------   transform 8 from input 3..<11
                     cccccc 6 input to carry
        */
        if carry.count > 0 {
            var carryIndex = 0
            let ni = N - (carry.count % D) // number of samples to complete carry
            sampleIndex = N - (carry.count % N) // where transforms will start after carry processed
            //print("SpectrumData process", carry.count, input.count, ni, sampleIndex)
            if ni > input.count {
                // insufficient input to perform a transform, carry all to next call
                carry.append(rangeOf:input, 0..<input.count)
                return
            }
            carry.append(rangeOf:input, 0..<ni)
            while carryIndex + N <= carry.count {
                //print("SpectrumData process", carryIndex)
                transformAndSum(carry, carryIndex..<(carryIndex+N))
                carryIndex += D
            }
            carry.removeAll(keepingCapacity:true)
        }
        while sampleIndex + N <= input.count {
            transformAndSum(input, sampleIndex..<(sampleIndex+N))
            sampleIndex += D
        }
        // carry to next call
        if sampleIndex < input.count {
            precondition(carry.isEmpty)
            carry.append(rangeOf:input, sampleIndex..<input.count)
        }
    }
    
    /// Complete the FFT average, convert to decibels, and rotate
    /// 0 frequency to the middle for display.
    func getdBandClear(_ data :inout [Float]) {
        precondition(data.count == N)
        if numberSummed == 0 {
            // no data
            var fill = 10.0*log10f(sumInitialValue) // need mutable for vDSP_vfill
            vDSP_vfill(&fill, &data, 1, vDSP_Length(N))
            return
        }
        //print("SpectrumData getdBandClear", "numberSummed", numberSummed)
        assert(fftSum.count == N)
        readLock.lock(); defer {readLock.unlock()}
        // calculate log10(magnitude squared)*10 (decibels)
        // the squaring is not scaled out so this is now 20*log(magnitude), i.e. power
        vDSP_vdbcon(&fftSum, 1,
                    &zeroReference,
                    /*output*/&fftSum, 1,
                    vDSP_Length(N), 0/*amplitude*/)
        var scale = -10.0*log10f(Float(numberSummed)) // divide for average by subtracting logarithm
        // apply scale and rotate freq[0] to centre of data array [N/2]
        let Nover2 = N/2
        data.withUnsafeMutableBufferPointer { dataPtr in
            fftSum.withUnsafeBufferPointer { sumPtr in
                vDSP_vsadd(sumPtr.baseAddress!, 1,
                           &scale,
                           /*output*/dataPtr.baseAddress!.advanced(by: Int(Nover2)), 1,
                           vDSP_Length(Nover2))
                vDSP_vsadd(sumPtr.baseAddress!.advanced(by: Int(Nover2)), 1,
                           &scale,
                           /*output*/dataPtr.baseAddress!, 1,
                           vDSP_Length(Nover2))
            }
        }
        // clear accumulation, but leave carrying samples
        vDSP_vfill(&sumInitialValue, &fftSum, 1, vDSP_Length(N))
        numberSummed = 0
    }
    
    func sampleFrequency()-> Double {
        source?.sampleFrequency() ?? Double.signalingNaN
    }

    static func mock()->SpectrumData {
        let mockSource = Oscillator<ComplexSamples>(signalHz: 0, sampleHz: 1)
        return SpectrumData(source: mockSource, fftLength: 4)
    }

}
