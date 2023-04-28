//
//  GraphView.swift
//  TrySwiftUI
//
//  Created by Andy Hooper on 2023-02-05.
//

import SwiftUI

public class GraphData: ObservableObject, Identifiable {
    public let id = UUID()
    typealias Point = (x:Float,y:Float)
    @Published var points: [Point]
    init(_ points: [Point]) {
        self.points = points
    }
}

public class GraphConfig: ObservableObject {
    @Published var min: GraphData.Point
    @Published var range: GraphData.Point
    @Published var scale: GraphData.Point
    @Published var labelX: String
    @Published var labelY: String
    @Published var formatX: String
    @Published var formatY: String
    @Published var numXIntervals: Int
    @Published var numYIntervals: Int
    struct LineStyle {
        var colour: Color
        var style = StrokeStyle()
        // TODO: LineConfig: marker, alpha, label
    }
    @Published var lineStyles: [LineStyle]
    init() {
        self.min = (0,0)
        self.range = (1,1)
        self.scale = (1,1)
        self.labelX = "X"
        self.labelY = "Y"
        self.formatX = "%f"
        self.formatY = "%f"
        self.numXIntervals = 10
        self.numYIntervals = 5
        self.lineStyles = [ .init(colour: Color(.black)) ]

    }
    init(min: GraphData.Point, max: GraphData.Point, scale: GraphData.Point,
         labelX: String, labelY: String, formatX: String, formatY: String,
         numXIntervals: Int, numYIntervals: Int, lineStyles: [LineStyle]) {
        self.min = min
        self.range = GraphData.Point(x: max.x - min.x,
                                     y: max.y - min.y)
        self.scale = scale
        self.labelX = labelX
        self.labelY = labelY
        self.formatX = formatX
        self.formatY = formatY
        self.numXIntervals = numXIntervals
        self.numYIntervals = numYIntervals
        self.lineStyles = lineStyles
    }
    var max : GraphData.Point {
        get { GraphData.Point(x: min.x + range.x,
                              y: min.y + range.y ) }
        set { range = GraphData.Point(x: newValue.x - min.x,
                                      y: newValue.y - min.y)}
    }
    func calculateTransform(_ size: CGSize) -> CGAffineTransform {
        CGAffineTransform.identity
            // flip Y coordinate
            .translatedBy(x: 0, y: size.height)
            .scaledBy(x: 1, y: -1)
            // data mapping
            .scaledBy(x: size.width / CGFloat(range.x),
                      y: size.height / CGFloat(range.y))
            .translatedBy(x: CGFloat(-min.x), y: CGFloat(-min.y))
    }
}

public struct GraphView: View {
    // Marking data and config as @ObservedObject here produces redundant updates
    var data : [GraphData]
    var config : GraphConfig
    
    public var body: some View {
        ZStack {
            PlotGrid(config: config)
            ForEach(0..<data.count, id: \.self) { i in
                PlotLine(data: data[i], config: config, lineStyle: config.lineStyles[i])
            }
            GeometryReader { geom in
                // Tracking rectangle
                let inverseTransform = config.calculateTransform(geom.size)
                                .scaledBy(x: CGFloat(config.scale.x), y: 1)
                                .inverted()
                if #available(macOS 13.0, *) {
                    Rectangle().foregroundColor(.clear)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoverLocation = location
                                if !isHovering { /*print("active");*/ NSCursor.crosshair.push() }
                                isHovering = true
                            case .ended:
                                if isHovering { /*print("ended");*/ NSCursor.pop() }
                                isHovering = false
                            }
                        }
                        .background(alignment: .topLeading) {
                            // using background instead of overlay avoids the fast moving mouse
                            // entering the text and interrupting the hover
                            if isHovering {
                                Text(trackingString(hoverLocation.applying(inverseTransform)))
                                    .offset(x: hoverLocation.x+10, y: hoverLocation.y-5)
                            }
                        }
                        .onTapGesture {
                            print("tap", hoverLocation.applying(inverseTransform))
                        }
                } else {
                    // TODO: Fallback on earlier versions
                    // https://swiftui-lab.com/a-powerful-combo/
                }
            }
            
        }
        .padding(EdgeInsets(top: 10, leading: 15*(config.labelY.count>0 ? 2 : 1),
                            bottom: 15*(config.labelX.count>0 ? 2 : 1), trailing: 10))
        .drawingGroup() // Metal rendering
        // https://www.hackingwithswift.com/books/ios-swiftui/enabling-high-performance-metal-rendering-with-drawinggroup
    }
    @State private var hoverLocation: CGPoint = .zero
    @State private var isHovering = false
    
    private func trackingString(_ p:CGPoint) ->String {
        return String(format: "%.3f, %.2f", p.x, p.y)
    }
}

private struct PlotGrid: View {
    @ObservedObject var config : GraphConfig
    let tickLength = CGFloat(3)
    //let labelFormatter = NumberFormatter()
    
