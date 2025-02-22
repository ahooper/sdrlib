//
//  SDRplay.swift
//  sdrplay1
//
//  Created by Andy Hooper on 2023-02-01.
//

//  https://www.sdrplay.com/docs/SDRplay_SDR_API_Specification.pdf
//  The SDRplay API uses shared memory, so the application must be un-sandboxed or
//  use an application group name https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AppSandboxInDepth/AppSandboxInDepth.html#//apple_ref/doc/uid/TP40011183-CH3-SW24

import class Foundation.NSCondition
import class Foundation.Thread
import sdrplay_api

public class SDRplay: BufferedSource<ComplexSamples> {

    public var devices = [sdrplay_api_DeviceT]()
    var deviceIndex = 0
    var deviceParams: UnsafeMutablePointer<sdrplay_api_DeviceParamsT>?
    
    static let SHORT_SCALE = 1.0/Float(1<<15)
    static let BUFFER_SIZE: Int = 2<<17
    var overflow: Int = 0 // the number of samples which could not fit
    var streamBuffer = Output() // for double buffering
        // private reduces calls to swift_beginAccess/swift_endAccess exclusivity protection
        // https://www.swift.org/blog/swift-5-exclusivity/
    var bufferFill = NSCondition()
    
    public init() {
        super.init(name: "SDRplay")
        setBufferSize(SDRplay.BUFFER_SIZE)
        getDevices()
    }

    // Set capacity for receive stream callback
    public func setBufferSize(_ size: Int) {
        streamBuffer = Output()
        outputBuffer = Output()
        produceBuffer = Output()
        streamBuffer.reserveCapacity(size)
        outputBuffer.reserveCapacity(size)
        produceBuffer.reserveCapacity(size)
    }
    
    func getDevices() {
        if devices.isEmpty {
            devices = [sdrplay_api_DeviceT](repeating: sdrplay_api_DeviceT(),
                                            count: Int(SDRPLAY_MAX_DEVICES))
            failIfError(sdrplay_api_Open(), "Open")
            var numDevices:UInt32 = 0
            failIfError(sdrplay_api_GetDevices(&devices, &numDevices, UInt32(SDRPLAY_MAX_DEVICES)),
                        "GetDevices")
            devices.removeLast(devices.count - Int(numDevices))
            for i in 0..<devices.count {
                // https://developer.apple.com/forums/thread/72120?answerId=699159022#699159022
                let serNoA = withUnsafeBytes(of: devices[i].SerNo) { raw_buf_ptr in
                                    [UInt8](raw_buf_ptr) }
                let serNo = String.decodeCString(serNoA, as: Unicode.ASCII.self)?.result ?? "Serno String conversion failed"
                let hwVer = (devices[i].hwVer == SDRPLAY_RSP1_ID) ? "RSP1" :
                            (devices[i].hwVer == SDRPLAY_RSP1A_ID) ? "RSP1A" :
                            (devices[i].hwVer == SDRPLAY_RSP2_ID) ? "RSP2" :
                            (devices[i].hwVer == SDRPLAY_RSPduo_ID) ? "RSPduo" :
                            (devices[i].hwVer == SDRPLAY_RSPdx_ID) ? "RSPdx" :
                                    "hwVer \(devices[i].hwVer)"
                print("SDRplay #\(i)", "serial", serNo, hwVer)
            }
        }
        if devices.isEmpty {
            failIfError(sdrplay_api_Fail, "No devices found")
        }

        sdrplay_api_LockDeviceApi() // Must lock API while device selection is peformed
        deviceIndex = 0
        failIfError(sdrplay_api_SelectDevice(&devices[deviceIndex]), "SelectDevice")
        sdrplay_api_UnlockDeviceApi() // finished device selection

        failIfError(sdrplay_api_GetDeviceParams(devices[deviceIndex].dev, &deviceParams),
                    "GetDeviceParams")
        printConfig()

    }
    
    deinit {
        stopReceive()
        sdrplay_api_ReleaseDevice(&devices[deviceIndex])
        sdrplay_api_UnlockDeviceApi()
        sdrplay_api_Close()
    }

    func failIfError(_ err:sdrplay_api_ErrT, _ desc:String) {
        if err == sdrplay_api_Success { return }
        let es = String(cString: sdrplay_api_GetErrorString(err))
        sdrplay_api_UnlockDeviceApi() // finished device selection
        sdrplay_api_Close()
        fatalError("SDRplay fail \(desc): \(es)")
    }
    
    public var tuneHz: Double {
        get {
            return deviceParams!.pointee.rxChannelA.pointee.tunerParams.rfFreq.rfHz
        }
        set {
            deviceParams!.pointee.rxChannelA.pointee.tunerParams.rfFreq.rfHz = newValue
            updateIfInit(sdrplay_api_Update_Tuner_Frf, sdrplay_api_Update_Ext1_None,
                         "Update_Tuner_Frf")
        }
    }

    public var sampleHz: Double {
        get {
            return deviceParams!.pointee.devParams.pointee.fsFreq.fsHz
        }
        set {
            deviceParams!.pointee.devParams.pointee.fsFreq.fsHz = newValue
            updateIfInit(sdrplay_api_Update_Dev_Fs, sdrplay_api_Update_Ext1_None,
                         "Update_Dev_Fs")
        }
    }
    
