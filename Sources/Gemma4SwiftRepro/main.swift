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

print("Gemma4SwiftRepro")
print("Model directory: \(modelDirectory.path)")

// try await ExperimentA.run(modelDirectory: modelDirectory)  // ✓ passed
// try await ExperimentB.run(modelDirectory: modelDirectory)  // ✓ passed
// try await ExperimentC.run(modelDirectory: modelDirectory)  // ✓ passed
// try await ExperimentD.run(modelDirectory: modelDirectory)  // ✗ broadcast crash (64) vs (1139)
try await ExperimentE.run(modelDirectory: modelDirectory)
