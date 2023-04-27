//
//  AudioOutput.swift
//  SimpleSDR3
//
//  https://github.com/thestk/rtaudio/blob/master/RtAudio.cpp
//  https://gist.github.com/rlxone/584467a63ac0ddf4d62fe1a983b42d0e
//  https://chromium.googlesource.com/chromium/src/media/+/7479f0acde23267d810b8e58c07b342719d9a923/audio/mac/audio_manager_mac.cc
//  Created by Andy Hooper on 2020-01-25.
//  Copyright © 2020 Andy Hooper. All rights reserved.
//

import class Foundation.NSCondition
import CoreAudio
//import Darwin

class AudioOutput: Sink<RealSamples> {

    typealias DataType = Float32
    static let DATA_BYTE_SIZE = MemoryLayout<DataType>.size

    var deviceID: AudioDeviceID = 0
    var deviceName = "UNKNOWN"
    var procID: AudioDeviceIOProcID? = nil
    var channelCount = [Int]()
    public var sampleRate = 0.0
    public var deviceStarted = false
    public var deviceStopped = false
    var sampleCount:UInt64 = 0
    
    var audioBuffers = [ContiguousArray<DataType>(),
                        ContiguousArray<DataType>()]
    var /*FUTURE:atomic*/callbackPlaying = 0 // index of buffer being played out
    var callbackPlayPoint = 0 // next index in playout buffer to be played
    var bufferSwitch = NSCondition()

    init() {

        super.init("AudioOutput", nil)
        setRunLoop()
        
#if false
        for dev in getAllDevices() {
            print("Audio device ID", dev, getManufacturer(dev), getDeviceName(dev))
        }
#endif

        deviceID = getDefaultDevice(input: false)
        if deviceID == kAudioDeviceUnknown {
            print("AudioOutput init DefaultOutputDevice unknown")
            return
        }

        deviceName = getDeviceName(deviceID)
        print("AudioOutput default output device", "ID", deviceID, "name", deviceName)
        
        channelCount = getChannelInterleave(deviceID)
        let availableRates = getAvailableSampleRates(deviceID)
        let nominalSampleRate = getSampleRate(deviceID)
        sampleRate = nominalSampleRate
        var virtualFormat = getSreamVirtualFormat(deviceID)
        let bufferFrameSizeRange = getBufferFrameSizeRange(deviceID)
        let bufferFrameSize = getBufferFrameSize(deviceID)
        print("AudioOutput",
              "channel interleave", channelCount,
              "sample rate", sampleRate, availableRates.map{($0.mMinimum,$0.mMaximum)},
              "buffer size", bufferFrameSize,
                    (bufferFrameSizeRange.mMinimum,bufferFrameSizeRange.mMaximum),
              "format", AudioOutput.fourCharString(Int32(virtualFormat.mFormatID)), virtualFormat)

        if !(   virtualFormat.mFormatID == kAudioFormatLinearPCM
             && virtualFormat.mFormatFlags == (kLinearPCMFormatFlagIsFloat|kLinearPCMFormatFlagIsPacked)
             && virtualFormat.mBitsPerChannel == 32) {
            print("AudioOutput unexpected virtual format", virtualFormat)
            virtualFormat.mFormatID = kAudioFormatLinearPCM
            virtualFormat.mFormatFlags = kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked
            virtualFormat.mBitsPerChannel = 32
            setStreamVirtualFormat(deviceID, &virtualFormat)
        }
        
        // buffers are fixed size
        let bufferSize = bufferFrameSize * Int(virtualFormat.mChannelsPerFrame)
        for i in 0..<audioBuffers.count { //  = 2
            audioBuffers[i] = ContiguousArray<DataType>(repeating:DataType.zero, count:bufferSize)
        }

        check(AudioDeviceCreateIOProcID(deviceID, AudioOutput.outputCallback, Unmanaged<AudioOutput>.passUnretained(self).toOpaque(), &procID))

        // Listen for overload and change of default output device
        check(AudioObjectAddPropertyListener(deviceID, &overloadPropertyAddress, AudioOutput.propertyListener, Unmanaged<AudioOutput>.passUnretained(self).toOpaque()))
        check(AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultOutputPropertyAddress, AudioOutput.propertyListener, Unmanaged<AudioOutput>.passUnretained(self).toOpaque()))

