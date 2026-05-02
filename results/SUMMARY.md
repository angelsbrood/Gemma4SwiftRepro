# swift-lm-response-parser test results

Tested against `swift-lm-response-parser` 0.1.0 (commit
`d6f2cad458762111e5b73579f4acc29afe530c3c`, the only tag), `mlx-swift-lm` `main`
branch (commit `7e2b7107be52ffbfe488f3c7987d3f52c1858b4b`), on Apple M5 Pro,
64 GB unified memory, macOS 26.4.1, Xcode 26.4.1, Swift tools-version 6.1.

Workloads:
- Gemma 4 26B-A4B 8-bit (`mlx-community/gemma-4-26b-a4b-it-8bit`,
  snapshot `1382fb7268fa62c07b83ffa174ff6fa455fb0686`) — VLMModelFactory
- Qwen 3.6 35B-A3B 8-bit (`mlx-community/Qwen3.6-35B-A3B-8bit`,
  snapshot `e06a74e6236a60c8367e1a3214e83d8b61b637b0`) — LLMModelFactory

All experiments use `repetitionPenalty: nil` to dodge the broadcast crash in
`MLXLMCommon.RepetitionContext.process` reproduced by Experiments D/E (separately
filed at mlx-swift-lm#258).

---

## Question 1: Does the library handle Gemma 4's actual emission format natively?

**Yes.** Experiment G (Gemma 4 single tool call, full system prompt + 2 tool specs,
`results/G-gemma4-single.txt`) — the entire 7-event stream:

```
[3] outputItemAdded(functionCall(id=fc_x2h1dxe5dev422zqg7jwycj3 callId=call_8yp... name=insert_section arguments="" status=inProgress))
[4] functionCallArgumentsDelta(itemId=fc_x2h1dxe5dev422zqg7jwycj3 delta="{\"content\":\"Hello. <!-- @anchor turns=\\"0000\\" -->\",\"heading\":\"Test\"}")
[5] functionCallArgumentsDone(itemId=fc_x2h1dxe5dev422zqg7jwycj3 arguments="{...}")
[6] outputItemDone(functionCall(... status=completed))
[7] responseCompleted(status=.completed, usage=inputTokens:1076 outputTokens:32)
```

The model emitted `<|tool_call>call:insert_section{...}<tool_call|>` (Gemma 4's
actual wire format) and the parser extracted it as a structured `functionCall`
item with the right `name` and a JSON-encoded `arguments` string. This is the
load-bearing test against Threshold's downstream `Gemma4ToolCallDecoder` —
which exists precisely because mlx-swift-lm's in-tree `GemmaFunctionParser`
still ships with the legacy `<start_function_call>...<end_function_call>` tags.

Library: ✓. In-tree mlx-swift-lm `GemmaFunctionParser`: ✗.

---

## Question 2: Does it handle reasoning-channel parsing for both Qwen and Gemma 4?

**Mixed.**

- **Gemma 4** (G + H): The model went straight to a tool call without any
  `<|channel>thought ...<channel|>` reasoning block, so we did not exercise
  reasoning-channel handling on Gemma 4 in this run. Library has dedicated
  `Gemma4ParserTests.swift` (~24 KB) covering the multi-token marker shape.
  Inconclusive empirically; passes in unit tests.

- **Qwen 3.6 35B-A3B** (F, `results/F-qwen.txt`): **No.** Of 256 emitted
  events, zero were `reasoningTextDelta`/`reasoningTextDone`; everything came
  through as `outputTextDelta`. The literal `</think>` token was emitted as
  message content:

  ```
  [235] outputTextDelta(itemId=msg_7a1apg2... text="</think>")
  ```

  Two compounding root causes:

  1. **Wrong format dispatch.** `config.json`'s `model_type` is
     `qwen3_5_moe`. The library's longest-prefix table
     (`Sources/LMResponseParser/Core/ResponseFormat.swift`) has both
     `qwen3_5` → `.qwen3Xml` and `qwen3_moe` → `.qwen`; longest-prefix wins,
     so `.qwen3Xml` is selected. But Qwen 3.6 35B-A3B is a Hermes-style
     thinking MoE — not a Qwen 3.5 Coder. Wrong parser.

  2. **Chat-template `<think>` injection invisible to the parser.** Even
     with the correct `.qwen` dispatch, the parser would have failed:
     Qwen 3.6's `chat_template.jinja` injects `<think>\n` at the assistant
     prefix (verified — the `enable_thinking` Jinja branch). The model
     emits reasoning content and a closing `</think>` but never an opening
     `<think>`. The parser starts in `.normal` mode and never enters
     `.reasoning`. The library's `priorOutput:` hook on `makeParser` exists
     for exactly this case (continuation requests with an unclosed
     reasoning marker), but `ResponseChatSession+PassDriver.swift:57`
     passes no `priorOutput:`.

---

## Question 3: Does the event stream map cleanly onto a tool-use loop's needs?

**Yes** — once tool dispatch is wired correctly. Deriving Threshold's
`(toolUseId, name, input)` triple is direct:

- `toolUseId` ← `outputItemAdded(.functionCall).callId` (`call_…`)
- `name` ← `outputItemAdded(.functionCall).name`
- `input` ← `functionCallArgumentsDone.arguments` (decoded as JSON)

Reasoning vs. content classification reduces to switching on
`reasoningTextDelta/Done` vs. `outputTextDelta/Done`. The 13-case
`ResponseStreamingEvent` enum has clear semantics; nothing extraneous.

The session abstraction
(`ResponseChatSession.streamResponseEvents(prompt:images:videos:config:)`)
wraps everything cleanly — system prompt via `instructions:`, tool specs via
`tools:`, generate parameters via `generateParameters:`. Wired up first try
against `realConciergeSoulPlusIntegratorInstructions` (Threshold's actual
system prompt) plus two `ToolSpec` literals (verbatim from the existing
`ExperimentC.swift`).

Wrinkle: the multi-pass dispatch loop wants a *meaningful* `toolDispatch`
callback. A dummy `.string("OK")` return caused Gemma 4 to enter a degenerate
retry loop, re-emitting the same `insert_section` call across 486+ passes
(see `results/H-gemma4-multi-dispatcher-loop.txt`). Library-correct behavior
— the model couldn't tell its prior call had taken effect — but a real
consumer must return realistic state through the dispatcher.

---

## Question 4: Does the library also handle assistant-history encoding, or only output parsing?

**Output-only.** Resolved by source inspection: no `encode`, `format`,
`render`, or `toMessage` public functions in `Sources/LMResponseParser/`
take a structured `(name, arguments)` and emit the model's wire format.
Threshold's `Gemma4ToolCallEncoder` and `Qwen3ToolCallEncoder` would stay
even after migration.

---

## Bonus: Multi-tool-call handling

Two configurations tested:

- **Single-pass** (no `toolDispatch`, `results/H-gemma4-multi.txt`): The
  model emitted exactly one tool call (`insert_section`) and stopped
  (`status=.completed`, not `.cancelled`). 1 `functionCall` item. Gemma 4
  natively does one-call-per-response — the model does not chain multiple
  `<|tool_call>...<tool_call|>` segments in a single generation.

- **Multi-pass** (dummy `toolDispatch` returning `.string("OK")`,
  `results/H-gemma4-multi-dispatcher-loop.txt`): 486+ tool-call items
  across 486+ passes, all duplicate `insert_section` calls. Killed
  externally after ~3000 events. The dummy "OK" response provided no
  state signal, so the model never advanced to the second tool. Not a
  parser issue.

Net: the parser cleanly extracts one `functionCall` per pass (Experiment G).
True single-response multi-call extraction was not exercisable on
Gemma 4 with our prompts. Library-side `Gemma4ParserTests.swift` covers
synthetic multi-call inputs.

---

## Threshold migration sketch

If Threshold adopted `swift-lm-response-parser`:

- **Retires**: `Gemma4ToolCallDecoder` — replaced directly by parser-emitted
  `functionCall` items (Q1 evidence).
- **Retires**: `ConciergeModel.toolCallFormatOverride` — the bridge dispatches
  internally on `model_type`/`model_config` (or via explicit `format:`).
- **Retires**: per-family parser dispatch in `ConciergeModel.makeParser` —
  `ResponseChatSession`'s built-in dispatch covers it.
- **Retires** (conditional on Q2 issues being addressed):
  `Gemma4ChannelParser`, `ThinkSpanExtractor`. For Gemma 4 the library
  handles the channel format in unit tests; for Qwen 3.6 35B-A3B the
  template-injection gap (Q2 issue 2) means downstream code stays until
  resolved.
- **Stays**: `Gemma4ToolCallEncoder`, `Qwen3ToolCallEncoder` — no encoder
  side in the library (Q4).
- **Stays**: `appendGemma4History` — lives below the parser layer
  (`MLXLMCommon.Chat.Message`'s lack of structured tool-call/response
  fields, orthogonal to this library).

Net reduction conditional on Q2 fixes: ~400 LOC of parsing-side code
becomes maintenance-free downstream. Without Q2 fixes: ~250 LOC retires
(Gemma 4 paths only).

---

## Issues encountered

1. **SPM dependency-graph friction.** `swift-lm-response-parser` 0.1.0's
   `Package.swift` pins `mlx-swift-lm` to `branch: "main"` (unstable-version
   source). SPM rejects mixed stable/unstable graphs for the same package, so
   consumers whose root pins `mlx-swift-lm` stably (e.g. our existing
   `from: "3.31.3"`) hit:
   ```
   swift-lm-response-parser is required using a stable-version but depends on
   an unstable-version package mlx-swift-lm
   ```
   Workaround: pin `swift-lm-response-parser` to its tag commit
   (`revision: "d6f2cad…"`), AND switch our root's `mlx-swift-lm` dep to
   `branch: "main"` to match. This is a real consumption-path defect — most
   downstream apps will hit it. Maintainer-side fix: pin `mlx-swift-lm`
   to a released version inside the parser library's `Package.swift`.

2. **Qwen 3.6 35B-A3B chat-template `<think>` injection unhandled** (Q2,
   issue 2). The `priorOutput:` mechanism on `makeParser` exists for exactly
   this case but isn't invoked from `runOnePass`. Fixable at the bridge
   level: detect chat-template-injected reasoning markers from the rendered
   prompt and forward them as `priorOutput`. Or surface via a
   `ResponseStreamConfig` field so consumers can opt in.

3. **`qwen3_5_moe` model_type wrongly dispatches to `.qwen3Xml`** (Q2,
   issue 1). Longest-prefix-wins picks `qwen3_5` over `qwen3_moe`, but
   Qwen 3.6 35B-A3B is a `qwen3_moe`-shaped model (Hermes-style tool calls
   + `<think>` reasoning), not Qwen 3.5 Coder. Maintainer-side fix: add an
   explicit `qwen3_5_moe` entry to `typePrefixes` pointing to `.qwen`
   (or a new variant if Qwen 3.6's wire format is non-trivially different).

4. **`responseCompleted.response.status` is `.cancelled` when `maxTokens`
   is hit** (F). Naming-wise we'd expect `.incomplete` with
   `incompleteDetails` populated; "cancelled" connotes external
   interruption. Minor; consumers doing UI-side error reporting want to
   differentiate.

5. **Default `processing.resize: CGSize(512x512)` even for text-only LLMs.**
   `ResponseChatSession.init` defaults `processing` for VLM use; text models
   via `LLMModelFactory` ignore it but the default is awkward for non-VLM
   consumers.

---

## Re-test against latest commit (2026-05-02)

Tested against `swift-lm-response-parser` commit
`7ef3a442dca1af3ec0addefbf4beff95f8e5c749` ("Add Qwen 3.6 XML routing and
prompt-boundary reasoning state handling", authored 2026-05-02), following
@DePasqualeOrg's fix for the Qwen 3.6 issues identified above.

Resolved versions: `swift-lm-response-parser` `7ef3a44…`, `mlx-swift-lm`
`3.31.3` (revision `1c05248bb0899e2a7a4962b84d319cf12f4e12aa`, stable). SPM
dep-graph: **resolved cleanly** — Issue 1 of the original report retires.
The parser library's prior commit `a9caec7` ("Pin mlx-swift-lm to version
number") moved its internal pin from `branch:"main"` to `from: "3.31.3"`,
which lets root consumers also pin stably.

### Question 2 (re-test): Reasoning-channel parsing for Qwen 3.6 35B-A3B

**Yes.** Re-running the same Experiment F prompt against the updated library
(`results/F-qwen-rerun.txt`):

- `reasoningDelta` / `reasoningDone` events: **242** (was 0 in original test)
- `</think>` in any `outputTextDelta`: **none** (was 1)
- Final terminal: `responseCompleted(status=.cancelled)` — `usage.outputTokensDetails.reasoningTokens: 242`

The very first content event is now `outputItemAdded(reasoning(id=rs_…))`
rather than `outputItemAdded(message(id=msg_…))`, confirming the parser
now enters reasoning mode at the prompt boundary. All 242 chain-of-thought
deltas land in a `reasoning` item; once the model emits the closing
`</think>` it's consumed cleanly and a fresh `message` item carries the
final-answer phase (events 249–267).

Both Qwen 3.6 issues from the original SUMMARY appear resolved:

- **Issue 3 (model_type dispatch)**: `qwen3_5_moe` now routes to a
  reasoning-aware parser. The fix commit message frames this as "Qwen 3.6
  XML routing"; the result is that `<think>...</think>` reasoning content
  is recognized as such regardless of which dispatch branch handles it.
- **Issue 2 (chat-template `<think>` injection)**: addressed via three new
  files — `Core/DelimitedReasoningBoundary.swift`,
  `Core/ImplicitReasoningPreamble.swift`, `Core/PromptBoundaryPriorText.swift`
  (plus the bridge-side `PromptBoundaryPriorText.swift` and a 14-line wiring
  change in `ResponseChatSession+PassDriver.swift`). Effect: the parser is
  seeded with implied prior reasoning state when the rendered prompt ends
  inside a reasoning marker, so the absence of an opening `<think>` in the
  model's emission no longer prevents reasoning-mode entry.

### Threshold migration sketch (revisited)

Both Q2 fixes landed cleanly, so the conditional language in the original
sketch drops:

- The full ~400 LOC retires cleanly (prior estimate split was ~250 LOC
  unconditional + ~150 LOC contingent on Qwen `<think>` injection being
  addressed). Specifically, `Gemma4ChannelParser` and `ThinkSpanExtractor`
  now both retire under the parser library's coverage.
- `Gemma4ToolCallEncoder`, `Qwen3ToolCallEncoder`, and `appendGemma4History`
  remain in Threshold — Q4 (no encoder side) and the `MLXLMCommon.Chat.Message`
  structural gap are unchanged by this fix.

### API churn note (heads up for consumers)

Bumping past `0.1.0`'s tag commit requires a small consumer-side update.
Two source-breaking changes since the tag:

- `ResponseStreamingEvent.reasoningTextDelta/Done` cases renamed to
  `reasoningDelta/Done`. Same payload shape; cosmetic rename to align with
  Open Responses spec naming.
- A new top-level case `responseIncomplete(ResponseIncompleteEvent)` was
  added (see "Outstanding" below).

Our `ParserSupport.swift:55–58` switch on `ResponseStreamingEvent` was
updated to use the new names and to handle the new case explicitly. With
that one-file change the existing experiments (F here, plus G/H against the
original library) compile against the bumped revision.

### Outstanding from original SUMMARY

- **Issue 4 (`.cancelled` vs `.incomplete` semantics on maxTokens)**: still
  open in this run. The library now defines a `responseIncomplete` event
  case with a documentation comment that explicitly distinguishes vLLM/SGLang
  collapsed semantics from Open Responses' separate discriminator, but our
  maxTokens-hit run still terminates with
  `responseCompleted(status=.cancelled)`. The discriminator-routing for
  maxTokens-induced termination doesn't appear to flip to
  `responseIncomplete` yet. Not part of what this commit was claimed to
  fix; noting status only.
- **Issue 5 (default `processing.resize`)**: not exercised; status
  unchanged.
