//
//  WaterfallScene.swift
//  SimpleSDR
//
//  Created by Andy Hooper on 2019-11-02.
//  Copyright © 2019 Andy Hooper. All rights reserved.
//

import SpriteKit

public class WaterfallImage {
    struct PixelWord {
        var b1,b2,b3,b4:UInt8
        init() {
            b1 = 0; b2 = 0; b3 = 0; b4 = 0
        }
        init(_ b1:UInt8, _ b2:UInt8, _ b3:UInt8, _ b4:UInt8) {
            self.b1 = b1; self.b2 = b2; self.b3 = b3; self.b4 = b4
        }
    }
    var palette: [PixelWord]?
    let white = PixelWord(255,255,255,255)
    let black = PixelWord(0,0,0,0)
    var width, height: Int
    var rowSize, dataSize, rowCount: Int
    var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        rowSize = width * MemoryLayout<PixelWord>.stride // RGBA
        dataSize = rowSize * height
        rowCount = 0
        bytes = [UInt8](repeating: 0, count: dataSize)
    }

    func setPalette(_ palette:[CGColor], alpha:CGFloat) {
        // assumes palette colorspace is generic RGB
        let a = UInt8(alpha * CGFloat(UInt8.max))
        self.palette = [PixelWord].init(unsafeUninitializedCapacity: palette.count) { pbp,pcount in
            for i in 0..<palette.count {
                let pi = CIColor(cgColor: palette[i])
                //TODO: colorSpace conversion https://developer.apple.com/library/archive/qa/qa1576/_index.html
                pbp[i] = PixelWord(UInt8(pi.red*255.9999),
                                   UInt8(pi.green*255.9999),
                                   UInt8(pi.blue*255.9999),
                                   a)
            }
            pcount = palette.count
        }
    }

    func clear() {
        rowCount = 0
    }
    
    func addRow(data:[Float], minValue:Float, maxValue:Float) {
        let paletteCount = palette!.count
        let paletteScale = Float(paletteCount) / (maxValue-minValue)
        precondition(data.count <= width)
        precondition(rowCount < height)
        guard let palette = palette else { return }
        bytes.withUnsafeMutableBytes { bp in
            // append new row
            var pwp = bp.baseAddress!.advanced(by: rowCount * rowSize)
            rowCount += 1
            for i in 0..<data.count {
                let v = data[i]
                let p = v < minValue ? black
                      : v >= maxValue ? white
                      : v.isNaN ? black
                      : palette[Int((data[i]-minValue) * paletteScale)]
                pwp.storeBytes(of: p, as: PixelWord.self)
                pwp += MemoryLayout<PixelWord>.stride
            }
        }
    }
    
    func makeTexture() -> SKTexture {
        let dataCount = rowSize * rowCount
        assert(dataCount <= bytes.count)
        return SKTexture(data: Data(bytes: bytes, count: dataCount),
                         size: CGSize(width: width, height: rowCount))
    }

}

public class WaterfallScene: SKScene {
    /// The spectrum waterfall scene consists of a fixed head node at the top
    /// with a series of descending sprites below. The head image grows line by
    /// line, and is transferred to a descending sprite when it reaches a fixed
    /// size. The size is a guess at balancing the work of displaying a number
    /// of sprites against the work for updating the image on the head.
    var head: SKSpriteNode?
    let headLineLimit = 100
    var descending = [SKSpriteNode]()
    var image: WaterfallImage?
    var palette: [CGColor]?
    
    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = CGPoint.zero
        setPalette(Palettes.turbo, alpha: 1.0)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("WaterfallScene init(coder:) has not been implemented")
    }
    
    func setPalette(_ palette:[CGColor], alpha:CGFloat) {
        self.palette = palette
        image?.setPalette(palette, alpha: alpha)
    }

    private func makeHeadImage(_ width: Int) {
        image = WaterfallImage(width: width, height: headLineLimit)
        if palette != nil {
            image!.setPalette(palette!, alpha: 1.0)
        }
    }
    
    func addLine(data:[Float], minValue:Float, maxValue:Float) {
        if image == nil {
            makeHeadImage(data.count)
            head = SKSpriteNode()
            head!.anchorPoint = CGPoint.zero
            head!.size.width = frame.width
            addChild(head!)
            //print("head",head.debugDescription)
        } else if image!.rowCount == image!.height || image!.width != data.count {
            //print("image", image!.bytes)
            // transfer head image to a moving sprite texture and start a new image
            let texture = image!.makeTexture()
            let sprite = SKSpriteNode(texture: texture)
            sprite.anchorPoint = CGPoint.zero
            sprite.position = CGPoint(x: 0, y: frame.height-CGFloat(image!.rowCount))
            sprite.scale(to: CGSize(width: frame.width, height: CGFloat(image!.rowCount)))
            addChild(sprite)
            descending.append(sprite)
            //print("add",sprite.debugDescription)
            if image!.width != data.count {
                makeHeadImage(data.count)
            } else {
                image!.clear()
            }
        }
        image!.addRow(data: data, minValue: minValue, maxValue: maxValue)
        head!.texture = image!.makeTexture()
        head!.size.height = head!.texture!.size().height
        // width set by didChangeSize
        head!.position = CGPoint(x: 0, y: frame.maxY-CGFloat(image!.rowCount))
        //print(head.debugDescription)
        
        // advance other sprites
        for i in 0..<descending.count {
            let di = descending[i]
            di.position.y -= 1
            if di.position.y + di.frame.height < 0 {
                //print("remove",di.debugDescription)
                removeChildren(in: [di])
                descending.remove(at: i) // should be the last
                break
            }
        }
    }
    
    override public func didChangeSize(_ oldSize: CGSize) {
        //print("WaterfallScene didChangeSize",frame)
        if let head = head {
            head.scale(to: CGSize(width: frame.width, height: head.size.height))
        }
        for i in 0..<descending.count {
            let di = descending[i]
            di.scale(to: CGSize(width: frame.width, height: di.size.height))
        }
        
        //TODO if height increased, move descending sprites up to head
    }
}
