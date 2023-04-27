//
//  ScopeData.swift
//  SimpleSDR3
//
//  Created by Andy Hooper on 2021-01-05.
//  Copyright © 2021 Andy Hooper. All rights reserved.
//

import class Foundation.NSLock

class ScopeData {
    let numItems: Int
    let numPoints: Int
    let sampleFrequency: Double
    var data: [[Float]]
    let readLock:NSLock
    init(numItems: Int, numPoints: Int, sampleFrequency: Double) {
        self.numItems = numItems
        self.numPoints = numPoints
        self.sampleFrequency = sampleFrequency
        data = [[Float]]()
        readLock = NSLock()
    }
    func sample(_ d: [Float]) {
        precondition(d.count == numItems)
        readLock.lock(); defer {readLock.unlock()}
        if data.count == numPoints { data.removeAll(keepingCapacity: true) }
        data.append(d)
    }
}
