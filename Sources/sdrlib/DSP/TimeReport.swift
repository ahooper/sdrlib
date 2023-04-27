//
//  TimeReport.swift
//  SimpleSDR
//
//  Report on execution time
//  https://stackoverflow.com/a/26578191
//  https://stackoverflow.com/a/4753909
//  https://developer.apple.com/library/archive/qa/qa1398/_index.html
//  https://gist.github.com/cemolcay/e8e3cad64da65cd80a50ed37310d2038
//
//  Created by Andy Hooper on 2019-10-10.
//  Copyright © 2019 Andy Hooper. All rights reserved.
//

//import struct Darwin.mach_timebase_info_data_t
//import func Darwin.mach_timebase_info
//import func Darwin.mach_absolute_time
import Darwin // mach_timebase_info_data_t{}, mach_timebase_info(), mach_absolute_time()
import class Foundation.NumberFormatter
import class Foundation.NSNumber

public class TimeReport {
    var name:String
    var count, highCount, badCount:UInt
    var resetNext:Bool
    var startTime:UInt64 //:CFAbsoluteTime
    let NOT_STARTED = UInt64(0)
    var maximum, minimum, sum, highTime:UInt64 //:CFTimeInterval
    var timebaseInfo:mach_timebase_info_data_t
    let formatter = NumberFormatter()
    
    /// Initialize a new time accumulator.
    public init(subjectName:String, highnS:UInt64=UInt64.max) {
        name = subjectName
        count = 0
        highCount = 0
        badCount = 0
        resetNext = false
        startTime = NOT_STARTED
        maximum = 0
        minimum = UInt64.max
        sum = 0
        highTime = highnS
        timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
    }
    
    deinit {
        printAccumulated()
    }

    private func formatted(_ x:UInt64)-> String {
        formatter.string(from:NSNumber(value:machAbsoluteToNanoSeconds(machAbsolute:x).rounded()))!
    }

    private func formatted(_ x:UInt)-> String {
        formatter.string(from:NSNumber(value:x))!
    }

    private func formatted(_ x:Float)-> String {
        formatter.string(from:NSNumber(value:x.rounded()))!
    }

    /// Show the time accumulated.
    public func printAccumulated(reset:Bool=false) {
        if count == 0 {
            print("TimeReport",name,"unused")
            return
        }
        let average = (count > 0) ? machAbsoluteToNanoSeconds(machAbsolute: sum) / Float(count) : Float.nan
        print("TimeReport",name,
              "average",formatted(average),
              "nSec. max",formatted(maximum),
              "min",formatted(minimum),
              "count",formatted(count),
              "high",formatted(highCount),
              "bad",formatted(badCount))
        if reset { self.reset() }
    }
    
    public func reset() {
        resetNext = true
    }
    
    /// Convert Mach time units to nanoseconds.
    func machAbsoluteToNanoSeconds(machAbsolute: UInt64) -> Float {
        return Float(machAbsolute * UInt64(timebaseInfo.numer)) / Float(timebaseInfo.denom)
    }
    
    /// Start time accumulation at the beginning of a timed section.
    public func start() {
        if resetNext {
            resetNext = false
            count = 0
            highCount = 0
            badCount = 0
            maximum = 0
            minimum = UInt64.max
            sum = 0
        }
        startTime = mach_absolute_time() //CFAbsoluteTimeGetCurrent()
    }

    /// Stop time accumulation at the end of a timed section.
    public func stop() {
        guard startTime != NOT_STARTED else {
            badCount += 1
            return
        }
        let stopTime = mach_absolute_time() //CFAbsoluteTimeGetCurrent()
        let duration = stopTime - startTime
        if duration <= 0 {
            badCount += 1
        } else {
            count += 1
            sum += duration
            if duration < minimum { minimum = duration }
            if duration > maximum { maximum = duration }
            if duration > highTime { highCount += 1 }
        }
    }
}
