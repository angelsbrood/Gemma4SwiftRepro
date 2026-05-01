# Gemma4SwiftRepro

Standalone reproducer for a `broadcast_shapes` fatal error that hits Gemma 4 26B-A4B 8-bit on first generate via `MLXVLM.VLMModelFactory` when `GenerateParameters.repetitionPenalty` is set.

## Summary

```
MLX/ErrorHandler.swift:343: Fatal error:
[broadcast_shapes] Shapes (64) and (80) cannot be broadcast.
at .../mlx-swift/Source/Cmlx/mlx-c/mlx/c/ops.cpp:3952
```

The first shape (`64`) is the `repetitionContextSize`. The second shape (`80`) tracks the rendered prompt length — for a longer system prompt + tool specs + Gemma 4's chat template, the second shape grows accordingly (e.g. `(64) and (1139)` with a ~1K-token prompt).

The same call shape against `mlx-community/Qwen3.6-35B-A3B-8bit` via `LLMModelFactory` runs cleanly — the bug appears to be specific to the Gemma 4 path. The same Gemma 4 weights also generate cleanly under Python `mlx_vlm.chat`, so the safetensors and the Metal kernels are not implicated.

## Repro

Build + run:

```bash
cd Gemma4SwiftRepro
swift package resolve
swift build -c release
# (one-time) copy a precompiled mlx metallib next to the binary if `swift build`
# did not produce one — see "Metal shader compilation" below.
.build/release/Gemma4SwiftRepro
```

`main.swift` selects which experiment runs. Experiment E is the smallest reproducer.

## Experiments

| Experiment | Adds vs. previous                                | Result |
|-----------:|--------------------------------------------------|--------|
| **A**      | bare minimum: `[.user("Say hello.")]`, `GenerateParameters(maxTokens: 32)` | ✅ generates `"Hello! How can I help you today?"` |
| **B**      | + ~1.5K-char system prompt                       | ✅ generates a tool-call-shaped reply |
| **C**      | + `UserInput(chat:tools:)` with two tool specs   | ✅ generates Gemma 4 native tool-call format; `prompt=1076 tokens` |
| **D**      | + full `repetitionPenalty: 1.1, repetitionContextSize: 64, temperature: 0.7, topP: 0.95, maxTokens: 4096` | ❌ `broadcast_shapes Shapes (64) and (1139) cannot be broadcast` |
| **E**      | bisect: A + only `repetitionPenalty: 1.1, repetitionContextSize: 64` (no system prompt, no tools, no temp/top-p/maxTokens changes) | ❌ `broadcast_shapes Shapes (64) and (80) cannot be broadcast` |

A→C all pass. D crashes. E confirms the trigger is `repetitionPenalty` alone — independent of system prompt length, tool specs, or sampling parameters.

## Suspected location

`Libraries/MLXLMCommon/Evaluate.swift` — `RepetitionContext.process(logits:)`:

```swift
public func process(logits: MLXArray) -> MLXArray {
    guard let indices = ring.validTokens?.asType(.uint32) else { return logits }
    var selectedLogits = logits[0..., indices]

    selectedLogits = MLX.where(
        selectedLogits .< 0, selectedLogits * repetitionPenalty,
        selectedLogits / repetitionPenalty)

    logits[0..., indices] = selectedLogits
    return logits
}
```

The Gemma 4 path appears to feed `logits` with a different leading dimension than other architectures, which makes the `logits[0..., indices]` indexing or the subsequent assignment fail to broadcast. (Did not investigate `MLXVLM/Models/Gemma4.swift` past the obvious — left for the maintainers.)

## Cross-substrate verification

The same on-disk Gemma 4 8-bit weights generate cleanly under `mlx_vlm.chat` (Python) — so the safetensors files, tokenizer, and chat template are all good, and the bug is in the Swift port specifically.

## Hardware

- MacBook Pro
- Apple M5 Pro (18 cores: 6 performance + 12 efficiency)
- 64 GB unified memory

## Software

- macOS 26.4.1 (build 25E253)
- Xcode 26.4.1 (build 17E202)
- Swift tools-version 6.1

## Versions

From `Package.resolved` (matches the target host project's resolution exactly):

| Package | Version | Revision |
|---|---|---|
| `mlx-swift-lm` | 3.31.3 | `1c05248bb0899e2a7a4962b84d319cf12f4e12aa` |
| `mlx-swift` | 0.31.3 | `61b9e011e09a62b489f6bd647958f1555bdf2896` |
| `swift-transformers` | 1.3.0 | `b38443e44d93eca770f2eb68e2a4d0fa100f9aa2` |

## Model

- Repo: `mlx-community/gemma-4-26b-a4b-it-8bit`
- Snapshot hash: `1382fb7268fa62c07b83ffa174ff6fa455fb0686`
- 26 GB on disk; 6-shard safetensors

```
chat_template.jinja
config.json
generation_config.json
model-00001-of-00006.safetensors  →  ../../blobs/8d5dc882…
model-00002-of-00006.safetensors  →  ../../blobs/b4d5cd40…
model-00003-of-00006.safetensors  →  ../../blobs/c1c67a52…
model-00004-of-00006.safetensors  →  ../../blobs/213a2f11…
model-00005-of-00006.safetensors  →  ../../blobs/da752d9c…
model-00006-of-00006.safetensors  →  ../../blobs/db5fef26…
model.safetensors.index.json
processor_config.json
tokenizer_config.json
tokenizer.json
```

## Metal shader compilation

`swift build` from the CLI does not produce the `mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib` that the runtime needs — that's an Xcode-build-system step. Two options:

1. Open `Package.swift` in Xcode (`xed .`) and build the executable target there.
2. Copy `mlx-swift_Cmlx.bundle/` from any Xcode-built host project's `Build/Products/{Debug|Release}/` into `.build/release/` next to the executable. The runtime's bundle search picks it up.

The reproducer above used option 2.
