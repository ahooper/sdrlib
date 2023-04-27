//
//  Buffered.swift
//  sdrplay1
//
//  Created by Andy Hooper on 2023-02-01.
//

import class Foundation.DispatchGroup
import class Foundation.DispatchQueue

public protocol SinkProtocol: AnyObject {
    associatedtype Input
    func process(_ input:Input)
}

protocol SourceProtocol {
    associatedtype Output
    /// Get the sampling frequency this stage is processing.
    func sampleFrequency()-> Double
    /// Connect a sink processor
    func connect<S:SinkProtocol>(sink: S, async: Bool) where Output == S.Input
}

//let asyncQueue = DispatchQueue.global(qos: .userInteractive)
let asyncQueue = DispatchQueue(label: "Buffered",
                               qos: .userInteractive,
                               attributes: .concurrent)

class BufferedSource<Output:DSPSamples>: SourceProtocol {
    let name: String
    internal var
        outputBuffer = Output(),    // buffer currently being written - the producer thread has
                                    // exclusive access to this buffer until it calls produce()
        produceBuffer = Output()    // buffer currently being consumed by sinks - the consumer
                                    // threads have shared read access to this buffer   
    let asyncGroup = DispatchGroup()

    struct Sink {
        let sink: any SinkProtocol,
            async: Bool,
            process: (Output)->Void
    }
    private var sinks = [Sink](),
                waitAsync = false
    
    init(name: String) {
        self.name = name
    }

    func connect<S:SinkProtocol>(sink: S, async: Bool = false) where Output == S.Input {
        sinks.append(Sink(sink: sink, async: async, process: sink.process))
    }

    func disconnect<S:SinkProtocol>(sink: S, asThread: Bool = false) where Output == S.Input {
        // can't search directly for function equality
        sinks.removeAll(where: { $0.sink === sink })
    }

    /// Provide the current output buffer to the sinks for processing.
    func produce(clear:Bool=false) {
        //print(name, "produce", waitAsync)
        if waitAsync {
            waitAsync = false
            sinkWaitTime.start()
            asyncGroup.wait()
            sinkWaitTime.stop()
            //sinkWaitTime.printAccumulated(reset: true)
        }
        if clear { produceBuffer.removeAll(keepingCapacity:true) }
        swap(&outputBuffer, &produceBuffer)
        subProcessTime.start()
        // dispatch all asynchronous sink processors
        for s in sinks {
            if s.async {
                asyncQueue.async(group: asyncGroup) {
                    s.process(self.produceBuffer)
                }
                waitAsync = true
            }
        }
        // call all synchronous sink processors
        for s in sinks {
            if !s.async {
                s.process(self.produceBuffer)
            }
        }
        subProcessTime.stop()
    }
    var sinkWaitTime = TimeReport(subjectName:"Sink wait"),
        subProcessTime = TimeReport(subjectName:"Sink process")
   
    func sampleFrequency()-> Double {
        Double.signalingNaN
    }
    
    var debugDescription: String { self.name }
}

class Buffered<Input:DSPSamples, Output:DSPSamples>: BufferedSource<Output>, SinkProtocol {
    var source: BufferedSource<Input>?
    
    init(_ name:String, _ source:BufferedSource<Input>?) {
        self.source = source
        super.init(name: name)
        source?.connect(sink: self, async: false)
        // TODO start()
    }
    
    func connect(source: BufferedSource<Input>, async: Bool = false) {
        self.source?.disconnect(sink: self)
        self.source = source
        source.connect(sink: self, async: async)
    }
    
    func disconnect() {
        self.source?.disconnect(sink: self)
        self.source = nil
    }

    override func sampleFrequency()-> Double {
        source?.sampleFrequency() ?? Double.signalingNaN
    }
    
    func process(_ x:Input, _ output:inout Output) {
        fatalError("\(name) process(::) method must be overridden.")
    }

    // SinkProtocol //
    
    func process(_ input: Input) {
        process(input, &outputBuffer)
        produce(clear: true)
    }
}

class Sink<Input:DSPSamples>: SinkProtocol {
    let name: String
    var source: BufferedSource<Input>?
    
    init(_ name:String, _ source:BufferedSource<Input>?) {
        self.source = source
        self.name = name
        source?.connect(sink: self)
    }
    
    func connect(source: BufferedSource<Input>, async: Bool = false) {
        self.source?.disconnect(sink: self)
        self.source = source
        source.connect(sink: self, async: async)
    }
    
    func disconnect() {
        self.source?.disconnect(sink: self)
        self.source = nil
    }

    // SinkProtocol //
    
    func process(_ x:Input) {
        fatalError("\(name) process(:) method must be overridden.")
    }
}

class NilSource<Output:DSPSamples>: BufferedSource<Output> {
    override func sampleFrequency() -> Double {
        Double.signalingNaN
    }
    
    static func Real()->NilSource<RealSamples>? { nil }
    static func Complex()->NilSource<ComplexSamples>? { nil }
}
