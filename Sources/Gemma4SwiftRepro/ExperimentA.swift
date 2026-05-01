import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import Tokenizers

enum ExperimentA {
    static func run(modelDirectory: URL) async throws {
        print("Experiment A: bare minimum load + generate")
        print("Model: \(modelDirectory.lastPathComponent)")

        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let container = try await VLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: tokenizerLoader)
        print("Container loaded.")

        let parameters = GenerateParameters(maxTokens: 32)

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