    public override func sampleFrequency() -> Double {
        let decim1 = (deviceParams!.pointee.rxChannelA.pointee.ctrlParams.decimation.enable != 0) ?
                        deviceParams!.pointee.rxChannelA.pointee.ctrlParams.decimation.decimationFactor : 1
        /* SDRplay_API_Specification_v3.06 s.3.13
         Conditions for LIF down-conversion to be enabled for all RSPs in single tuner mode:
         (fsHz == 8192000) && (bwType == sdrplay_api_BW_1_536) && (ifType == sdrplay_api_IF_2_048) => DecFac 4
         (fsHz == 8000000) && (bwType == sdrplay_api_BW_1_536) && (ifType == sdrplay_api_IF_2_048) => DecFac 4
         (fsHz == 8000000) && (bwType == sdrplay_api_BW_5_000) && (ifType == sdrplay_api_IF_2_048) => DecFac 4
         (fsHz == 2000000) && (bwType <= sdrplay_api_BW_0_300) && (ifType == sdrplay_api_IF_0_450) => DecFac 4
         (fsHz == 2000000) && (bwType == sdrplay_api_BW_0_600) && (ifType == sdrplay_api_IF_0_450) => DecFac 2
         (fsHz == 6000000) && (bwType <= sdrplay_api_BW_1_536) && (ifType == sdrplay_api_IF_1_620) => DecFac 3
         In RSPduo master/slave mode, down-conversion is always enabled.
         */
        let decim2 =
            (deviceParams!.pointee.devParams.pointee.fsFreq.fsHz == 8192000 &&
              deviceParams!.pointee.rxChannelA.pointee.tunerParams.bwType == sdrplay_api_BW_1_536 &&
              deviceParams!.pointee.rxChannelA.pointee.tunerParams.ifType == sdrplay_api_IF_2_048) ? 4
            : (deviceParams!.pointee.devParams.pointee.fsFreq.fsHz == 8000000 &&
              deviceParams!.pointee.rxChannelA.pointee.tunerParams.bwType == sdrplay_api_BW_1_536 &&
              deviceParams!.pointee.rxChannelA.pointee.tunerParams.ifType == sdrplay_api_IF_2_048) ? 4
            : (deviceParams!.pointee.devParams.pointee.fsFreq.fsHz == 8000000 &&
               deviceParams!.pointee.rxChannelA.pointee.tunerParams.bwType == sdrplay_api_BW_5_000 &&
               deviceParams!.pointee.rxChannelA.pointee.tunerParams.ifType == sdrplay_api_IF_2_048) ? 4
            : (deviceParams!.pointee.devParams.pointee.fsFreq.fsHz == 2000000 &&
               deviceParams!.pointee.rxChannelA.pointee.tunerParams.bwType.rawValue <= sdrplay_api_BW_0_300.rawValue &&
               deviceParams!.pointee.rxChannelA.pointee.tunerParams.ifType == sdrplay_api_IF_0_450) ? 4
            : (deviceParams!.pointee.devParams.pointee.fsFreq.fsHz == 2000000 &&
               deviceParams!.pointee.rxChannelA.pointee.tunerParams.bwType == sdrplay_api_BW_0_600 &&
               deviceParams!.pointee.rxChannelA.pointee.tunerParams.ifType == sdrplay_api_IF_0_450) ? 2
            : (deviceParams!.pointee.devParams.pointee.fsFreq.fsHz == 6000000 &&
               deviceParams!.pointee.rxChannelA.pointee.tunerParams.bwType.rawValue <= sdrplay_api_BW_1_536.rawValue &&
               deviceParams!.pointee.rxChannelA.pointee.tunerParams.ifType == sdrplay_api_IF_1_620) ? 3
            : 1
            //TODO In RSPduo master/slave mode, down-conversion is always enabled.
        //print("SDRplay", "sampleFrequency", sampleHz, decim1, decim2)
        return sampleHz / Double(decim1) / Double(decim2)
    }
    
    private func updateIfInit(_ reasonForUpdate: sdrplay_api_ReasonForUpdateT,
                              _ reasonForUpdateExt1: sdrplay_api_ReasonForUpdateExtension1T,
                              _ name:String) {
        if streamInit {
            failIfError(sdrplay_api_Update(devices[deviceIndex].dev,
                                           devices[deviceIndex].tuner,
                                           reasonForUpdate,
                                           reasonForUpdateExt1),
                                name)
        }
    }

    public var streamInit: Bool = false //TODO setter to do start/stopReceive
           
    private var callbackFns = sdrplay_api_CallbackFnsT(StreamACbFn: SDRplay_streamCallback,
                                                       StreamBCbFn: nil,
                                                       EventCbFn: SDRplay_eventCallback)
        // has to be var to be passed as C pointer, although unchanging

    var sampleCount:UInt64 = 0

