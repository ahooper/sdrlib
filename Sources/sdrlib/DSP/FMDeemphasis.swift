//
//  FMDeemphasis.swift
//  SimpleSDR3
//
//  https://github.com/gnuradio/gnuradio/blob/master/gr-analog/python/analog/fm_emph.py
//  http://www.sengpielaudio.com/calculator-timeconstant.htm
//
//  Created by Andy Hooper on 2020-04-23.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import func CoreFoundation.tanf

public class FMDeemphasis: IIR22Filter<RealSamples> {

    public init(source:BufferedSource<Input>, tau:Float=75e-6) {
        let fc = 1.0 / tau, // corner frequency
            fs = Float(source.sampleFrequency()),
            ca = 2.0 * fs * tanf(fc / (2.0 * fs))

        // Resulting digital pole, zero, and gain term from the bilinear
        // transformation of H(s) = ca / (s + ca) to
        // H(z) = b0 (1 - z1 z^-1)/(1 - p1 z^-1)
        let k = -ca / (2.0 * fs),
            z1 = Float(-1.0),
            p1 = (1.0 + k) / (1.0 - k),
            b0 = -k / (1.0 - k),
            btaps = [ b0 * 1.0, b0 * -z1 ],
            ataps = [      1.0,      -p1 ] // explicitly not old gnuradio feedback tap sign convention!
        // Since H(s = 0) = 1.0, then H(z = 1) = 1.0 and has 0 dB gain at DC
        
        //print("FMDeemphasis", btaps, ataps)
        super.init(source:source, btaps, ataps)
    }
    
}

