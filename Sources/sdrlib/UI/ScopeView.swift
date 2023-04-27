//
//  ScopeView.swift
//  sdrplay1
//
//  Created by Andy Hooper on 2023-04-10.
//

import SwiftUI

struct ScopeView: View {
    @State var source: ScopeData?
    @State var viewData = [GraphData]()
    @State var config = GraphConfig(min: (0,-1),
                                    max: (1000, 1),
                                    scale: (1,1),
                                    labelX: "Time",
                                    labelY: "Level",
                                    formatX: "%.2f",
                                    formatY: "%.0f",
                                    numXIntervals: 10,
                                    numYIntervals: 5,
                                    lineStyles: [ GraphConfig.LineStyle(colour: Color(.blue)),
                                                  GraphConfig.LineStyle(colour: Color(.red)),
                                                  GraphConfig.LineStyle(colour: Color(.green)),
                                                  GraphConfig.LineStyle(colour: Color(.black)),
                                                  GraphConfig.LineStyle(colour: Color(.cyan)),
                                                  GraphConfig.LineStyle(colour: Color(.magenta)),
                                                  GraphConfig.LineStyle(colour: Color(.yellow)) ])
    @State var annotationColour = #colorLiteral(red: 0.501960814, green: 0.501960814, blue: 0.501960814, alpha: 1) // #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
    @State var backgroundColour = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) // #colorLiteral(red: 0.06361754484, green: 0.2487588786, blue: 0.2487588786, alpha: 1)
    
    // https://www.hackingwithswift.com/quick-start/swiftui/how-to-use-a-timer-with-swiftui
    static let REFRESH_HZ = 20.0
    let timer = Timer.publish(every: 1/REFRESH_HZ /*seconds*/, //TODO: configurable
                                      //TODO: tolerance
                              on: .main, in: .common).autoconnect()

    var body: some View {
        GraphView(data: viewData, config: config)
            .background(Color(backgroundColour))
            .foregroundColor(Color(annotationColour))
            .font(.system(size: 10))
            .onReceive(timer) { input in
                //print ("scope timer")
                guard let source = source else { return }
                if source.data.count > 0 {
                    //print("ScopeView", source.data.count)
                    let N = source.data.count
                    if viewData.count != source.numItems {
                        viewData = (0..<source.numItems).map { _ in
                            GraphData([GraphData.Point](repeating: GraphData.Point(.nan,.nan),
                                                        count: N)) }
                    }
                    source.readLock.lock(); defer {source.readLock.unlock()}
                    for j in 0..<source.numItems {
                        viewData[j].points.replaceSubrange(0..<viewData[j].points.count,
                                                           with: (0..<N).map {i in
                            GraphData.Point(x: Float(i) / Float(source.sampleFrequency),
                                            y:source.data[i][j])})
                    }
                }
        }

    }
}

struct ScopeView_Previews: PreviewProvider {
    static var previews: some View {
        ScopeView()
    }
}
