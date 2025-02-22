//
//  Window.swift
//  sdrplay1
//
//  Created by Andy Hooper on 2023-03-09.
//
//  https://holometer.fnal.gov/GH_FFT.pdf = https://www.researchgate.net/publication/267956210_Spectrum_and_spectral_density_estimation_by_the_Discrete_Fourier_transform_DFT_including_a_comprehensive_list_of_window_functions_and_some_new_flat-top_windows
//  https://en.wikipedia.org/wiki/Window_function
//  https://ccrma.stanford.edu/~jos/sasp/Spectrum_Analysis_Windows.html
// https://www.researchgate.net/publication/2995027_On_the_Use_of_Windows_for_Harmonic_Analysis_With_the_Discrete_Fourier_Transform
//  https://github.com/scipy/scipy/blob/main/scipy/signal/windows/_windows.py

import func CoreFoundation.cosf
import func CoreFoundation.fabs
import func CoreFoundation.sqrtf
import func CoreFoundation.exp
import func CoreFoundation.sqrt

public struct WindowFunction {
       
    /// Window function signature
    public typealias Function = (Int,Int)->Float

    public static func rectangular(_ n:Int, _ M:Int)->Float { 1.0 }
        // aka. Dirichlet, boxcar
    
    public static func bartlett(_ n:Int, _ M:Int)->Float {
        // aka. triangular
        let tmp = Float(n) - Float(M) / 2.0
        return 1.0 - (2.0 * abs(tmp)) / Float(M)
    }
    
    fileprivate static func generalCosine(_ n:Int, _ M:Int, _ a0:Float, _ a1:Float)->Float {
        let f = 2.0 * Float.pi * Float(n) / Float(M)
        return a0 + a1*cosf(f)
    }
    
    fileprivate static func generalCosine(_ n:Int, _ M:Int, _ a0:Float, _ a1:Float, _ a2:Float)->Float {
        let f = 2.0 * Float.pi * Float(n) / Float(M)
        return a0 + a1*cosf(f) + a2*cosf(2.0*f)
    }
    
    fileprivate static func generalCosine(_ n:Int, _ M:Int, _ a0:Float, _ a1:Float, _ a2:Float, _ a3:Float)->Float {
        let f = 2.0 * Float.pi * Float(n) / Float(M)
        return a0 + a1*cosf(f) + a2*cosf(2.0*f) + a3*cosf(3.0*f)
    }

    fileprivate static func generalCosine(_ n:Int, _ M:Int, _ a0:Float, _ a1:Float, _ a2:Float, _ a3:Float, _ a4:Float)->Float {
        let f = 2.0 * Float.pi * Float(n) / Float(M)
        return a0 + a1*cosf(f) + a2*cosf(2.0*f) + a3*cosf(3.0*f) + a4*cosf(4.0*f)
    }

    public static func hann(_ n:Int, _ M:Int)->Float {
        // aka. rasied cosine, sine squared, Hanning
        // https://ccrma.stanford.edu/~jos/sasp/Hann_Hanning_Raised_Cosine.html
        generalCosine(n, M, 0.5, -0.5)
    }
    
    public static func hamming(_ n:Int, _ M:Int)->Float {
        // https://ccrma.stanford.edu/~jos/sasp/Hamming_Window.html
        generalCosine(n, M, 0.54, -0.46)
    }

    public static func blackman(_ n:Int, _ M:Int)->Float {
        // https://ccrma.stanford.edu/~jos/sasp/Classic_Blackman.html
        generalCosine(n, M, 0.42, -0.50, 0.08)
    }

    public static func blackmanharris(_ n:Int, _ M:Int)->Float {
        generalCosine(n, M, 0.35875, -0.48829, 0.14128, -0.01168)
    }

    public static func nuttall33(_ n:Int, _ M:Int)->Float {
        generalCosine(n, M, 0.338946, -0.481973, 0.161054, -0.018027)
    }

    public static func nuttall37(_ n:Int, _ M:Int)->Float {
        generalCosine(n, M, 0.3635819, -0.4891775, 0.1365995, -0.0106411)
    }

    /// https://www.mathworks.com/help/signal/ref/flattopwin.html
    public static func flattop(_ n:Int, _ M:Int)->Float {
        generalCosine(n, M, 0.21557895, -0.41663158, 0.277263158, -0.083578947, 0.006947368)
    }
    
