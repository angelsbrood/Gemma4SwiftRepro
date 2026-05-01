import Foundation

// Default model dir — set via MODEL_DIR env var, or edit this line to point at
// your local snapshot of mlx-community/gemma-4-26b-a4b-it-8bit. Snapshot hash
// 1382fb7268fa62c07b83ffa174ff6fa455fb0686 (verified) is what these experiments
// were validated against.
let defaultModelDir = URL(filePath: "/path/to/gemma-4-26b-a4b-it-8bit/snapshots/1382fb7268fa62c07b83ffa174ff6fa455fb0686")

let modelDirectory: URL = {
    if let envPath = ProcessInfo.processInfo.environment["MODEL_DIR"], !envPath.isEmpty {
        return URL(filePath: envPath)
    }
    return defaultModelDir
}()

// Qwen 3.6 35B-A3B 8-bit dir for ExperimentF — set via QWEN_MODEL_DIR env var.
let qwenModelDirectory: URL = {
    if let envPath = ProcessInfo.processInfo.environment["QWEN_MODEL_DIR"], !envPath.isEmpty {
        return URL(filePath: envPath)
    }
    return URL(filePath: "/path/to/Qwen3.6-35B-A3B-8bit/snapshots/<hash>")
}()

print("Gemma4SwiftRepro")
print("Gemma model directory: \(modelDirectory.path)")
print("Qwen model directory:  \(qwenModelDirectory.path)")

// try await ExperimentA.run(modelDirectory: modelDirectory)  // ✓ passed
// try await ExperimentB.run(modelDirectory: modelDirectory)  // ✓ passed
// try await ExperimentC.run(modelDirectory: modelDirectory)  // ✓ passed
// try await ExperimentD.run(modelDirectory: modelDirectory)  // ✗ broadcast crash (64) vs (1139)
// try await ExperimentE.run(modelDirectory: modelDirectory)  // ✗ broadcast crash (64) vs (80)

// parser-test branch — swift-lm-response-parser experiments. Run one at a time.
// try await ExperimentF.run(modelDirectory: qwenModelDirectory)
// try await ExperimentG.run(modelDirectory: modelDirectory)
try await ExperimentH.run(modelDirectory: modelDirectory)