    init(config: GraphConfig) {
        self.config = config
        //self.labelFormatter.usesSignificantDigits = true
        //self.labelFormatter.maximumSignificantDigits = 6
    }
    
    var body: some View {
        GeometryReader { geom in
            let dataGrid = GraphData.Point(x: config.range.x / Float(config.numXIntervals),
                                           y: config.range.y / Float(config.numYIntervals))
            let gridSize = CGSize(width: geom.size.width / CGFloat(config.numXIntervals),
                                  height: geom.size.height / CGFloat(config.numYIntervals))
        
            Text(config.labelX)
                .offset(x: 0, y: geom.size.height+10) // TODO: scale
                .frame(maxWidth: geom.size.width, alignment: .center)
            Text(config.labelY)
                .rotationEffect(Angle(radians: -.pi/2))
                .offset(x: -40, y: 0) // TODO: scale
                .frame(maxHeight: geom.size.height, alignment: .center)
            
            Path { path in
                //print("grid path")
                path.move(to: CGPoint(x: 0, y: geom.size.height))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: geom.size.width, y: 0))
                for i in 1...config.numXIntervals {
                    let x = gridSize.width * CGFloat(i)
                    path.move(to: CGPoint(x: x, y: -tickLength))
                    path.addLine(to: CGPoint(x: x, y: geom.size.height))
                }
                for i in 1...config.numYIntervals {
                    let y = gridSize.height * CGFloat(i)
                    path.move(to: CGPoint(x: -tickLength, y: y))
                    path.addLine(to: CGPoint(x: geom.size.width, y: y))
                }
            }
            .scale(x: 1, y: -1) // flip Y coordinate
            .stroke(.gray, // TODO: macOS 12 .secondary,
                    lineWidth: 0.5)
            
            ForEach(0...config.numXIntervals, id: \.self) { i in
                let x = gridSize.width * CGFloat(i),
                    v = (dataGrid.x * Float(i) + config.min.x) / config.scale.x,
                    s = String(format: config.formatX, v) //labelFormatter.string(from: v as NSNumber)!
                Text(s)
                    .offset(x: x, y: 0)
                    .frame(maxWidth: gridSize.width, alignment: .center)
            }
            .offset(x: -gridSize.width/2, y: geom.size.height)
            ForEach(0...config.numYIntervals, id: \.self) { i in
                let y = gridSize.height * CGFloat(i),
                    v = (dataGrid.y * Float(i) + config.min.y) / config.scale.y,
                    s = String(format: config.formatY, v)//labelFormatter.string(from: v as NSNumber)!
                Text(s)
                    .rotationEffect(Angle(radians: -.pi/2))
                    .frame(maxHeight: gridSize.height, alignment: .center)
                    .offset(x: 0, y: -y)
            }
            .offset(x: -15, y: geom.size.height-gridSize.height/2)
        }
    }
}

private struct PlotLine: View {
    @ObservedObject var data : GraphData
    @ObservedObject var config : GraphConfig
    let lineStyle: GraphConfig.LineStyle
    
    var body: some View {
        GeometryReader { geom in
            let transform = config.calculateTransform(geom.size)
            Path { path in
                //print("PlotLine data path", data.points)
                var move = true
                for dp in data.points {
                    if dp.x.isNaN || dp.y.isNaN { move = true; continue }
                    let gp = CGPoint(x: CGFloat(dp.x),
                                     y: CGFloat(dp.y))
                    if move {
                        path.move(to: gp)
                        move = false
                    } else {
                        path.addLine(to: gp)
                    }
                }
            }
            .transform(transform)
            .stroke(lineStyle.colour, style: lineStyle.style)
            .clipped()
        }
    }
}

struct GraphView_Previews: PreviewProvider {
    static var previews: some View {
        let data1 = GraphData([(0,-0.1),(1,0.4),(2,0.25),(3,0.6),(4,0.8)]),
            data2 = GraphData([(0,0.4),(1,0.9),(2,0.75),(3,1.1),(4,1.3)]),
            config = GraphConfig(min: (0,0.2),
                                 max: (8,1.5),
                                 scale: (1,1),
                                 labelX: "Ordinate",
                                 labelY: "Abscissa",
                                 formatX: "%.2f",
                                 formatY: "%.0f",
                                 numXIntervals: 10,
                                 numYIntervals: 4,
                                 lineStyles: [.init(colour: .green),
                                              .init(colour: .blue,
                                                    style: StrokeStyle(lineWidth: 3,
                                                                       dash: [9,3]))])
        VStack {
            GraphView(data: [data1,data2],
                      config: config)
                .background(Color.white)
                .foregroundColor(.secondary)
                .font(.system(size: 10))
                .frame(width: 600, height: 400)
            HStack {
                Button("Change data") {
                    print("Change data")
                    data1.points.removeFirst()
                }
                Button("Change label") {
                    print("Change label")
                    config.labelX = "Count \(data1.points.count)"
                }
            }
        }
    }
}
