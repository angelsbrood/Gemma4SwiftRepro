import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import Tokenizers

// Bisect: Experiment A's bare-minimum call + only the rep penalty added.
// If this crashes with the same broadcast pair, the trigger is the rep penalty
// alone (not the system prompt, not the tool specs, not temperature/top-p).
enum ExperimentE {
    static func run(modelDirectory: URL) async throws {
        print("Experiment E: bare minimum + rep penalty only")
        print("Model: \(modelDirectory.lastPathComponent)")

        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let container = try await VLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: tokenizerLoader)
        print("Container loaded.")

        let parameters = GenerateParameters(
            maxTokens: 32,
            repetitionPenalty: 1.1,
            repetitionContextSize: 64
        )

        let stream = try await container.perform { context in
            let chat: [Chat.Message] = [.user("Say hello.")]
            let userInput = UserInput(chat: chat)
            let lmInput = try await context.processor.prepare(input: userInput)
            return try MLXLMCommon.generate(
                input: lmInput, parameters: parameters, context: context)
        }

        var generated = ""
        for await event in stream {
            if case .chunk(let text) = event {
                generated += text
                print("CHUNK: \(text)", terminator: "")
            }
        }
        print("\n--- DONE ---")
        print("Generated \(generated.count) chars: \(generated)")
    }
}