    fileprivate func printConfig() {
        print("SDRplay",
              "fsHz", deviceParams!.pointee.devParams.pointee.fsFreq.fsHz,
              "samplesPerPkt", deviceParams!.pointee.devParams.pointee.samplesPerPkt,
              "dcOffset",deviceParams!.pointee.rxChannelA.pointee.ctrlParams.dcOffset.DCenable,
              "iqOffset",deviceParams!.pointee.rxChannelA.pointee.ctrlParams.dcOffset.IQenable,
              "decimation", deviceParams!.pointee.rxChannelA.pointee.ctrlParams.decimation.decimationFactor,
              "agc mode",deviceParams!.pointee.rxChannelA.pointee.ctrlParams.agc.enable.rawValue,
              "set",deviceParams!.pointee.rxChannelA.pointee.ctrlParams.agc.setPoint_dBfs,
              "adsbMode",deviceParams!.pointee.rxChannelA.pointee.ctrlParams.adsbMode.rawValue,
              "rfHz", deviceParams!.pointee.rxChannelA.pointee.tunerParams.rfFreq.rfHz,
              "bwType", deviceParams!.pointee.rxChannelA.pointee.tunerParams.bwType.rawValue,
              "ifType", deviceParams!.pointee.rxChannelA.pointee.tunerParams.ifType.rawValue,
              "loMode", deviceParams!.pointee.rxChannelA.pointee.tunerParams.loMode.rawValue,
              "LNAstate", deviceParams!.pointee.rxChannelA.pointee.tunerParams.gain.LNAstate,
              "gRdB", deviceParams!.pointee.rxChannelA.pointee.tunerParams.gain.gRdB)
        switch devices[deviceIndex].hwVer {
        case UInt8(SDRPLAY_RSP1_ID):
            break // no additional parameters
        case UInt8(SDRPLAY_RSP1A_ID):
            print("SDRplay", "RSP1A",
                  "rfNotchEnable", deviceParams!.pointee.devParams.pointee.rsp1aParams.rfNotchEnable,
                  "rfDabNotchEnable", deviceParams!.pointee.devParams.pointee.rsp1aParams.rfDabNotchEnable,
                  "biasTEnable", deviceParams!.pointee.rxChannelA.pointee.rsp1aTunerParams.biasTEnable)
        case UInt8(SDRPLAY_RSP2_ID):
            print("SDRplay", "RSP2",
                  "extRefOutputEn", deviceParams!.pointee.devParams.pointee.rsp2Params.extRefOutputEn,
                  "antennaSel", deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.antennaSel.rawValue,
                  "amPortSel", deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.amPortSel,
                  "biasTEnable", deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.biasTEnable,
                  "rfNotchEnable", deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.rfNotchEnable)
        case UInt8(SDRPLAY_RSPduo_ID):
            print("SDRplay", "RSPduo",
                  "decimation", deviceParams!.pointee.rxChannelB.pointee.ctrlParams.decimation.decimationFactor,
                  "rfHz", deviceParams!.pointee.rxChannelB.pointee.tunerParams.rfFreq.rfHz,
                  "bwType", deviceParams!.pointee.rxChannelB.pointee.tunerParams.bwType.rawValue,
                  "ifType", deviceParams!.pointee.rxChannelB.pointee.tunerParams.ifType.rawValue,
                  "loMode", deviceParams!.pointee.rxChannelB.pointee.tunerParams.loMode.rawValue,
                  "gRdB", deviceParams!.pointee.rxChannelB.pointee.tunerParams.gain.gRdB)
            print("SDRplay", "RSPduo",
                  "extRefOutputEn", deviceParams!.pointee.devParams.pointee.rspDuoParams.extRefOutputEn,
                  "biasTEnable", deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.biasTEnable,
                                 deviceParams!.pointee.rxChannelB.pointee.rspDuoTunerParams.biasTEnable,
                  "rfNotchEnable", deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.rfNotchEnable,
                                   deviceParams!.pointee.rxChannelB.pointee.rspDuoTunerParams.rfNotchEnable,
                  "rfDabNotchEnable", deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.rfDabNotchEnable,
                                      deviceParams!.pointee.rxChannelB.pointee.rspDuoTunerParams.rfDabNotchEnable,
                  "tuner1AmPortSel", deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.tuner1AmPortSel,
                  "tuner1AmNotchEnable", deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.tuner1AmNotchEnable)
        case UInt8(SDRPLAY_RSPdx_ID):
            print("SDRplay", "RSPdx",
                  "antennaSel", deviceParams!.pointee.devParams.pointee.rspDxParams.antennaSel.rawValue,
                  "biasTEnable", deviceParams!.pointee.devParams.pointee.rspDxParams.biasTEnable,
                  "hdrEnable", deviceParams!.pointee.devParams.pointee.rspDxParams.hdrEnable,
                  "rfNotchEnable", deviceParams!.pointee.devParams.pointee.rspDxParams.rfNotchEnable,
                  "rfDabNotchEnable", deviceParams!.pointee.devParams.pointee.rspDxParams.rfDabNotchEnable,
                  "hdrBwMode",deviceParams!.pointee.rxChannelA.pointee.rspDxTunerParams.hdrBw.rawValue)
        default:
            break
        }
    }

    public func startReceive() {
        sampleCount = 0
        failIfError(sdrplay_api_Init(devices[deviceIndex].dev,
                                             &callbackFns,
                                             Unmanaged<SDRplay>.passUnretained(self).toOpaque()),
                    "Init")
        streamInit = true
        printConfig()
    }
    
    public func stopReceive() {
        if streamInit {
            failIfError(sdrplay_api_Uninit(devices[deviceIndex].dev), "Uninit")
            streamInit = false
        }
    }

    func fillBuffer(_ processSize: Int) {
        bufferFill.lock() // BEGIN LOCK REGION
            while streamBuffer.count < processSize {
                /*print("SDRplay receiveLoop wait")*/
                bufferFill.wait()
            }
            //print("SDRplay receiveLoop", buffer.count)
            if overflow > 0 {
                print("SDRplay", streamBuffer.count, "overflow", overflow)
                overflow = 0
            }
            swap(&streamBuffer, &outputBuffer)
        bufferFill.unlock() // END LOCK REGION
    }
    
