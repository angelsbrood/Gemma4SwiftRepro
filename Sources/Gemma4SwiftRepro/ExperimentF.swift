import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import Tokenizers
import LMResponseParser
import LMResponseParserMLX

// Experiment F: route Qwen 3.6 35B-A3B 8-bit output through
// `swift-lm-response-parser` (LMResponseParserMLX.ResponseChatSession). Goal:
// observe whether `<think>...</think>` reasoning content is correctly
// classified as `reasoningTextDelta`/`reasoningTextDone` events and whether
// the library recognizes Qwen 3.6's wire format at all.
enum ExperimentF {
    static func run(modelDirectory: URL) async throws {
        print("Experiment F: Qwen 3.6 35B-A3B 8-bit via LMResponseParserMLX")
        print("Model: \(modelDirectory.lastPathComponent)")

        let (modelType, modelConfig) = try readModelConfig(at: modelDirectory)
        print("model_type from config.json: \(modelType.isEmpty ? "<missing>" : modelType)")

        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: tokenizerLoader)
        print("Container loaded.")

        let parameters = GenerateParameters(maxTokens: 256)

        let session = ResponseChatSession(
            container,
            modelType: modelType,
            modelConfig: modelConfig,
            instructions: "You are a helpful assistant. Think briefly before answering.",
            generateParameters: parameters,
            tools: nil,
        )

        let stream = session.streamResponseEvents(
            prompt: "What is 2+2? Think briefly first.",
            images: [],
            videos: [],
        )

        var eventCount = 0
        for try await event in stream {
            eventCount += 1
            print("[\(eventCount)] \(describeEvent(event))")
        }
        print("--- DONE --- (\(eventCount) events)")
    }
}
