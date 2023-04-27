//
//  CycleTime.swift
//  sdrplay1
//
//  Created by Andy Hooper on 2023-02-15.
//

class CycleTime<Input:DSPSamples>: Sink<Input> {
    let time: TimeReport
    init(_ source:BufferedSource<Input>?) {
        time = TimeReport(subjectName: "CycleTime")
        super.init("CycleTime", source)
    }
    public override func process(_ input: Input) {
        time.stop()
        time.start()
    }
}
