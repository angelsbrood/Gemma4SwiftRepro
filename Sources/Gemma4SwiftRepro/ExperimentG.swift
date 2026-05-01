import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import Tokenizers
import LMResponseParser
import LMResponseParserMLX

// Experiment G: Gemma 4 26B-A4B 8-bit via LMResponseParserMLX, single tool
// call. Load-bearing test against the parent PLAN's question 1: does the
// library extract `<|tool_call>call:NAME{...}<tool_call|>` segments natively?
// Also question 2: does `<|channel>thought ...<channel|>` content classify as
// `reasoningText*` events?
//
// Setup mirrors ExperimentC (system prompt + two tool specs + same user
// prompt) but with `repetitionPenalty: nil` to dodge the broadcast crash
// reproduced by ExperimentE/D, and the model's output routed through
// `ResponseChatSession.streamResponseEvents` instead of
// `MLXLMCommon.generate`.
enum ExperimentG {
    static func run(modelDirectory: URL) async throws {
        print("Experiment G: Gemma 4 26B-A4B 8-bit via LMResponseParserMLX (single tool call)")
        print("Model: \(modelDirectory.lastPathComponent)")

        let (modelType, modelConfig) = try readModelConfig(at: modelDirectory)
        print("model_type from config.json: \(modelType.isEmpty ? "<missing>" : modelType)")

        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let container = try await VLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: tokenizerLoader)
        print("Container loaded.")

        let parameters = GenerateParameters(maxTokens: 512)

        let insertSectionSpec: ToolSpec = [
            "type": "function" as any Sendable,
            "function": [
                "name": "insert_section" as any Sendable,
                "description": "Insert a new section into the document." as any Sendable,
                "parameters": [
                    "type": "object" as any Sendable,
                    "properties": [
                        "heading": ["type": "string" as any Sendable, "description": "Section heading" as any Sendable] as [String: any Sendable] as any Sendable,
                        "content": ["type": "string" as any Sendable, "description": "Section body" as any Sendable] as [String: any Sendable] as any Sendable,
                    ] as [String: any Sendable] as any Sendable,
                    "required": ["heading", "content"] as [any Sendable] as any Sendable,
                ] as [String: any Sendable] as any Sendable,
            ] as [String: any Sendable] as any Sendable,
        ]
        let strReplaceSpec: ToolSpec = [
            "type": "function" as any Sendable,
            "function": [
                "name": "str_replace" as any Sendable,
                "description": "Replace text in the document." as any Sendable,
                "parameters": [
                    "type": "object" as any Sendable,
                    "properties": [
                        "old": ["type": "string" as any Sendable] as [String: any Sendable] as any Sendable,
                        "new": ["type": "string" as any Sendable] as [String: any Sendable] as any Sendable,
                    ] as [String: any Sendable] as any Sendable,
                    "required": ["old", "new"] as [any Sendable] as any Sendable,
                ] as [String: any Sendable] as any Sendable,
            ] as [String: any Sendable] as any Sendable,
        ]
        let tools: [ToolSpec] = [insertSectionSpec, strReplaceSpec]

        let session = ResponseChatSession(
            container,
            modelType: modelType,
            modelConfig: modelConfig,
            instructions: realConciergeSoulPlusIntegratorInstructions,
            generateParameters: parameters,
            tools: tools,
        )

        let stream = session.streamResponseEvents(
            prompt: "Add a section titled 'Test' with body 'Hello.'",
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