    public func receiveLoop(_ processSize: Int) {
        while !Thread.current.isCancelled {
            fillBuffer(processSize)
            sampleCount += UInt64(outputBuffer.count)
            //print("SDRplay produce", outputBuffer.count)
            if !streamInit { continue }  // has been stopped
            produce(clear:true)
        }
        print("SDRplay receiveLoop exit", "samples", sampleCount, "buffer capacity", streamBuffer.capacity)
        stopReceive()
    }

    
    public static let OptAntenna = "Antenna",
                      OptAntenna_A = "Antenna A",
                      OptAntenna_B = "Antenna B",
                      OptAntenna_Hi_Z = "Hi-Z",
                      OptAntenna_C = "Antenna C",
                      OptTuner_1_50_ohm = "Tuner 1 50 ohm",
                      OptTuner_2_50_ohm = "Tuner 2 50 ohm",
                      OptTuner_1_Hi_Z = "Tuner 1 Hi-Z"
    public static let OptBiasTee = "biasT_ctrl",
                      Opt_Enable = "enable",
                      Opt_Disable = "disable"
    public static let OptRFNotch = "rfnotch_ctrl"
    public static let OptDABNotch = "dabnotch_ctrl"
    public static let OptAGCMode = "agc_mode",
                      OptAGCMode_100Hz = "100Hz",
                      OptAGCMode_50Hz = "50Hz",
                      OptAGCMode_5Hz = "5Hz",
                      OptAGCMode_Disable = "disable"
    public static let OptDebug = "debug"
    public static let OptIFGainReduction = "if_gain_reduction"
    public static let OptAGCSetPoint = "agc_set_point"
    public static let OptDecimation = "decimation"
    public static let OptLNAstate = "LNAstate"
    public static let OptRFGainReduction = "rf_gain_reduction" // converted to OptLNAstate
    public static let OptBandwidth = "bandwidth",
                      OptBandwidth_0_200     = Int(sdrplay_api_BW_0_200.rawValue),
                      OptBandwidth_0_300     = Int(sdrplay_api_BW_0_300.rawValue),
                      OptBandwidth_0_600     = Int(sdrplay_api_BW_0_600.rawValue),
                      OptBandwidth_1_536     = Int(sdrplay_api_BW_1_536.rawValue),
                      OptBandwidth_5_000     = Int(sdrplay_api_BW_5_000.rawValue),
                      OptBandwidth_6_000     = Int(sdrplay_api_BW_6_000.rawValue),
                      OptBandwidth_7_000     = Int(sdrplay_api_BW_7_000.rawValue),
                      OptBandwidth_8_000     = Int(sdrplay_api_BW_8_000.rawValue)
    public static let OptIFType = "IF",
                      OptIF_Zero      = Int(sdrplay_api_IF_Zero.rawValue),
                      OptIF_0_450     = Int(sdrplay_api_IF_0_450.rawValue),
                      OptIF_1_620     = Int(sdrplay_api_IF_1_620.rawValue),
                      OptIF_2_048     = Int(sdrplay_api_IF_2_048.rawValue)
    public static let OptLOMode = "LO",
                      OptLO_Undefined = Int(sdrplay_api_LO_Undefined.rawValue),
                      OptLO_Auto      = Int(sdrplay_api_LO_Auto.rawValue),
                      OptLO_120MHz    = Int(sdrplay_api_LO_120MHz.rawValue),
                      OptLO_144MHz    = Int(sdrplay_api_LO_144MHz.rawValue),
                      OptLO_168MHz    = Int(sdrplay_api_LO_168MHz.rawValue)
    //TODO: RSPdx HDR mode

    public func getAntennas()-> [String] {
        switch devices[deviceIndex].hwVer {
        case UInt8(SDRPLAY_RSP1_ID):
            return []
        case UInt8(SDRPLAY_RSP1A_ID):
            return []
        case UInt8(SDRPLAY_RSP2_ID):
            return [SDRplay.OptAntenna_A, SDRplay.OptAntenna_B, SDRplay.OptAntenna_Hi_Z]
        case UInt8(SDRPLAY_RSPduo_ID):
            return [SDRplay.OptTuner_1_50_ohm, SDRplay.OptTuner_2_50_ohm, SDRplay.OptTuner_1_Hi_Z]
        case UInt8(SDRPLAY_RSPdx_ID):
            return [SDRplay.OptAntenna_A, SDRplay.OptAntenna_B, SDRplay.OptAntenna_C]
        default:
            return ["Unknown"]
        }
    }

