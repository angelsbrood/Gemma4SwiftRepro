import Foundation
import LMResponseParser

// Shared helpers for the parser-test experiments (F, G, H).

/// Read `config.json` from a model snapshot directory and return
/// `(model_type, config_subset)`. Both flow into
/// `ResponseChatSession.init` so the bridge can call
/// `ResponseFormat.infer(modelName:modelType:modelConfig:)` — the dispatch
/// path real consumers exercise. `modelName` derived from a snapshot dir does
/// not match the library's name-prefix table, so `model_type` from config.json
/// is the load-bearing signal for our test models. The full config dict is
/// only consulted by the library for llama-2-vs-3 vocab-size disambiguation,
/// so we forward only the keys the library is documented to read (`vocab_size`).
func readModelConfig(at modelDirectory: URL) throws -> (modelType: String, config: [String: any Sendable]) {
    let configURL = modelDirectory.appendingPathComponent("config.json")
    let data = try Data(contentsOf: configURL)
    guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NSError(domain: "ParserSupport", code: 1, userInfo: [NSLocalizedDescriptionKey: "config.json is not a JSON object"])
    }
    let modelType = (raw["model_type"] as? String) ?? ""
    var config: [String: any Sendable] = [:]
    if let vocabSize = raw["vocab_size"] as? Int {
        config["vocab_size"] = vocabSize
    }
    return (modelType, config)
}

/// Pretty-print a single ResponseStreamingEvent on one line. Keeps output
/// scannable in per-experiment logs.
func describeEvent(_ event: ResponseStreamingEvent) -> String {
    switch event {
    case .responseCreated:
        return "responseCreated"
    case .responseInProgress:
        return "responseInProgress"
    case let .responseCompleted(e):
        return "responseCompleted(status=\(String(describing: e.response.status)), usage=\(String(describing: e.response.usage)))"
    case let .responseIncomplete(e):
        return "responseIncomplete(status=\(String(describing: e.response.status)), usage=\(String(describing: e.response.usage)))"
    case let .outputItemAdded(e):
        return "outputItemAdded(\(itemSummary(e.item)))"
    case let .outputItemDone(e):
        return "outputItemDone(\(itemSummary(e.item)))"
    case let .contentPartAdded(e):
        return "contentPartAdded(itemId=\(e.itemId) partKind=\(partKind(e.part)))"
    case let .contentPartDone(e):
        return "contentPartDone(itemId=\(e.itemId) partKind=\(partKind(e.part)))"
    case let .outputTextDelta(e):
        return "outputTextDelta(itemId=\(e.itemId) text=\(escape(e.delta)))"
    case let .outputTextDone(e):
        return "outputTextDone(itemId=\(e.itemId) text=\(escape(e.text)))"
    case let .functionCallArgumentsDelta(e):
        return "functionCallArgumentsDelta(itemId=\(e.itemId) delta=\(escape(e.delta)))"
    case let .functionCallArgumentsDone(e):
        return "functionCallArgumentsDone(itemId=\(e.itemId) arguments=\(escape(e.arguments)))"
    case let .reasoningDelta(e):
        return "reasoningDelta(itemId=\(e.itemId) delta=\(escape(e.delta)))"
    case let .reasoningDone(e):
        return "reasoningDone(itemId=\(e.itemId) text=\(escape(e.text)))"
    @unknown default:
        return "<unknown event \(event)>"
    }
}

private func itemSummary(_ item: ResponseOutputItem) -> String {
    switch item {
    case let .message(m):
        return "message(id=\(m.id) status=\(String(describing: m.status)))"
    case let .functionCall(f):
        return "functionCall(id=\(f.id) callId=\(f.callId) name=\(f.name) arguments=\(escape(f.arguments)) status=\(String(describing: f.status)))"
    case let .functionCallOutput(o):
        return "functionCallOutput(id=\(o.id) callId=\(o.callId))"
    case let .reasoning(r):
        return "reasoning(id=\(r.id) status=\(String(describing: r.status)))"
    @unknown default:
        return "<unknown item>"
    }
}

private func partKind(_ part: ResponseContentPart) -> String {
    switch part {
    case .outputText: return "outputText"
    case .reasoningText: return "reasoningText"
    case .refusal: return "refusal"
    @unknown default: return "<unknown part>"
    }
}

private func escape(_ s: String) -> String {
    let truncated = s.count > 200 ? String(s.prefix(200)) + "…" : s
    return "\"\(truncated.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\"", with: "\\\""))\""
}
