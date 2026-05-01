import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import Tokenizers

enum ExperimentC {
    static func run(modelDirectory: URL) async throws {
        print("Experiment C: system + user + tool specs")
        print("Model: \(modelDirectory.lastPathComponent)")

        let tokenizerLoader = #huggingFaceTokenizerLoader()
        let container = try await VLMModelFactory.shared.loadContainer(
            from: modelDirectory, using: tokenizerLoader)
        print("Container loaded.")

        let parameters = GenerateParameters(maxTokens: 64)

        let stream = try await container.perform { context in
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

            let chat: [Chat.Message] = [
                .system(realConciergeSoulPlusIntegratorInstructions),
                .user("Add a section titled 'Test' with body 'Hello.'")
            ]
            let userInput = UserInput(chat: chat, tools: tools)
            let lmInput = try await context.processor.prepare(input: userInput)
            return try MLXLMCommon.generate(
                input: lmInput, parameters: parameters, context: context)
        }

        var generated = ""
        for await event in stream {
            switch event {
            case .chunk(let text):
                generated += text
                print("CHUNK: \(text)", terminator: "")
            case .toolCall(let call):
                print("\nTOOL CALL: \(call.function.name) args=\(call.function.arguments)")
            case .info(let info):
                print("\nINFO: prompt=\(info.promptTokenCount) generated=\(info.generationTokenCount) stop=\(info.stopReason)")
            }
        }
        print("\n--- DONE ---")
        print("Generated \(generated.count) chars: \(generated)")
    }
}
