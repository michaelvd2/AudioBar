import Foundation
import XCTest

final class AudioProcessStoreSourceTests: XCTestCase {
    func testEQEditsEnableTheEffectBeforeUpdatingEngine() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)

        for functionName in ["setEQGain", "setEQPreamp", "applyEQPreset"] {
            let function = try XCTUnwrap(source.function(named: functionName))
            XCTAssertTrue(function.contains("eqSettings.isBypassed = false"), functionName)
            XCTAssertTrue(function.contains("updateEQEngine()"), functionName)
        }
    }

    func testTurningEQOnRestartsTheRoute() throws {
        let source = try String(contentsOf: audioProcessStoreURL(), encoding: .utf8)
        let function = try XCTUnwrap(source.function(named: "setEQBypassed"))

        XCTAssertTrue(function.contains("restartEQEngine()"))
        XCTAssertTrue(function.contains("updateEQEngine()"))
    }

    private func audioProcessStoreURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AudioBar/Stores/AudioProcessStore.swift")
    }
}

private extension String {
    func function(named name: String) -> String? {
        guard let start = range(of: "func \(name)")?.lowerBound else {
            return nil
        }

        var braceDepth = 0
        var didOpenBody = false
        var index = start
        while index < endIndex {
            let character = self[index]
            if character == "{" {
                braceDepth += 1
                didOpenBody = true
            } else if character == "}" {
                braceDepth -= 1
                if didOpenBody && braceDepth == 0 {
                    return String(self[start...index])
                }
            }
            index = self.index(after: index)
        }

        return nil
    }
}
