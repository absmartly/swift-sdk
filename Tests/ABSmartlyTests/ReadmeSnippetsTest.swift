import Foundation
import XCTest

// ReadmeSnippets.swift compiles every ```swift block of README.md. This test fails when a block
// in the README is not in that file, so a README change cannot skip the compile check.
final class ReadmeSnippetsTest: XCTestCase {
	private func normalized(_ text: String) -> String {
		return text.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty && !$0.hasPrefix("import ") }
			.joined(separator: "\n")
	}

	func testEveryReadmeSnippetIsCompiled() throws {
		let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let readme = try String(
			contentsOf: testsDir.appendingPathComponent("../../README.md").standardized, encoding: .utf8)
		let compiled = normalized(
			try String(contentsOf: testsDir.appendingPathComponent("ReadmeSnippets.swift"), encoding: .utf8))

		let blocks = readme.components(separatedBy: "```swift\n").dropFirst().map {
			$0.components(separatedBy: "```").first ?? ""
		}
		XCTAssertGreaterThan(blocks.count, 20)
		for block in blocks {
			let snippet = normalized(block)
			XCTAssertTrue(snippet.isEmpty || compiled.contains(snippet), "README snippet not compiled:\n\(block)")
		}
	}
}
