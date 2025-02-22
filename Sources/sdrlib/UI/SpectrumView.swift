//
//  SpectrumView.swift
//  sdrplay1
//
//  Created by Andy Hooper on 2023-02-11.
//

import SwiftUI
import SpriteKit // for SpriteView
import Combine // for Publisher

public struct SpectrumView: View {
    let annotationColour = #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
    let backgroundColour = #colorLiteral(red: 0.06361754484, green: 0.2487588786, blue: 0.2487588786, alpha: 1)
    @State var source: SpectrumData?
    @State var dbData = [Float]()
    @State var points = [GraphData.Point]()
    @State var viewData = GraphData([])
    @State var config = GraphConfig(min: (-1,-100),
                                    max: (1, 0),
                                    scale: (1e3,1),
                                    labelX: "Frequency (kHz)",
                                    labelY: "Level (dB)",
                                    formatX: "%.2f",
                                    formatY: "%.0f",
                                    numXIntervals: 12,
                                    numYIntervals: 5,
                                    lineStyles: [.init(colour: Color( #colorLiteral(red: 0.6987945412, green: 0.9176391373, blue: 1, alpha: 1) ))])
    @State var centreHz = Double.nan
    @State var waterfall = WaterfallScene(size: CGSize(width: 1024, height: 200))
    
    // https://www.hackingwithswift.com/quick-start/swiftui/how-to-use-a-timer-with-swiftui
    public static let REFRESH_HZ = 20.0
    let timer: Publishers.Autoconnect<Timer.TimerPublisher>

    public init(source: SpectrumData?, refreshHz:Double = REFRESH_HZ) {
        // needs an explicit initializer to allow client access to set source
        self.source = source
        // have to initialize timer here since no way to call the implicit initializer
        timer = Timer.publish(every: 1/refreshHz /*seconds*/,
                                                //TODO: configurable
                                                //TODO: tolerance
                              on: .main, in: .common).autoconnect()
    }
    
    fileprivate func updatePoints() {
        points = (0..<points.count).map{ i in GraphData.Point(points[i].x, y:dbData[i]) }
        return
        for i in 0..<dbData.count {
            points[i].y = dbData[i]
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            GraphView(data: [viewData], config: config)
                .background(Color(backgroundColour))
                .foregroundColor(Color(annotationColour))
                .font(.system(size: 10))
                .onReceive(timer) { input in
                    //print ("spectrum timer")
                    guard let source = source else { return }
                    if source.centreHz != centreHz {
                        centreHz = source.centreHz
                        let fs = source.sampleFrequency()
                        config.min.x = Float(centreHz - fs / 2)
                        config.max.x = Float(centreHz + fs / 2)
                        if centreHz >= 10e6 {
                            config.scale.x = 1e6
                            config.labelX = "Frequency (MHz)"
                        } else {
                            config.scale.x = 1e3
                            config.labelX = "Frequency (kHz)"
                        }
                        //print("SpectrumView", "fs", fs, "centre", centreHz, "min", config.min, "max", config.max)
                        // reset spectrum when frequency changed
                        dbData = [Float](repeating: Float.nan, count: Int(source.N))
                        source.getdBandClear(&dbData)
                        // set to rebuild axes below
                        dbData.removeAll(keepingCapacity: true)
                    }
                    if source.available() {
                        //print("SpectrumView", source.numberSummed)
                        let N = Int(source.N)
                        if dbData.count != N {
                           dbData = [Float](repeating: Float.nan, count: N)
                            let bin = Float(source.sampleFrequency()) / Float(N)
                            print("SpectrumView", "bin", bin, "N", N)
                            points = (0..<N).map{ i in GraphData.Point(bin * Float(i) + config.min.x, y:dbData[i]) }
                            //print("SpectrumView", "points", points.map{p in p.x})
                        }
                        source.getdBandClear(&dbData)
                        // faster to rebuild than modify in place!
                        points = (0..<points.count).map{ i in GraphData.Point(points[i].x, y:dbData[i]) }
                        waterfall.addLine(data: dbData, minValue: config.min.y, maxValue: config.max.y)
                        viewData.points.replaceSubrange(0..<viewData.points.count, with: points)
                    }
            }
            if #available(macOS 12.0, *) {
                SpriteView(scene: waterfall,
                           preferredFramesPerSecond: 10,
                           options: [.ignoresSiblingOrder, .allowsTransparency],
                           debugOptions: [.showsFPS,.showsNodeCount])
                    .padding(EdgeInsets(top: 0, leading: 15*2, bottom: 0, trailing: 10))  // as in GraphView
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .background(Color(backgroundColour))
            } else {
                // Fallback on earlier versions
                // https://www.hackingwithswift.com/forums/swiftui/swiftui-spritekit-macos-catalina-10-15/2662/2669
                SKSceneView(scene: waterfall)
                    .padding(EdgeInsets(top: 0, leading: 15*2, bottom: 0, trailing: 10))  // as in GraphView
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .background(Color(backgroundColour))
            }
        }
    }
}

struct SpectrumView_Previews: PreviewProvider {
    static var previews: some View {
        let mockData = SpectrumData.mock()
        SpectrumView(source: mockData)
    }
}