        // Audio device is not started until first buffer is filled
    }

    deinit {
        if deviceStarted {
            check(AudioDeviceStop(deviceID, procID))
        }
        if procID != nil {
            AudioDeviceDestroyIOProcID(deviceID, procID!)
        }
        AudioObjectRemovePropertyListener(deviceID, &overloadPropertyAddress, AudioOutput.propertyListener, Unmanaged<AudioOutput>.passUnretained(self).toOpaque())
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultOutputPropertyAddress, AudioOutput.propertyListener, Unmanaged<AudioOutput>.passUnretained(self).toOpaque())
    }

    func sampleFrequency() -> Double {
        return Double(sampleRate)
    }
    
    override func connect(source: BufferedSource<RealSamples>, async: Bool = false) {
        precondition(source.sampleFrequency() == sampleRate)
        super.connect(source: source, async: async)
    }
    
    override func disconnect() {
        stop()
        super.disconnect()
        zero()
    }
    
    let fillTime = TimeReport(subjectName:"AudioOutput fill", highnS:UInt64(1/48e3*512*1e9))
    let processTime = TimeReport(subjectName:"AudioOutput process", highnS:UInt64(1/48e3*512*1e9))
    let waitTime = TimeReport(subjectName:"AudioOutput wait", highnS:UInt64(1/48e3*512*1e9))

    override func process(_ input: Input) {
        processTime.start()
        //print("AudioOutput process", input.count, deviceStarted, callbackPlaying, fillPoint)
        var filling = 1 - callbackPlaying // fill the buffer that is not playing
        let numChannels = channelCount[0]
        var sum:Float=0, max:Float=0
        //print("p",input.count,filling,fillPoint,callbackPlayPoint,separator:",",terminator:" ")
        for i in 0..<input.count {
            if fillPoint >= audioBuffers[filling].count {
                //print("AudioOutput process filled",filling,fillPoint,deviceStarted,deviceStopped)
                filledBuffer(filling)
                // advance to next buffer
                filling = 1 - callbackPlaying
                fillPoint = 0
                //fflush(stdout)
            }
            let v = input[i]
            // duplicate for stereo TODO: multiple inputs
            for c in 0..<numChannels {
                audioBuffers[filling][fillPoint+c] = v
            }
            fillPoint += numChannels
            sum += v
            let av = abs(v)
            if av > max { max = av }
        }
        sampleCount += UInt64(input.count)
        // warn of high levels
        if max >= 1.0 { print("AudioOutput process", "count", input.count, "avg", sum/Float(input.count), "max", max) }
        processTime.stop()
    }
    var fillPoint = 0

    /// Switch buffers when filled
    private func filledBuffer(_ filling: Int) {
        //print("AudioOutput filledBuffer",filling,fillPoint,deviceStarted,deviceStopped)
        if underflowCount > 0 {
            print("AudioOutput underflow",underflowCount)
            underflowCount = 0 // ignoring the concurrency conflict on this
        }
        if callbackPlaying == filling { print("AudioOutput filled late!") }
        if !deviceStarted && !deviceStopped {
            // start device after first buffer filled
            callbackPlaying = filling
            callbackPlayPoint = 0
            sampleCount = 0
            check(AudioDeviceStart(deviceID, procID))
            deviceStarted = true
            print("AudioOutput device started")
        }
        fillTime.stop()
        waitTime.start()
        //print("f",filling,callbackPlaying,separator:",",terminator:" ")
        bufferSwitch.lock() // BEGIN LOCK REGION
            while callbackPlaying != filling {
                //print("w",filling,callbackPlaying,separator:",",terminator:" ")
                bufferSwitch.wait()
            }
        bufferSwitch.unlock() // END LOCK REGION
        waitTime.stop()
        fillTime.start()
    }
    
    func zero() {
        for b in 0..<audioBuffers.count {
            for i in 0..<audioBuffers[b].count {
                audioBuffers[b][i] = DataType.zero
            }
            //audioBuffers[b].replaceSubrange(0..<audioBuffers[b].count,
            //                                with:repeatElement(DataType.zero,
            //                                                   count:audioBuffers[b].count))
        }
    }
    
    func stop() {
        check(AudioDeviceStop(deviceID, procID))
        deviceStarted = false
        deviceStopped = true
        sampleCount = 0
        bufferSwitch.lock() // BEGIN LOCK REGION
            zero()
            callbackPlaying = 0
            callbackPlayPoint = 0
            fillPoint = 0
        bufferSwitch.signal()
        bufferSwitch.unlock() // END LOCK REGION
        print("AudioOutput device stopped")
    }
    
    func resume() {
        print("AudioOutput resume callbackPlaying \(callbackPlaying) callbackPlayPoint \(callbackPlayPoint) fillPoint \(fillPoint)")
        deviceStopped = false
        bufferSwitch.lock() // BEGIN LOCK REGION
            callbackPlaying = 1 - callbackPlaying
            callbackPlayPoint = 0
            fillPoint = 0
        bufferSwitch.signal()
        bufferSwitch.unlock() // END LOCK REGION
    }
    
    private static let outputCallback:AudioDeviceIOProc = {
        // excerpt from /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h
        /*!
         @abstract       An AudioDeviceIOProc is called by an AudioDevice to provide input data read from
                         the device and collect output data to be written to the device for the current
                         IO cycle.
         @param          inDevice
                             The AudioDevice doing the IO.
         @param          inNow
                             An AudioTimeStamp that indicates the IO cycle started. Note that this time
                             includes any scheduling latency that may have been incurred waking the
                             thread on which IO is being done.
         @param          inInputData
                             An AudioBufferList containing the input data for the current IO cycle. For
                             streams that are disabled, the AudioBuffer's mData field will be NULL but
                             the mDataByteSize field will still say how much data would have been there
                             if it was enabled. Note that the contents of this structure should never be
                             modified.
         @param          inInputTime
                             An AudioTimeStamp that indicates the time at which the first frame in the
                             data was acquired from the hardware. If the device has no input streams, the
                             time stamp will be zeroed out.
         @param          outOutputData
                             An AudioBufferList in which the output data for the current IO cycle is to
                             be placed. On entry, each AudioBuffer's mDataByteSize field indicates the
                             maximum amount of data that can be placed in the buffer and the buffer's
                             memory has been zeroed out. For formats where the number of bytes per packet
                             can vary (as with AC-3, for example), the client has to fill out on exit
                             each mDataByteSize field in each AudioBuffer with the amount of data that
                             was put in the buffer. Otherwise, the mDataByteSize field should not be
                             changed. For streams that are disabled, the AudioBuffer's mData field will
                             be NULL but the mDataByteSize field will still say how much data would have
                             been there if it was enabled. Except as noted above, the contents of this
                             structure should not other wise be modified.
         @param          inOutputTime
                             An AudioTimeStamp that indicates the time at which the first frame in the
                             data will be passed to the hardware. If the device has no output streams,
                             the time stamp will be zeroed out.
         @param          inClientData
                             A pointer to client data established when the AudioDeviceIOProc was
                             registered with the AudioDevice.
         @result         The return value is currently unused and should always be 0.
        */
                            (_ inDevice:AudioObjectID,
                             _ inNow:UnsafePointer<AudioTimeStamp>,
                             _ inInputData:UnsafePointer<AudioBufferList>,
                             _ inInputTime:UnsafePointer<AudioTimeStamp>,
                             _ outOutputData:UnsafeMutablePointer<AudioBufferList>,
                             _ inOutputTime:UnsafePointer<AudioTimeStamp>,
                             _ inClientData:UnsafeMutableRawPointer?) -> OSStatus in
        let s = Unmanaged<AudioOutput>.fromOpaque(inClientData!).takeUnretainedValue() // "self"
        if s.deviceStopped { return noErr }  // leave zero
        assert(outOutputData.pointee.mNumberBuffers == 1) // assuming interleaved stereo
        let buffer = outOutputData.pointee.mBuffers
        let numChannels = Int(buffer.mNumberChannels)
        assert(numChannels == 2) // assuming interleaved stereo
        let numSamples = Int(buffer.mDataByteSize) / AudioOutput.DATA_BYTE_SIZE
        let numToCopy = min(numSamples, s.audioBuffers[s.callbackPlaying].count - s.callbackPlayPoint)
        //print("c",s.callbackPlaying,s.callbackPlayPoint,separator:",",terminator:" ")
        //print("AudioOutput", inDevice, "callback", s.callbackPlaying, numSamples, numToCopy)
        if numToCopy < numSamples {
            s.underflowCount += 1
        }
        s.audioBuffers[s.callbackPlaying].withUnsafeBufferPointer { bp in
            buffer.mData!.copyMemory(from: bp.baseAddress!.advanced(by:s.callbackPlayPoint),
                                     byteCount: numToCopy*AudioOutput.DATA_BYTE_SIZE)
        }
        s.callbackPlayPoint += numToCopy
        if s.callbackPlayPoint == s.audioBuffers[s.callbackPlaying].count {
            s.callbackPlaying = 1 - s.callbackPlaying // switch to play the other buffer
            s.callbackPlayPoint = 0
            s.bufferSwitch.signal()
        }
        return noErr
    }
    var underflowCount:UInt = 0
        
    private static let propertyListener:AudioObjectPropertyListenerProc = {
        /*!
            @typedef        AudioObjectPropertyListenerProc
            @abstract       Clients register an AudioObjectPropertyListenerProc with an AudioObject in order
                            to receive notifications when the properties of the object change.
            @discussion     Listeners will be called when possibly many properties have changed.
                            Consequently, the implementation of a listener must go through the array of
                            addresses to see what exactly has changed. Note that the array of addresses will
                            always have at least one address in it for which the listener is signed up to
                            receive notifications about but may contain addresses for properties for which
                            the listener is not signed up to receive notifications.
            @param          inObjectID
                                The AudioObject whose properties have changed.
            @param          inNumberAddresses
                                The number of elements in the inAddresses array.
            @param          inAddresses
                                An array of AudioObjectPropertyAddresses indicating which properties
                                changed.
            @param          inClientData
                                A pointer to client data established when the listener process was registered
                                with the AudioObject.
            @result         The return value is currently unused and should always be 0.
        */
                            (_ objectID:AudioObjectID,
                             _ addressCount:UInt32,
                             _ addresses:UnsafePointer<AudioObjectPropertyAddress>,
                             _ callbackContext:UnsafeMutableRawPointer?) -> OSStatus in
        let s = Unmanaged<AudioOutput>.fromOpaque(callbackContext!).takeUnretainedValue() // "self"
        for i in 0..<Int(addressCount) {
            let selector: AudioObjectPropertySelector = addresses.advanced(by:i).pointee.mSelector
            if selector == kAudioDeviceProcessorOverload {
                // check objectID == s.deviceID
                s.underflowCount += 1
            } else if selector == kAudioHardwarePropertyDefaultOutputDevice {
                print("AudioOutput propertyListener", "DefaultOutputDevice")
            } else {
                print("AudioOutput propertyListener", "selector", fourCharString(Int32(selector)))
            }
        }
        return kAudioHardwareNoError
    }
    private var overloadPropertyAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioDeviceProcessorOverload,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain),
                defaultOutputPropertyAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain)

    private func setRunLoop() {
        var theRunLoop: CFRunLoop = CFRunLoopGetCurrent()
        let propertySize = UInt32(MemoryLayout<CFRunLoop>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyRunLoop,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, propertySize, &theRunLoop))
    }

    func getDeviceName(_ deviceID: AudioObjectID)->String {
        var deviceName = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        let s = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &deviceName)
        return (s == noErr) ? String(deviceName)
            : "getDeviceName(\(deviceID)) failed \(AudioOutput.fourCharString(s))"
    }
    
    func getManufacturer(_ deviceID: AudioObjectID)->String {
        var manufacturer = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceManufacturerCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        let s = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &manufacturer)
        return (s == noErr) ? String(manufacturer)
            : "getManufacturer(\(deviceID)) failed \(AudioOutput.fourCharString(s))"
    }

    private func getDeviceCount() -> UInt32 {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize))
        return propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)
    }
    
    private func getSubDeviceCount(_ deviceID: AudioDeviceID) -> UInt32 {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize))
        return propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)
    }
    
    private func getAllDevices() -> [AudioDeviceID] {
        let devicesCount = getDeviceCount()
        var devices = [AudioDeviceID](repeating: 0, count: Int(devicesCount))
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        var devicesSize = devicesCount * UInt32(MemoryLayout<AudioDeviceID>.size)
        check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &devicesSize, &devices))
        return devices
    }
    
    func getDefaultDevice(input: Bool=false) -> AudioDeviceID {
        var deviceID = kAudioDeviceUnknown
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: input ? kAudioHardwarePropertyDefaultInputDevice
                                 : kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID))
        return deviceID
    }

    func getStreamCount(_ deviceID: AudioDeviceID, input: Bool=false) -> Int {
        var count: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: input ? kAudioDevicePropertyScopeInput
                              : kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &count))
        return Int(count)
    }
    
    func getChannelInterleave(_ deviceID: AudioDeviceID, input: Bool=false) -> [Int] {
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: input ? kAudioDevicePropertyScopeInput
                              : kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
        var propertySize: UInt32 = 0
        check(AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize))
        let bufferList = AudioBufferList.allocate(maximumBuffers: Int(propertySize)/MemoryLayout<AudioBuffer>.size)
        check(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, bufferList.unsafeMutablePointer))
        var channelCount = [Int](repeating: 0, count: bufferList.count)
        for i in 0..<bufferList.count {
            channelCount[i] = Int(bufferList[i].mNumberChannels)
        }
        free(bufferList.unsafeMutablePointer)
        return channelCount
    }

    func getBufferFrameSizeRange(_ deviceID: AudioDeviceID) -> AudioValueRange {
        var range = AudioValueRange()
        var propertySize = UInt32(MemoryLayout<AudioValueRange>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyBufferFrameSizeRange,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &range))
        return range
    }
 
    func getBufferFrameSize(_ deviceID: AudioDeviceID) -> Int {
        var bufferFrameSize = UInt32()
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyBufferFrameSize,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &bufferFrameSize))
        return Int(bufferFrameSize)
    }

    func setBufferFrameSize(_ deviceID: AudioDeviceID, _ size: Int) {
        precondition(!deviceStarted, "setBufferFrameSize cannot be called on an active stream")
        var bufferFrameSize = UInt32(size)
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
             mSelector: kAudioDevicePropertyBufferFrameSize,
             mScope: kAudioObjectPropertyScopeGlobal,
             mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, &bufferFrameSize))
        let bufferSize = size * channelCount[0]
        for i in 0..<audioBuffers.count {
            audioBuffers[i] = ContiguousArray<DataType>(repeating:DataType.zero, count:bufferSize)
        }
    }
    
    func getFramePeriod()-> Double {
        return Double(getBufferFrameSize(deviceID)) / getSampleRate(deviceID)
    }

    func getSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var nominalSampleRate = Float64(0)
        var propertySize = UInt32(MemoryLayout<Float64>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &nominalSampleRate))
        return nominalSampleRate
    }
    
    func getAvailableSampleRates(_ deviceID: AudioDeviceID) -> [AudioValueRange] {
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        var propertySize: UInt32 = 0
        check(AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize))
        var ranges = [AudioValueRange](repeating: AudioValueRange(),
                                       count: Int(propertySize / UInt32(MemoryLayout<AudioValueRange>.size)))
        check(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &ranges))
        return ranges
    }
    
    private var reportedRate: Double = 0
    private static let setSampleRateListener: AudioObjectPropertyListenerProc = {
                            (_ objectID:AudioObjectID,
                             _ addressCount:UInt32,
                             _ addresses:UnsafePointer<AudioObjectPropertyAddress>,
                             _ callbackContext:UnsafeMutableRawPointer?) -> OSStatus in
        let s = Unmanaged<AudioOutput>.fromOpaque(callbackContext!).takeUnretainedValue() // "self"
        for i in 0..<Int(addressCount) {
            let selector: AudioObjectPropertySelector = addresses.advanced(by:i).pointee.mSelector
            print("AudioOutput setSampleRateListener","selector",selector)
            if selector == kAudioDevicePropertyNominalSampleRate {
                s.reportedRate = s.getSampleRate(objectID)
            }
        }
        return kAudioHardwareNoError
    }
   
    func setSampleRate(_ deviceID: AudioDeviceID, _ rate: Double) {
        var nominalSampleRate = Float64(rate)
        let propertySize = UInt32(MemoryLayout<Float64>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectAddPropertyListener(deviceID, &propertyAddress, AudioOutput.setSampleRateListener, Unmanaged<AudioOutput>.passUnretained(self).toOpaque()))
        check(AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, &nominalSampleRate))
        // wait until reported rate is the requested rate
        var waitCounter: UInt32 = 0
        let waitMicrosecs = UInt32(5000), waitLimit = waitMicrosecs * 1000
        while reportedRate != rate {
            waitCounter += waitMicrosecs
            if waitCounter > waitLimit { break }
            usleep(waitMicrosecs)
        }
        check(AudioObjectRemovePropertyListener(deviceID, &propertyAddress, AudioOutput.setSampleRateListener, Unmanaged<AudioOutput>.passUnretained(self).toOpaque()))
        if waitCounter > waitLimit {
            print("AudioOutput setSampleRate timeout waiting for update")
        }
    }
    
    func getSreamVirtualFormat(_ deviceID: AudioDeviceID) -> AudioStreamBasicDescription {
        var description = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyVirtualFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &description))
        return description
    }
    
    func setStreamVirtualFormat(_ deviceID: AudioDeviceID, _ description: inout AudioStreamBasicDescription) {
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyVirtualFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &description))
    }

    func getSreamPhysicalFormat(_ deviceID: AudioDeviceID) -> AudioStreamBasicDescription {
        var description = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &description))
        return description
    }
    
    static func fourCharString(_ i:Int32)->String {
        // https://github.com/ooper-shlab/aurioTouch2.0-Swift/blob/master/PublicUtility/CAXException.swift
        let c1 = (i >> 24) & 0xFF,
            c2 = (i >> 16) & 0xFF,
            c3 = (i >>  8) & 0xFF,
            c4 = (i      ) & 0xFF
        if isprint(c1) != 0 && isprint(c2) != 0 && isprint(c3) != 0 && isprint(c4) != 0 {
            let cs = [CChar](arrayLiteral: CChar(c1), CChar(c2), CChar(c3), CChar(c4), 0)
            return String(cString: cs)
        }
        if i > -200000 && i < 200000 {
            return String(i)
        }
        return "0x" + String(UInt32(bitPattern:i), radix: 16)
    }
    
    @discardableResult
    private func check(_ err: OSStatus, file: String = #file, line: Int = #line) -> OSStatus! {
        if err != noErr {
            print("AudioOutput Error: \(AudioOutput.fourCharString(err)) in \(file):\(line)\n")
            return err
        }
        return nil
    }
   
#if false
    func getWorkgroup() {
        var workgroup: os_workgroup_t
        var propertySize = UInt32(MemoryLayout<os_workgroup_t>.size)
        var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyIOThreadOSWorkgroup,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &workgroup))
        print("AudioOutput getWorkgroup property size", propertySize)
    }
#endif

}