    public func setOption(_ option: String, _ value: String) {
        var en: UInt8
        var update = sdrplay_api_Update_None,
            updateExt1 = sdrplay_api_Update_Ext1_None
        
        if option == SDRplay.OptAntenna {
            switch devices[deviceIndex].hwVer {
            
            case UInt8(SDRPLAY_RSP2_ID):
                if value == SDRplay.OptAntenna_A {
                    deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.amPortSel = sdrplay_api_Rsp2_AMPORT_2
                    deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.antennaSel = sdrplay_api_Rsp2_ANTENNA_A
                    update = sdrplay_api_ReasonForUpdateT(rawValue: sdrplay_api_Update_Rsp2_AmPortSelect.rawValue
                                                                  | sdrplay_api_Update_Rsp2_AntennaControl.rawValue)
                } else if value == SDRplay.OptAntenna_B {
                    deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.amPortSel = sdrplay_api_Rsp2_AMPORT_2
                    deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.antennaSel = sdrplay_api_Rsp2_ANTENNA_B
                    update = sdrplay_api_ReasonForUpdateT(rawValue: sdrplay_api_Update_Rsp2_AmPortSelect.rawValue
                                                                  | sdrplay_api_Update_Rsp2_AntennaControl.rawValue)
                } else if value == SDRplay.OptAntenna_Hi_Z {
                    deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.amPortSel = sdrplay_api_Rsp2_AMPORT_1
                    deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.antennaSel = sdrplay_api_Rsp2_ANTENNA_A
                    update = sdrplay_api_Update_Rsp2_AmPortSelect
                } else {
                    failIfError(sdrplay_api_InvalidParam, value)
                }
                
            case UInt8(SDRPLAY_RSPduo_ID):
                if value == SDRplay.OptTuner_1_50_ohm {
                    if devices[deviceIndex].tuner != sdrplay_api_Tuner_A {
                        failIfError(sdrplay_api_SwapRspDuoActiveTuner(devices[deviceIndex].dev,
                                                                             &devices[deviceIndex].tuner,
                                                                             sdrplay_api_RspDuo_AMPORT_2),
                                    "SwapRspDuoActiveTuner")
                        //TODO switch deviceParams?
                    } else {
                        deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.tuner1AmPortSel = sdrplay_api_RspDuo_AMPORT_2
                        update = sdrplay_api_Update_RspDuo_AmPortSelect
                    }
                } else if value == SDRplay.OptTuner_2_50_ohm {
                    if devices[deviceIndex].tuner != sdrplay_api_Tuner_B {
                        failIfError(sdrplay_api_SwapRspDuoActiveTuner(devices[deviceIndex].dev,
                                                                              &devices[deviceIndex].tuner,
                                                                              sdrplay_api_RspDuo_AMPORT_2),
                                    "SwapRspDuoActiveTuner")
                        //TODO switch deviceParams?
                    }
                } else if value == SDRplay.OptTuner_1_Hi_Z {
                    if devices[deviceIndex].tuner != sdrplay_api_Tuner_A {
                        failIfError(sdrplay_api_SwapRspDuoActiveTuner(devices[deviceIndex].dev,
                                                                             &devices[deviceIndex].tuner,
                                                                             sdrplay_api_RspDuo_AMPORT_1),
                                    "SwapRspDuoActiveTuner")
                        //TODO switch deviceParams?
                    } else {
                        deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.tuner1AmPortSel = sdrplay_api_RspDuo_AMPORT_1
                        update = sdrplay_api_Update_RspDuo_AmPortSelect
                    }
                } else {
                    failIfError(sdrplay_api_InvalidParam, value)
                }

            case UInt8(SDRPLAY_RSPdx_ID):
                if value == SDRplay.OptAntenna_A {
                    deviceParams!.pointee.devParams.pointee.rspDxParams.antennaSel = sdrplay_api_RspDx_ANTENNA_A
                    updateExt1 = sdrplay_api_Update_RspDx_AntennaControl
                } else if value == SDRplay.OptAntenna_B {
                    deviceParams!.pointee.devParams.pointee.rspDxParams.antennaSel = sdrplay_api_RspDx_ANTENNA_B
                    updateExt1 = sdrplay_api_Update_RspDx_AntennaControl
                } else if value == SDRplay.OptAntenna_C {
                    deviceParams!.pointee.devParams.pointee.rspDxParams.antennaSel = sdrplay_api_RspDx_ANTENNA_C
                    updateExt1 = sdrplay_api_Update_RspDx_AntennaControl
                } else {
                    failIfError(sdrplay_api_InvalidParam, value)
                }
                
            default:
                failIfError(sdrplay_api_InvalidParam, value)
            }
            
        } else if option == SDRplay.OptBiasTee {
            en = (value == SDRplay.Opt_Disable) ? 0 : 1
            switch devices[deviceIndex].hwVer {
            
            case UInt8(SDRPLAY_RSP1A_ID):
                deviceParams!.pointee.rxChannelA.pointee.rsp1aTunerParams.biasTEnable = en
                update = sdrplay_api_Update_Rsp1a_BiasTControl

            case UInt8(SDRPLAY_RSP2_ID):
                deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.biasTEnable = en
                update = sdrplay_api_Update_Rsp2_BiasTControl

            case UInt8(SDRPLAY_RSPduo_ID):
                if devices[deviceIndex].tuner == sdrplay_api_Tuner_A {
                    deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.biasTEnable = en
                } else {
                    deviceParams!.pointee.rxChannelB.pointee.rspDuoTunerParams.biasTEnable = en
                }
                update = sdrplay_api_Update_RspDuo_BiasTControl

            case UInt8(SDRPLAY_RSPdx_ID):
                deviceParams!.pointee.devParams.pointee.rspDxParams.biasTEnable = en
                updateExt1 = sdrplay_api_Update_RspDx_BiasTControl

            default:
                failIfError(sdrplay_api_InvalidParam, value)
            }

        } else if option == SDRplay.OptRFNotch {
            en = (value == SDRplay.Opt_Disable) ? 0 : 1
            switch devices[deviceIndex].hwVer {
            
            case UInt8(SDRPLAY_RSP1A_ID):
                deviceParams!.pointee.devParams.pointee.rsp1aParams.rfNotchEnable = en
                update = sdrplay_api_Update_Rsp1a_RfNotchControl

            case UInt8(SDRPLAY_RSP2_ID):
                deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.rfNotchEnable = en
                update = sdrplay_api_Update_Rsp2_RfNotchControl

            case UInt8(SDRPLAY_RSPduo_ID):
                if devices[deviceIndex].tuner == sdrplay_api_Tuner_A {
                    deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.rfNotchEnable = en
                } else {
                    deviceParams!.pointee.rxChannelB.pointee.rspDuoTunerParams.rfNotchEnable = en
                }
                update = sdrplay_api_Update_RspDuo_RfNotchControl

            case UInt8(SDRPLAY_RSPdx_ID):
                deviceParams!.pointee.devParams.pointee.rspDxParams.rfNotchEnable = en
                updateExt1 = sdrplay_api_Update_RspDx_RfNotchControl

            default:
                failIfError(sdrplay_api_InvalidParam, value)
            }

        } else if option == SDRplay.OptDABNotch {
            en = (value == SDRplay.Opt_Disable) ? 0 : 1
            switch devices[deviceIndex].hwVer {
            
            case UInt8(SDRPLAY_RSP1A_ID):
                deviceParams!.pointee.devParams.pointee.rsp1aParams.rfDabNotchEnable = en
                update = sdrplay_api_Update_Rsp1a_RfDabNotchControl

            case UInt8(SDRPLAY_RSPduo_ID):
                if devices[deviceIndex].tuner == sdrplay_api_Tuner_A {
                    deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.rfDabNotchEnable = en
                } else {
                    deviceParams!.pointee.rxChannelB.pointee.rspDuoTunerParams.rfDabNotchEnable = en
                }
                update = sdrplay_api_Update_RspDuo_RfDabNotchControl

            case UInt8(SDRPLAY_RSPdx_ID):
                deviceParams!.pointee.devParams.pointee.rspDxParams.rfDabNotchEnable = en
                updateExt1 = sdrplay_api_Update_RspDx_RfDabNotchControl

            default:
                failIfError(sdrplay_api_InvalidParam, value)
            }

        } else if option == SDRplay.OptAGCMode {
            if value == SDRplay.OptAGCMode_100Hz {
                deviceParams!.pointee.rxChannelA.pointee.ctrlParams.agc.enable = sdrplay_api_AGC_100HZ
            } else if value == SDRplay.OptAGCMode_50Hz {
                deviceParams!.pointee.rxChannelA.pointee.ctrlParams.agc.enable = sdrplay_api_AGC_50HZ
            } else if value == SDRplay.OptAGCMode_5Hz {
                deviceParams!.pointee.rxChannelA.pointee.ctrlParams.agc.enable = sdrplay_api_AGC_5HZ
            } else if value == SDRplay.Opt_Disable {
                deviceParams!.pointee.rxChannelA.pointee.ctrlParams.agc.enable = sdrplay_api_AGC_DISABLE
            } else {
                failIfError(sdrplay_api_InvalidParam, value)
            }
            update = sdrplay_api_Update_Ctrl_Agc
     
        } else if option == SDRplay.OptDebug {
            failIfError(sdrplay_api_DebugEnable(devices[deviceIndex].dev,
                                    (value == SDRplay.Opt_Disable) ? sdrplay_api_DbgLvl_Disable
                                                                   : sdrplay_api_DbgLvl_Verbose),
                        "DebugEnable")
            
        } else {
            failIfError(sdrplay_api_InvalidParam, option)
            
        }
        if update != sdrplay_api_Update_None || updateExt1 != sdrplay_api_Update_Ext1_None {
            updateIfInit(update, updateExt1, option)
        }
    }

