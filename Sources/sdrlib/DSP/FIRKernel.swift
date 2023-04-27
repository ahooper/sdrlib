//
//  FIRKernel.swift
//  SimpleSDR
//
//  Calculate kernel coefficients for FIR filters.
//
//  Created by Andy Hooper on 2019-10-17.
//  Copyright © 2019 Andy Hooper. All rights reserved.
//

import func CoreFoundation.cosf
import func CoreFoundation.sinf
import func CoreFoundation.sqrtf
import func CoreFoundation.powf
import func CoreFoundation.ceilf
import func CoreFoundation.log10f
import struct Accelerate.vecLib.vDSP.DSPComplex
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public enum FIRKernel {
    
    // From http://www.labbookpages.co.uk/audio/firWindowing.html
    // https://www.st.com/resource/en/design_tip/dm00446489-fir-filter-design-by-sampling-windowing-and-modulating-the-sinc-function-stmicroelectronics.pdf
    
    
    /// Create a windowed sinc function for a filter with one transition (low and high pass filters).
    /// - Parameter filterLength: the number of taps in the filter
    /// - Parameter normalizedTransitionFrequency: the normalized transition frequency
    /// - Parameter highNotLowPass: true for a high pass filter, false for low pass
    /// - Parameter windowFunction: the response shaping window function to apply
    /// - Returns: the filter kernel array
    public static func sincKernel(filterLength:Int,
                          normalizedTransitionFrequency:Float,
                          highNotLowPass:Bool,
                                  windowFunction:WindowFunction.Function,
                          gain:Float=1.0) -> [Float] {
        var out = [Float](repeating:0, count:filterLength)
        let halfLength = filterLength / 2  // truncated
        let M = filterLength - 1, // order of the filter
            m_2 = 0.5 * Float(M)

        var ft = normalizedTransitionFrequency
        precondition(ft <= 0.5, "FIRKernel sincKernel: Normalized transition frequency exceeds 0.5");
        var sum: Float = 0

        // Set centre tap, if present. This avoids a divide by zero.
        if 2*halfLength != filterLength {
            var val = 2.0 * ft

            // If we want a high pass filter, subtract sinc function from a Dirac pulse
            if highNotLowPass { val = 1.0 - val }

            out[halfLength] = val
            sum += val
        } else {
            precondition(!highNotLowPass, "FIRKernel sincKernel: For high pass filter, window length must be odd");
        }

        // This has the effect of inverting all weight values
        if highNotLowPass { ft = -ft }

        // Calculate taps. Due to symmetry, only need to calculate half the window
        for n in 0..<halfLength {
            let val = sincSample(ft, n, m_2)
            let winVal = val * windowFunction(n, M) // Apply the windowing function
            out[n] =                winVal
            out[filterLength-n-1] = winVal
            sum += 2 * winVal
        }
        
        // Scale for requested gain (default unity)
        if !gain.isNaN {
            for n in 0..<filterLength {
                out[n] *= gain / sum
            }
        }

        return out
    }
    
    fileprivate static func sincSample(_ ft: Float, _ n: Int, _ m_2: Float) -> Float {
        if Float(n) == m_2 { return 2.0*ft } // sin x ≅ x for small x
        return sinf(2.0 * Float.pi * ft * (Float(n)-m_2)) / (Float.pi * (Float(n)-m_2))
    }

    /// Create two windowed sinc functions for a filter with two transitions (band pass and band stop filters).
    public static func dualSincKernel(filterLength:Int,
                               normalizedTransition1Frequency:Float,
                               normalizedTransition2Frequency:Float,
                               bandStopNotPass:Bool,
                                      windowFunction:WindowFunction.Function,
                               gain:Float=1.0) -> [Float] {
        var out = [Float](repeating:0, count:filterLength)
        let halfLength = filterLength / 2  // truncated
        let M = filterLength - 1, // order of the filter
            m_2 = 0.5 * Float(M)

        var ft1 = normalizedTransition1Frequency
        var ft2 = normalizedTransition2Frequency
        var sum: Float = 0

        // Set centre tap.
        precondition(2*halfLength != filterLength, "FIRKernel dualSincKernel: For band pass and band stop filters, window length must be odd");
        var val = 2.0 * (ft2 - ft1)

        // If we want a band stop filter, subtract sinc functions from a Dirac pulse
        if bandStopNotPass { val = 1.0 - val }

        out[halfLength] = val

        // Swap transition points if Band Stop
        if bandStopNotPass { swap(&ft1,&ft2) }

        // Calculate taps. Due to symmetry, only need to calculate half the window
        for n in 0..<halfLength {
            let val1 = sincSample(ft1, n, m_2)
            let val2 = sincSample(ft2, n, m_2)
            let winVal = (val2 - val1) * windowFunction(n, M) // Apply the windowing function
            out[n] =                winVal
            out[filterLength-n-1] = winVal
            sum += 2 * winVal
        }
        
        // Scale for requested gain (default unity)
        if !gain.isNaN {
            for n in 0..<filterLength {
                out[n] *= gain / sum;
            }
        }

        return out
    }
    
    public static func lowPass(filterLength:Int,
                        transitionFrequency:Float,
                        sampleFrequency:Float,
                        windowFunction:WindowFunction.Function=WindowFunction.blackman,
                        gain:Float=1.0)
                    ->[Float] {
        return sincKernel(filterLength:filterLength,
                          normalizedTransitionFrequency:transitionFrequency/sampleFrequency,
                          highNotLowPass:false,
                          windowFunction:windowFunction,
                          gain:gain)
    }
    
    public static func highPass(filterLength:Int,
                         transitionFrequency:Float,
                         sampleFrequency:Float,
                         windowFunction:WindowFunction.Function=WindowFunction.blackman,
                         gain:Float=1.0)
                    ->[Float] {
        return sincKernel(filterLength:filterLength,
                          normalizedTransitionFrequency:transitionFrequency/sampleFrequency,
                          highNotLowPass:true,
                          windowFunction:windowFunction,
                          gain:gain)
    }
    
    public static func bandPass(filterLength:Int,
                         transition1Frequency:Float,
                         transition2Frequency:Float,
                         sampleFrequency:Float,
                         windowFunction:WindowFunction.Function=WindowFunction.blackman,
                         gain:Float=1.0)
                    ->[Float] {
        return dualSincKernel(filterLength:filterLength,
                              normalizedTransition1Frequency:transition1Frequency/sampleFrequency,
                              normalizedTransition2Frequency:transition2Frequency/sampleFrequency,
                              bandStopNotPass:false,
                              windowFunction:windowFunction,
                              gain:gain)
    }
    
    public static func bandStop(filterLength:Int,
                         transition1Frequency:Float,
                         transition2Frequency:Float,
                         sampleFrequency:Float,
                         windowFunction:WindowFunction.Function=WindowFunction.blackman,
                         gain:Float=1.0)
                    ->[Float] {
        return dualSincKernel(filterLength:filterLength,
                              normalizedTransition1Frequency:transition1Frequency/sampleFrequency,
                              normalizedTransition2Frequency:transition2Frequency/sampleFrequency,
                              bandStopNotPass:true,
                              windowFunction:windowFunction,
                              gain:gain)
    }


    /// Compute the Kaiser parameter `beta`, given the desired attenuation.
    /// - Parameter attenuation: The desired attenuation in the stopband and
    /// maximum ripple in the passband, in dB.  This should be a *positive* number.
    /// - Returns: The `beta` parameter to be used in the formula for a Kaiser window.
    /// In Kaiser's paper this is defined as α, not β. JOSmith says α = β / π
    // Source: scipy-1.2.2/scipy/signal/fir_filter_design.py
    public static func kaiser_beta(attenuation:Float) -> Float {
        if attenuation > 50 {
            return 0.1102 * (attenuation - 8.7)
        } else if attenuation > 21 {
            return 0.5842 * powf(attenuation - 21, 0.4) + 0.07886 * (attenuation - 21)
        } else {
            return 0.0
        }
    }
    
    /// Determine the filter window parameters for the Kaiser window method.
    /// The parameters returned by this function are generally used to create
    /// a finite impulse response filter using the window method.
    /// - Parameter ripple: Upper bound for the deviation (in dB) of the magnitude of the
    /// filter's frequency response from that of the desired filter (not
    /// including frequencies in any transition intervals).  That is, if `w`
    /// is the frequency expressed as a fraction of the Nyquist frequency,
    /// `A(w)` is the actual frequency response of the filter and `D(w)` is the
    /// desired frequency response, the design requirement is that:
    ///     `abs(A(w) - D(w))) < 10**(-ripple/20)`
    /// for `0 <= w <= 1` and `w` not in a transition interval.
    /// - Parameter width: Width of transition region, normalized so that `1` corresponds to `π`
    /// radians / sample.  That is, the frequency is expressed as a fraction of the Nyquist frequency.
    /// - Returns: the tuple `(numtaps:Int, beta:Float)`, where `numtaps` is the length of the Kaiser window,
    /// and `beta` is the beta parameter for the Kaiser window.
    // Source: `scipy-1.2.2/scipy/signal/fir_filter_design.py`
    public static func kaiser_parameters(ripple:Float, width:Float) -> (Int,Float) {
        let a = abs(ripple)
        precondition(a >= 8, "kaiserord() Requested maximum ripple attentuation \(a) is too small for the Kaiser formula.")
        let beta = kaiser_beta(attenuation: a)

        let numtaps = (a - 7.95) / 2.285 / (Float.pi * width) + 1

        return (Int(ceilf(numtaps)), beta)
    }

    public static func kaiserLowPass(transitionFrequency:Float,
                              sampleFrequency:Float,
                              ripple:Float,
                              width:Float,
                              gain:Float=1.0)
                    ->[Float] {
        //TODO width relative to sampleFrequency
        let (filterLength,beta) = kaiser_parameters(ripple: ripple, width: width)
        return sincKernel(filterLength:filterLength,
                          normalizedTransitionFrequency:transitionFrequency/sampleFrequency,
                          highNotLowPass:false,
                          windowFunction:WindowFunction.kaiser(beta:beta),
                          gain:gain)
    }

    public static func kaiserLowPass(normalizedTransitionFrequency: Float,
                              ripple:Float,
                              width:Float,
                              gain:Float=1.0)
                    ->[Float] {
        let (filterLength,beta) = kaiser_parameters(ripple: ripple, width: width)
        return sincKernel(filterLength:filterLength,
                          normalizedTransitionFrequency:normalizedTransitionFrequency,
                          highNotLowPass:false,
                          windowFunction:WindowFunction.kaiser(beta:beta),
                          gain:gain)
    }

    // parameters used in liquid_firdes_kaiser
    public static func kaiserLowPass(filterLength: Int,
                                     normalizedTransitionFrequency: Float,
                                     stopBandAttenuation: Float,
                                     gain:Float=1.0)
                    ->[Float] {
        let beta = kaiser_beta(attenuation: stopBandAttenuation)
        return sincKernel(filterLength:filterLength,
                          normalizedTransitionFrequency:normalizedTransitionFrequency,
                          highNotLowPass:false,
                          windowFunction:WindowFunction.kaiser(beta:beta),
                          gain:gain)
    }

    public static func kaiserHighPass(transitionFrequency:Float,
                               sampleFrequency:Float,
                               ripple:Float,
                               width:Float,
                               gain:Float=1.0)
                    ->[Float] {
        //TODO width relative to sampleFrequency
        let (filterLength,beta) = kaiser_parameters(ripple: ripple, width: width)
        return sincKernel(filterLength:filterLength,
                           normalizedTransitionFrequency:transitionFrequency/sampleFrequency,
                           highNotLowPass:true,
                          windowFunction:WindowFunction.kaiser(beta:beta),
                           gain:gain)
    }
    
    public static func kaiserBandPass(transition1Frequency:Float,
                               transition2Frequency:Float,
                               sampleFrequency:Float,
                               ripple:Float,
                               width:Float,
                               gain:Float=1.0)
                    ->[Float] {
        //TODO width relative to sampleFrequency
        let (filterLength,beta) = kaiser_parameters(ripple: ripple, width: width)
        return dualSincKernel(filterLength:filterLength,
                              normalizedTransition1Frequency:transition1Frequency/sampleFrequency,
                              normalizedTransition2Frequency:transition2Frequency/sampleFrequency,
                              bandStopNotPass:false,
                              windowFunction:WindowFunction.kaiser(beta:beta),
                              gain:gain)
    }
    
    public static func kaiserBandStop(transition1Frequency:Float,
                               transition2Frequency:Float,
                               sampleFrequency:Float,
                               ripple:Float,
                               width:Float,
                               gain:Float=1.0)
                    ->[Float] {
        //TODO width relative to sampleFrequency
        let (filterLength,beta) = kaiser_parameters(ripple: ripple, width: width)
        return dualSincKernel(filterLength:filterLength,
                              normalizedTransition1Frequency:transition1Frequency/sampleFrequency,
                              normalizedTransition2Frequency:transition2Frequency/sampleFrequency,
                              bandStopNotPass:true,
                              windowFunction:WindowFunction.kaiser(beta:beta),
                              gain:gain)
    }
    
    public static func notch(filterSemiLength:Int,
                      normalizedNotchFrequency:Float,
                      stopBandAttenuation:Float)
                ->[Float] {
        // liquid-dsp-1.3.2/src/filter/src/firdes.c liquid_firdes_notch()
        // also see Yu, Mitra and Babić, "Design of linear phase FIR notch filters", 1990 https://www.ias.ac.in/article/fulltext/sadh/015/03/0133-0155
        precondition(normalizedNotchFrequency >= -0.5 && normalizedNotchFrequency <= 0.5, "notch(), frequency must be in [-0.5,0.5]")
        precondition(stopBandAttenuation >= 0, "notch() stop-band suppression must be greater than zero")
        
        let windowFunction = WindowFunction.kaiser(beta: kaiser_beta(attenuation: stopBandAttenuation))
        
        let length = 2 * filterSemiLength + 1
        //TODO: N ≌ (A + 6.35)/11.87 Δω
        var out=[Float](),
            sum:Float = 0
        for i in 0..<length {
            // tone at carrier frequency
            let p = -cosf(2.0 * Float.pi * normalizedNotchFrequency * Float(i - filterSemiLength))
            let winVal = p * windowFunction(i, length)
            out.append(winVal)
            sum += winVal * p
        }

        // scale for unity gain
        for i in 0..<length {
            out[i] /= sum
        }

        // add impulse
        out[filterSemiLength] += 1.0

        return out
    }
    
    public static func dcBlock(filterSemiLength:Int,
                               stopBandAttenuation:Float)
                ->[Float] {
        return notch(filterSemiLength:filterSemiLength,
                     normalizedNotchFrequency:0.0,
                     stopBandAttenuation:stopBandAttenuation)
    }
    
    public static func peak(filterSemiLength:Int,
                            normalizedPeakFrequency:Float,
                            stopBandAttenuation:Float)
                ->[Float] {
        // inverse of notch
        precondition(normalizedPeakFrequency >= -0.5 && normalizedPeakFrequency <= 0.5, "peak(), frequency must be in [-0.5,0.5]")
        precondition(stopBandAttenuation >= 0, "peak() stop-band suppression must be greater than zero")
        
        let windowFunction = WindowFunction.kaiser(beta: kaiser_beta(attenuation: stopBandAttenuation))
        
        let length = 2 * filterSemiLength + 1
        var out=[Float](),
            sum:Float = 0
        for i in 0..<length {
            // tone at carrier frequency
            let p = cosf(2.0 * Float.pi * normalizedPeakFrequency * Float(i - filterSemiLength))
            let winVal = p * windowFunction(i, length)
            out.append(winVal)
            sum += winVal
        }

        // add impulse at centre
        out[filterSemiLength] += 1.0
        sum += 1

        // scale for unity gain
        //TODO: peak() is not scaling properly to unity gain
        for i in 0..<length {
            out[i] /= sum
        }

        return out
    }
    
    //TODO Parks-McClellan design
    // https://github.com/janovetz/remez-exchange
    // https://github.com/sfilip/firpm
    //TODO Least squares design
    // https://cnx.org/contents/6x7LNQOp@7/Linear-Phase-Fir-Filter-Design-By-Least-Squares

    /// Split a coefficient kernel into a polyphase bank of coefficients for resampling. The
    /// rows are reversed for application against a sample window.
    /// - Parameter M: the number of coefficient rows to produce
    /// - Parameter F: the input coefficient kernel
    /// - Parameter scale: a gain factor to scale the coefficients, typically = M for unity
    /// gain in resampling
    public static func polyphaseBank(_ M: Int, _ F: [Float], scale: Float=1.0) -> [[Float]] {
        precondition(M > 0, "FIRKernel polyphaseBank size must be > 0")
        let N = F.count
        precondition(N > 0, "FIRKernel polyphaseBank filter must not be empty")
        precondition(M <= N, "FIRKernel polyphaseBank size \(M) must not exceed kernel size \(N)")
        var F0 = F.map{$0*scale}
        let pad = (N + M-1) / M * M - N // pad to even multiple of M with zeros
        if pad > 0 {
            print("FIRKernel polyphaseBank \(M) \(N) pad \(pad)")
            F0.append(contentsOf: repeatElement(Float.zero, count:pad))
        }
        let P = F0.count / M // length of sub-filters, truncating division
        // FB = [list(reversed(F0[i:P*M:M])) for i in range(M)] # sub-filters
        var FB = [[Float]]()
        FB.reserveCapacity(M)
        for i in 0..<M {
            FB.append([Float](stride(from:(P-1)*M+i, to:-1, by:-M).map{F0[$0]}))
        }
        return FB
    }
    
    public static func frequencyResponse(_ coefficients:[Float], fc:Float)->DSPComplex {
        var H:DSPComplex = DSPComplex.zero
        for i in 0..<(coefficients.count) {
            H += coefficients[i] * DSPComplex.exp(DSPComplex(0, 2.0*Float.pi*fc*Float(i)))
        }
        return H
    }
//    This gets errno 9 on the file write, maybe due to App. Sandbox?
//    struct FileWriter:TextOutputStream {
//        let fileName = "filterResponse.gnuplot"
//    #if os(macOS)
//        var fd:Int32 = -1
//        mutating func write(_ string: String) {
//            if fd < 0 {
//                fd = Darwin.open(fileName, O_CREAT|O_TRUNC, 0o666)
//                if fd < 0 { print("open error", Darwin.errno); return }
//            }
//            let bytesCount = string.utf8.count
//            string.withCString{(cstr) in
//                var writtenBytes:Int = 0
//                while writtenBytes != bytesCount {
//                    let result = Darwin.write(fd,
//                                              cstr.advanced(by:writtenBytes),
//                                              bytesCount - writtenBytes)
//                    if result < 0 {
//                        print("write error", Darwin.errno)
//                        return
//                    }
//                    writtenBytes += result
//                }
//            }
//        }
//    #else
//        mutating func write(_ string: String) {
//            print(string)
//        }
//    #endif
//    }
//    static var printer = FileWriter()
    
    public static func plotFrequencyResponse(_ coefficients:[Float], title:String, Fs:Float=1.0, nFFT:Int=512) {
        print("""
        #set terminal qt font "Verdana,10"
        set title "\(title)"
        set xrange [\(-Fs/2):\(Fs/2)]
        set autoscale y
        set xlabel 'Frequency [Hz]'
        set ylabel 'Power Spectral Density [dB]'
        set style line 12 lc rgb '#404040' lt 0 lw 1
        set grid xtics ytics
        set grid front ls 12
        set style fill transparent solid 0.2
        set nokey
        plot '-' w filledcurves x1 lt 1 lw 2 lc rgb '#004080'
        """)//, to:&printer)
        for i in 0...nFFT {
            let f = (Float(i) - 0.5*Float(nFFT)) / Float(nFFT)
            let R = frequencyResponse(coefficients, fc:f)
            print(f*Fs, 20*log10f(R.modulus()))//, to:&printer)
        }
        print("e")//, to:&printer) // end of '-' data
        print("pause -1 'Hit Return or close plot window'")//, to:&printer)
    }

}
