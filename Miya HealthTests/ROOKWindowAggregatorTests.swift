//
//  ROOKWindowAggregatorTests.swift
//  Miya HealthTests
//
//  Tests ROOKWindowAggregator against real local ROOK export v2 JSON samples.
//

import XCTest
@testable import Miya_Health

final class ROOKWindowAggregatorTests: XCTestCase {
    
    private func loadROOKDataset(fromRelativePath relativePath: String) throws -> ROOKDataset {
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = projectRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ROOKDataset.self, from: data)
    }
    
    func testWhoopWindowAggregation() throws {
        let dataset = try loadROOKDataset(fromRelativePath: "Rook Samples/ROOKConnect-Whoop-dataset-v2.json")
        let raw = ROOKWindowAggregator.buildWindowRawMetrics(age: 35, dataset: dataset)
        
        XCTAssertNotNil(raw.sleepDurationHours)
        XCTAssertNotNil(raw.restorativeSleepPercent)
        XCTAssertNotNil(raw.awakePercent)
        XCTAssertNotNil(raw.breathingRate)
        
        XCTAssertNotNil(raw.hrvMs)
        XCTAssertTrue(raw.hrvType == "rmssd" || raw.hrvType == "mixed")
    }
    
    func testAppleWindowAggregation() throws {
        let dataset = try loadROOKDataset(fromRelativePath: "Rook Samples/ROOKConnect-Apple Health-dataset-v2.json")
        let raw = ROOKWindowAggregator.buildWindowRawMetrics(age: 35, dataset: dataset)
        
        XCTAssertNotNil(raw.sleepDurationHours)
        XCTAssertNotNil(raw.restorativeSleepPercent)
        XCTAssertNotNil(raw.awakePercent)
        XCTAssertNotNil(raw.breathingRate)
        
        XCTAssertNotNil(raw.steps)
    }
}


