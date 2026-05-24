import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class ProcessRunnerTests: XCTestCase {
    func testRunDrainsLargeStdoutAndStderrBeforeWaitingForExit() throws {
        let temp = try TemporaryDirectory()
        let scriptURL = temp.url.appendingPathComponent("large-output.sh")
        try writeExecutable(
            scriptURL,
            contents: """
            #!/bin/zsh
            /usr/bin/perl -e 'print "o" x 1048576'
            /usr/bin/perl -e 'print STDERR "e" x 1048576'
            exit 7
            """
        )

        let result = try FoundationProcessRunner().run(
            executableURL: scriptURL,
            arguments: [],
            input: nil,
            currentDirectoryURL: nil,
            environment: [:]
        )

        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.stdout.count, 1_048_576)
        XCTAssertEqual(result.stderr.count, 1_048_576)
    }
}