    public func setOption(_ option: String, _ value: Int) {
        if option == SDRplay.OptIFGainReduction {
            deviceParams!.pointee.rxChannelA.pointee.tunerParams.gain.gRdB = Int32(value)
            updateIfInit(sdrplay_api_Update_Tuner_Gr, sdrplay_api_Update_Ext1_None, option)

        } else if option == SDRplay.OptAGCSetPoint {
            deviceParams?.pointee.rxChannelA.pointee.ctrlParams.agc.setPoint_dBfs = Int32(value)
            updateIfInit(sdrplay_api_Update_Ctrl_Agc, sdrplay_api_Update_Ext1_None, option)

        } else if option == SDRplay.OptLNAstate {
            deviceParams!.pointee.rxChannelA.pointee.tunerParams.gain.LNAstate = UInt8(value)
            updateIfInit(sdrplay_api_Update_Tuner_Gr, sdrplay_api_Update_Ext1_None, option)

        } else if option == SDRplay.OptRFGainReduction {
            deviceParams!.pointee.rxChannelA.pointee.tunerParams.gain.LNAstate = findLNAState(value)
            updateIfInit(sdrplay_api_Update_Tuner_Gr, sdrplay_api_Update_Ext1_None, option)
            
        } else if option == SDRplay.OptDecimation {
            if value == 1 {
                deviceParams!.pointee.rxChannelA.pointee.ctrlParams.decimation.enable = 0
            } else if value > 1 && value <= 64 {
                deviceParams!.pointee.rxChannelA.pointee.ctrlParams.decimation.enable = 1
                deviceParams!.pointee.rxChannelA.pointee.ctrlParams.decimation.decimationFactor = UInt8(value)
                deviceParams!.pointee.rxChannelA.pointee.ctrlParams.decimation.wideBandSignal = 1
            }
            updateIfInit(sdrplay_api_Update_Ctrl_Decimation, sdrplay_api_Update_Ext1_None, option)
            
        } else if option == SDRplay.OptBandwidth {
            deviceParams!.pointee.rxChannelA.pointee.tunerParams.bwType = sdrplay_api_Bw_MHzT(rawValue: UInt32(value))
            updateIfInit(sdrplay_api_Update_Tuner_BwType, sdrplay_api_Update_Ext1_None, option)

        } else if option == SDRplay.OptIFType {
            deviceParams!.pointee.rxChannelA.pointee.tunerParams.ifType = sdrplay_api_If_kHzT(rawValue: Int32(value))
            updateIfInit(sdrplay_api_Update_Tuner_IfType, sdrplay_api_Update_Ext1_None, option)

        } else if option == SDRplay.OptLOMode {
            deviceParams!.pointee.rxChannelA.pointee.tunerParams.loMode = sdrplay_api_LoModeT(rawValue: UInt32(value))
            updateIfInit(sdrplay_api_Update_Tuner_LoMode, sdrplay_api_Update_Ext1_None, option)

        } else if option == SDRplay.OptDebug {
            failIfError(sdrplay_api_DebugEnable(devices[deviceIndex].dev,
                                                        sdrplay_api_DbgLvl_t(rawValue: UInt32(value))),
                        "DebugEnable")
            
        } else{
            failIfError(sdrplay_api_InvalidParam, option)
        }
    }
    