    /// This flat top window was optimized for the lowest sidelobe level that is achieveable
    /// with 3 cosine terms. Its transfer function and characteristics are given by
    /// NENBW = 3.4129 bins , W3dB = 3.3720 bins, emax = −0.0065 dB = 0.0750 %.
    /// The first zero is located at f = ±4.00 bins. The highest sidelobe is −70.4dB,
    /// located at f = ±4.65 bins. The sidelobes drop at a rate of f^−1. At the optimal
    /// overlap of 72.2%, the amplitude flatness is 0.964, the power flatness is 0.637,
    /// and the overlap correlation is 0.041.
    public static func HFT70(_ n:Int, _ M:Int)->Float {
        generalCosine(n, M, 1, -1.90796, 1.07349, -0.18199)
    }
    
    /// This flat top window was optimized for the lowest sidelobe level that is achieveable
    /// with 4 cosine terms. Its characteristics are very similar to those of the flat-top
    /// window that is used in newer HP/Agilent spectrum analyzers. Its transfer function
    /// and characteristics are given by
    /// NENBW = 3.8112 bins , W3dB = 3.7590 bins, emax = 0.0044 dB = 0.0507 %.
    /// The first zero is located at f = ±5.00 bins. The highest sidelobe is −95.0dB,
    /// located at f = ±7.49 bins. The sidelobes drop at a rate of f^−1. At the optimal
    /// overlap of 75.6%, the amplitude flatness is 0.952, the power flatness is 0.647,
    /// and the overlap correlation is 0.056.
    public static func HFT95(_ n:Int, _ M:Int)->Float {
        generalCosine(n, M, 1, -1.9383379, 1.3045202, -0.4028270, 0.0350665)
    }
    
    /// This flat top window was optimized for the lowest sidelobe level that is achieveable
    /// with 4 cosine terms if condition (161) is additionally imposed to ensure a
    /// sidelobe-drop rate of f^−3. Its transfer function and characteristics are given by
    /// NENBW = 3.8832 bins , W3dB = 3.8320 bins, emax = −0.0039 dB = 0.0450 %.
    /// The first zero is located at f = ±5.00 bins. The highest sidelobe is −90.2dB,
    /// located at f = ±5.58 bins. The sidelobes drop at a rate of f^−3. At the optimal
    /// overlap of 76.0%, the amplitude flatness is 0.953, the power flatness is 0.646,
    /// and the overlap correlation is 0.054.
    public static func HFT90D(_ n:Int, _ M:Int)->Float {
        generalCosine(n, M, 1, -1.942604, 1.340318, -0.440811, 0.043097)
    }

    /// Generate a periodic window, for use in spectral analysis
    public static func Periodic(_ length:Int,
                                _ windowFunction:Function=blackman,
                                gain:Float=1.0)-> [Float] {
        (0..<length).map { n in gain*windowFunction(n, length) }
    }

    /// Generate a symmetric window, for use in filter design
    public static func Symmetric(_ length:Int,
                                 _ windowFunction:Function=blackman,
                                 gain:Float=1.0)-> [Float] {
        (0..<length).map { n in gain*windowFunction(n, length-1) }
    }

    public static func kaiser(beta:Float) -> Function {
        precondition(beta >= 0, "kaiser(), beta must be greater than or equal to zero (\(beta))")

        return { n,M->Float in
            // http://www.labbookpages.co.uk/audio/firWindowing.html
            let r = 2 * Double(n) / Double(M) - 1
            let a = bessI0(Double(beta) * sqrt(1 - r*r))
            let b = bessI0(Double(beta))
            return Float(a / b)
        }
    }

    /// Evaluate modified Bessel function In(x) and n=0.
    //  Excerpt from https://github.com/kapteyn-astro/gipsy/blob/master/sub/bessel.c
    //  Part of GIPSY https://www.astro.rug.nl/~gipsy/
    //  Copyright (c) 1998 Kapteyn Institute Groningen
    static func bessI0(_ x: Double) -> Double {
        var ax, ans: Double
        var y: Double

        ax = fabs(x)
        if ax < 3.75 {
            y = x/3.75; y = y*y
            ans = 1.0 + y*(3.5156229 + y*(3.0899424 + y*(1.2067492
                             + y*(0.2659732 + y*(0.360768e-1 + y*0.45813e-2)))))
        } else {
            y = 3.75/ax
            ans = (exp(ax)/sqrt(ax)) * (0.39894228 + y*(0.1328592e-1
                                        + y*(0.225319e-2 + y*(-0.157565e-2 + y*(0.916281e-2
                                        + y*(-0.2057706e-1 + y*(0.2635537e-1 + y*(-0.1647633e-1
                                        + y*0.392377e-2))))))))
        }
        return ans
    }

}
