import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import Tokenizers
import LMResponseParser
import LMResponseParserMLX

// Experiment H: Gemma 4 26B-A4B 8-bit via LMResponseParserMLX, multi-tool-call.
// Same setup as ExperimentG (system prompt + same two tool specs +
// `repetitionPenalty: nil`), but with a prompt designed to elicit two
// consecutive tool calls in a single response. Tests whether the parser:
// - extracts both `<|tool_call>...<tool_call|>` segments
// - emits two `outputItemAdded(functionCall(...))` events
// - preserves order
// - parses each call's arguments correctly
// - classifies any inter-call prose as content vs. reasoning
//
// Increased `maxTokens` to 1024 so the model has headroom for both segments.
enum ExperimentH {
    static func run(modelDirectory: URL) async throws {
        print("Experiment H: Gemma 4 26B-A4B 8-bit via LMResponseParserMLX (multi-tool-call)")
        print("Model: \(modelDirectory.lastPathComponent)")

        let (modelType, modelConfig) = try readModelConfig(at: modelDirectory)
        print("model_type from config.json: \(modelType.isEmpty ? "<missing>" : modelType)")

        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let container = try await VLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: tokenizerLoader)
        print("Container loaded.")

        let parameters = GenerateParameters(maxTokens: 1024)

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

        // Single-pass test: no toolDispatch. Captures whether the parser
        // extracts multiple `<|tool_call>...<tool_call|>` segments from one
        // generation. (We separately ran with a dummy dispatcher returning
        // "OK" — see results/H-gemma4-multi-dispatcher-loop.txt — and observed
        // a degenerate retry loop, which surfaces a different concern about
        // dispatcher realism but doesn't speak to single-response multi-call
        // parsing.)
        let session = ResponseChatSession(
            container,
            modelType: modelType,
            modelConfig: modelConfig,
            instructions: realConciergeSoulPlusIntegratorInstructions,
            generateParameters: parameters,
            tools: tools,
        )

        let stream = session.streamResponseEvents(
            prompt: "Do two things: insert a section called 'Test' with body 'Hello.', then immediately str_replace 'Test' with 'Confirmed'.",
            images: [],
            videos: [],
        )

        var eventCount = 0
        var toolCallAddedCount = 0
        for try await event in stream {
            eventCount += 1
            print("[\(eventCount)] \(describeEvent(event))")
            if case let .outputItemAdded(e) = event, case .functionCall = e.item {
                toolCallAddedCount += 1
            }
        }
        print("--- DONE --- (\(eventCount) events, \(toolCallAddedCount) functionCall items added)")
    }
}