    /*
     https://www.sdrplay.com/docs/SDRplay_API_Specification_v3.08.pdf
     Section 5 Gain Reduction Tables
     */
    func findLNAState(_ grdB: Int)-> UInt8 {
        switch devices[deviceIndex].hwVer {
        case UInt8(SDRPLAY_RSP1_ID):
            return
                tuneHz < 420e6 ? findLNAState(grdB, [0,24,19,43]) :
                tuneHz < 1000e6 ? findLNAState(grdB, [0,7,19,26]) :
                tuneHz < 2000e6 ? findLNAState(grdB, [0,5,19,24]) : 0
        
        case UInt8(SDRPLAY_RSP1A_ID):
            return
                tuneHz < 60e6 ? findLNAState(grdB, [0,6,12,18,37,42,61]) :
                tuneHz < 420e6 ? findLNAState(grdB, [0,6,12,18,20,26,32,38,57,62]) :
                tuneHz < 1000e6 ? findLNAState(grdB, [0,7,13,19,20,27,33,39,45,64]) :
                tuneHz < 2000e6 ? findLNAState(grdB, [0,6,12,20,26,32,38,43,62]) : 0

        case UInt8(SDRPLAY_RSP2_ID):
            let hiZ = (deviceParams!.pointee.rxChannelA.pointee.rsp2TunerParams.amPortSel == sdrplay_api_Rsp2_AMPORT_1)
            return
                tuneHz < 60e6 && hiZ ? findLNAState(grdB, [0,6,12,18,37]) :
                tuneHz < 420e6 ? findLNAState(grdB, [0,10,15,21,24,34,39,45,64]) :
                tuneHz < 1000e6 ? findLNAState(grdB, [0,7,10,17,22,41]) :
                tuneHz < 2000e6 ? findLNAState(grdB, [0,5,21,15,15,34]) : 0

        case UInt8(SDRPLAY_RSPduo_ID):
            let hiZ = (deviceParams!.pointee.rxChannelA.pointee.rspDuoTunerParams.tuner1AmPortSel == sdrplay_api_RspDuo_AMPORT_1)
            return
                tuneHz < 60e6 && hiZ ? findLNAState(grdB, [0,6,12,18,37]) :
                tuneHz < 60e6 ? findLNAState(grdB, [0,6,12,18,37,42,61]) :
                tuneHz < 420e6 ? findLNAState(grdB, [0,6,12,18,20,26,32,38,57,62]) :
                tuneHz < 1000e6 ? findLNAState(grdB, [0,7,13,19,20,27,33,39,45,64]) :
                tuneHz < -2000e6 ? findLNAState(grdB, [0,6,12,20,26,32,38,43,62]) : 0

        case UInt8(SDRPLAY_RSPdx_ID):
            let hdr = (deviceParams!.pointee.devParams.pointee.rspDxParams.hdrEnable != 0)
            return
                tuneHz < 2e6 && hdr ? findLNAState(grdB, [0,3,6,9,12,15,18,21,24,25,27,30,33,36,
                                                          39,42,45,48,51,54,57,60]) :
                tuneHz < 12e6 ? findLNAState(grdB, [0,3,6,9,12,15,24,27,30,33,36,39,42,45,
                                                    48,51,54,57,60]) :
                tuneHz < 60e6 ? findLNAState(grdB, [0,3,6,9,12,15,18,24,27,30,33,36,39,42,
                                                    45,48,51,54,57,60]) :
                tuneHz < 250e6 ? findLNAState(grdB, [0,3,6,9,12,15,24,27,30,33,36,39,42,45,
                                                     48,51,54,57,60,63,66,69,72,75,78,81,84]) :
                tuneHz < 420e6 ? findLNAState(grdB, [0,3,6,9,12,15,18,24,27,30,33,36,39,42,
                                                     45,48,51,54,57,60,63,66,69,72,75,78,81,84]) :
                tuneHz < 1000e6 ? findLNAState(grdB, [0,7,10,13,16,19,22,25,31,34,37,40,43,46,
                                                      49,52,55,58,61,64,67]) :
                tuneHz < 2000e6 ? findLNAState(grdB, [0,5,8,11,14,17,20,32,35,38,41,44,47,50,
                                                      53,56,59,62,65]) : 0

        default:
            failIfError(sdrplay_api_InvalidParam, String(grdB))
            return 0
        }
    }
    
    func findLNAState(_ grdB: Int, _ list: [UInt8])-> UInt8  {
        UInt8(list.firstIndex(where: { v in grdB <= v }) ?? list.count-1)
    }

}

extension SplitComplex {
    fileprivate mutating func append(_ xi: UnsafePointer<Int16>,
                                     _ xq: UnsafePointer<Int16>,
                                     _ n: Int, _ scale: Float) {
        // Alternatives tried:
#if false
        for j in 0..<n {
            append(ComplexSamples.Element(
                real: Float(xi[j]) * SDRplay.SHORT_SCALE,
                imag: Float(xq[j]) * SDRplay.SHORT_SCALE))
        }
#elseif false
        // In old Swift releases, this seemed to discard reserved capacity,
        // which is important for performance
        append(contentsOf: (0..<n).map{ComplexSamples.Element(
                                            Float(xi[$0]) * SDRplay.SHORT_SCALE,
                                            Float(xq[$0]) * SDRplay.SHORT_SCALE)})
#elseif false
        // In old Swift releases, this seemed to discard reserved capacity,
        // which is important for performance
        let xiBuf = UnsafeBufferPointer(start:xi, count:n),
            xqBuf = UnsafeBufferPointer(start:xq, count:n)
        append(real: xiBuf.map{Float($0) * SDRplay.SHORT_SCALE},
               imag: xqBuf.map{Float($0) * SDRplay.SHORT_SCALE})
#elseif true
        re.append(contentsOf:
                    UnsafeBufferPointer(start:xi, count:n).map{Float($0) * scale})
        im.append(contentsOf: 
                    UnsafeBufferPointer(start:xq, count:n).map{Float($0) * scale})
#endif
    }
}

/// This callback is triggered when there are samples to be processed.
/// - Parameter xi: Pointer to the real data in the buffer
/// - Parameter xq: Pointer to the imaginary data in the buffer
/// - Parameter params: Pointer to the stream callback parameters structure
/// - Parameter numSamples: The number of samples in the current buffer
/// - Parameter reset: Indicates if a re-initialisation has occurred within
///                     the API and that local buffering should be reset
/// - Parameter cbContext: Pointer to context passed into sdrplay_api_Init()
func SDRplay_streamCallback(xi: UnsafeMutablePointer<Int16>?,
                            xq: UnsafeMutablePointer<Int16>?,
                            params: UnsafeMutablePointer<sdrplay_api_StreamCbParamsT>?,
                            numSamples: UInt32,
                            reset: UInt32,
                            cbContext: UnsafeMutableRawPointer?) {
    let s = Unmanaged<SDRplay>.fromOpaque(cbContext!).takeUnretainedValue() // "self"
    //print("SDRplay StreamACbFn", numSamples)
    if let params = params {
        //                if params.pointee.fsChanged != 0 {
        //                    print("SDRplay StreamACbFn fsChanged")
        //                }
        //                if params.pointee.rfChanged != 0 {
        //                    print("SDRplay StreamACbFn rfhanged")
        //                }
        //                if params.pointee.grChanged != 0 {
        //                    print("SDRplay StreamACbFn grChanged")
        //                }
    }
    if s.streamInit {
        if let xi = xi, let xq = xq {
            s.bufferFill.lock() // BEGIN LOCK REGION
            let n = min(Int(numSamples),
                        s.streamBuffer.capacity - s.streamBuffer.count)
            s.streamBuffer.append(xi, xq, n, SDRplay.SHORT_SCALE)
            s.overflow += (Int(numSamples)-n)
            //print("SDRplay callback signal", numSamples, s.buffer.count, s.buffer.capacity, n )
            s.bufferFill.signal()
            s.bufferFill.unlock() // END LOCK REGION
        }
    }
}
    
/// This callback is triggered whenever an event occurs. The list of events
/// is specified by the sdrplay_api_EventT enumerated type.
/// - Parameter eventId: Indicates the type of event that has occurred
/// - Parameter tuner: Indicates which tuner(s) the event relates to
/// - Parameter params: Pointer to the event callback union (the structure used depends on the eventId)
/// cbContext: Pointer to context passed into sdrplay_api_Init()
func SDRplay_eventCallback(eventId: sdrplay_api_EventT,
                           tuner: sdrplay_api_TunerSelectT,
                           params: UnsafeMutablePointer<sdrplay_api_EventParamsT>?,
                           cbContext: UnsafeMutableRawPointer?) {
    let s = Unmanaged<SDRplay>.fromOpaque(cbContext!).takeUnretainedValue() // "self"
    switch eventId {
    case sdrplay_api_GainChange:
        print("SDRplay GainChange",
              "tuner", tuner.rawValue,
              "gRdB", params!.pointee.gainParams.gRdB,
              "lnaGRdB", params!.pointee.gainParams.lnaGRdB,
              "currGain", String(format:"%.1f",params!.pointee.gainParams.currGain))
    case sdrplay_api_PowerOverloadChange:
        print("SDRplay PowerOverloadChange",
              "tuner", tuner.rawValue,
              params!.pointee.powerOverloadParams.powerOverloadChangeType == sdrplay_api_Overload_Detected ? "detected" : "corrected")
        // Must acknowledge power overload message received
        sdrplay_api_Update(s.devices[s.deviceIndex].dev,
                           tuner,
                           sdrplay_api_Update_Ctrl_OverloadMsgAck,
                           sdrplay_api_Update_Ext1_None)
    case sdrplay_api_DeviceRemoved:
        print("SDRplay DeviceRemoved")
        sdrplay_api_Uninit(s.devices[s.deviceIndex].dev)
    case sdrplay_api_RspDuoModeChange:
        print("SDRplay RspDuoModeChange",
              "tuner", tuner.rawValue,
              params!.pointee.rspDuoModeParams.modeChangeType.rawValue)
    default:
        print("SDRplay EventCbFn unknown event", eventId.rawValue,
              "tuner", tuner.rawValue)
    }
}
