# Gita AI Platform Phase 1 Development Design

**Date:** 2026-09-09  
**Status:** Approved design; awaiting written-spec review  
**Scope:** Messages-first shared AI platform, security gates, prompt assembly/caching foundations, and migration of four existing AI flows  
**Source architecture:** [`Gita-AI五层技术架构与三运行时方案.md`](../../../../../1-产品&设计/4-开发相关/Gita-AI五层技术架构与三运行时方案.md)

## 1. Purpose

Build a shared AI platform beneath Gita's existing AI features so session handling, context fetching, fencing, model transport, validation, approval, logging, and prompt-cache instrumentation are implemented once.

Phase 1 uses a Messages-style request/response runtime. Agent SDK and Managed Agents are future runtime choices, not implementation deliverables. The design preserves one narrow `AgentRuntime` boundary so adding another runtime later does not require changing recipes, artifacts, security gates, or feature UI.

The platform-first approach is intentional. To prevent speculative abstraction, every Phase 1 type and module must support at least one of the four existing flows:

- `practice.plan.from_image`
- `practice.review.media`
- `practice.diagnose.video`
- `practice.next_session`

## 2. Goals

- Route all four existing AI flows through one orchestrator and one runtime abstraction.
- Separate domain-neutral execution from Gita practice recipes and rules.
- Produce immutable context snapshots and provenance sets before model execution.
- Enforce input, provenance, presentation, and mutation constraints in code.
- Require preview and host approval before AI-generated drafts change practice data.
- Assemble byte-stable prompt prefixes and measure provider cache behavior.
- Preserve existing feature behavior during migration and remove duplicated clients after parity.
- Keep manual practice, recording, and review flows available when AI fails.

## 3. Non-goals

- Implement Agent SDK or Managed Agents adapters.
- Add autonomous multi-step agent loops.
- Add a general chat surface or a public Extension marketplace.
- Add cloud account, cross-device conversation state, or background durable jobs.
- Add new end-user AI capabilities such as weekly reflection.
- Cache final personalized model answers.
- Replace deterministic practice rules with model judgment.
- Generalize the platform for domains that do not yet exist in Gita.

## 4. Current State

The application already has useful foundations:

- `SkillDefinition` and `SkillRegistry` identify four built-in skills.
- `AITransport` centralizes OpenAI-compatible `/chat/completions` requests and one format retry.
- `AIInvocationStore` records model, skill version, duration, memory references, status, and draft outcome.
- `MemoryContextBuilder` builds a size-limited memory block and records included item IDs.
- Draft generators and feature sheets isolate some presentation logic from transport logic.

The main issue is duplicated orchestration. `NextSessionClient`, `VisionPracticeClient`, `MediaReviewClient`, and `VideoDiagnosisClient` each perform some combination of:

1. skill lookup;
2. URL and credential validation;
3. memory/context assembly;
4. model request;
5. response extraction and JSON decoding;
6. domain normalization;
7. invocation logging;
8. error mapping.

This makes security and behavior inconsistent and makes every new recipe another client implementation.

## 5. Architectural Decision

Use a platform-first modular design with a Messages-only concrete runtime:

```text
Feature UI
   ↓
GitaPracticeExtension
   ↓
AIPlatform contracts and AgentOrchestrator
   ↓
Security pipeline + PromptAssembler
   ↓
MessagesRuntime
   ↓
Provider transport

AgentOrchestrator
   ↓
ToolGateway protocols
   ↓
PracticeStore / MemoryStore / media services
```

The platform owns execution mechanics. The Extension owns practice meaning. Adapters own framework and storage details.

## 6. Dependency Rules

1. `AIPlatform` must not import or reference `PracticeSession`, `PracticeItem`, `Project`, `PracticeCategory`, chords, tempo, or other Gita domain types.
2. `GitaPracticeExtension` may depend on `AIPlatform` protocols and Gita domain models.
3. Feature UI may request a recipe and render a typed presentation model, but may not call a provider client directly.
4. Runtime implementations may depend on networking and provider DTOs, but not on Gita domain models or stores.
5. Security gates run outside the runtime and therefore apply identically to future runtimes.
6. Storage and business mutations are accessed only through narrow gateway protocols.
7. A provider-specific response type must not cross the runtime boundary.

## 7. Proposed Modules

The repository currently groups these concerns under `foxgita/foxgita/Services`. Phase 1 should keep the Xcode target structure stable while organizing new files into focused subdirectories or file groups:

```text
foxgita/foxgita/Services/AIPlatform/
├── Contracts/
│   ├── InteractionRequest.swift
│   ├── RecipeDefinition.swift
│   ├── AgentExecutionPlan.swift
│   ├── RuntimeEvent.swift
│   └── SkillArtifactEnvelope.swift
├── Session/
│   ├── AISession.swift
│   ├── ConversationState.swift
│   └── ApprovalState.swift
├── Core/
│   ├── AgentOrchestrator.swift
│   ├── ExtensionRegistry.swift
│   └── RuntimeRouter.swift
├── Context/
│   ├── ContextFetcher.swift
│   ├── ContextFencer.swift
│   ├── ContextSnapshot.swift
│   └── SeenSet.swift
├── Security/
│   ├── InputGate.swift
│   ├── ProvenanceGate.swift
│   ├── PresentationGate.swift
│   ├── MutationGate.swift
│   └── ApprovalToken.swift
├── Prompt/
│   ├── PromptAssembler.swift
│   ├── PromptFingerprint.swift
│   └── PromptCacheMetrics.swift
├── Runtime/
│   ├── AgentRuntime.swift
│   └── MessagesRuntime.swift
├── Artifact/
│   ├── ArtifactValidator.swift
│   └── ArtifactStore.swift
└── Observability/
    ├── InvocationRecorder.swift
    └── OutcomeTracker.swift

foxgita/foxgita/Services/GitaPracticeExtension/
├── GitaPracticeExtension.swift
├── PracticeRecipeRegistry.swift
├── ContextPolicies/
├── Recipes/
├── Validators/
└── Presenters/
```

Directories describe ownership, not new Swift packages. Package or target extraction is deferred until another consumer proves it useful.

## 8. Core Contracts

All contracts should be value types and conform to `Sendable`; persisted or wire-level types also conform to `Codable`.

### 8.1 InteractionRequest

Represents a user or feature request before a recipe is resolved.

```swift
struct InteractionRequest: Sendable {
    let invocationID: UUID
    let sessionID: UUID?
    let recipeHint: String
    let surface: InteractionSurface
    let input: UserInput
    let selectedResources: [ResourceRef]
    let clientCapabilities: ClientCapabilities
}
```

The feature creates `invocationID` before starting so cancellation and draft outcome remain traceable.

### 8.2 RecipeDefinition

Replaces prompt-heavy `SkillDefinition` with an execution declaration.

```swift
struct RecipeDefinition: Sendable {
    let id: String
    let family: String
    let version: String
    let title: String
    let fetchPolicy: FetchPolicy
    let outputSchema: OutputSchema
    let runtimeRequirements: RuntimeRequirements
    let approvalPolicy: ApprovalPolicy
    let promptTemplate: PromptTemplate
    let timeout: Duration
    let allowsFormatRepair: Bool
}
```

Existing `SkillID` values remain as compatibility identifiers during migration. Renaming them to the target recipe taxonomy is a separate, versioned migration.

### 8.3 ContextSnapshot and SeenSet

```swift
struct ContextSnapshot: Codable, Sendable {
    let id: UUID
    let invocationID: UUID
    let createdAt: Date
    let scope: ResourceScope
    let sections: [ContextSection]
    let selectedResourceRefs: [ResourceRef]
    let warnings: [ContextWarning]
    let revision: String
}

struct SeenSet: Codable, Sendable {
    let snapshotID: UUID
    let projectIDs: Set<String>
    let taskIDs: Set<String>
    let sessionIDs: Set<String>
    let mediaIDs: Set<String>
    let evidenceRefs: Set<EvidenceRef>
    let memoryRefs: Set<String>
}
```

`SeenSet` contains only references returned by authorized fetching for this invocation. It is not reconstructed from model text or conversation summaries.

### 8.4 AgentExecutionPlan

```swift
struct AgentExecutionPlan: Sendable {
    let invocationID: UUID
    let sessionID: UUID
    let recipe: RecipeDefinition
    let contextSnapshot: ContextSnapshot
    let seenSet: SeenSet
    let consentSnapshot: ConsentSnapshot
    let allowedTools: [ToolGrant]
    let budget: ExecutionBudget
    let fallbackPolicy: FallbackPolicy
}
```

Phase 1's plan always resolves to `MessagesRuntime`. The requirements remain explicit to prevent runtime details from leaking into recipes.

### 8.5 SkillArtifactEnvelope

```swift
struct SkillArtifactEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    let id: UUID
    let invocationID: UUID
    let recipeID: String
    let recipeVersion: String
    let generatedAt: Date
    let contextSnapshotID: UUID
    let payload: Payload
    let evidenceRefs: [EvidenceRef]
    let memoryRefs: [String]
    let warnings: [ArtifactWarning]
    let approvalRequirement: ApprovalRequirement
}
```

The original artifact is immutable. User edits create an accepted presentation or business draft associated with the original artifact.

### 8.6 Runtime Contract

```swift
protocol AgentRuntime: Sendable {
    func execute(
        plan: AgentExecutionPlan,
        prompt: PromptAssembly,
        credentials: RuntimeCredentials
    ) -> AsyncThrowingStream<RuntimeEvent, Error>
}
```

Phase 1 events are `accepted`, `started`, `modelDelta`, `artifactProduced`, `completed`, `failed`, and `cancelled`. Tool-loop events exist in the enum only when needed by Messages execution or tests; no autonomous loop is implemented.

## 9. Unified Execution State Machine

```text
created
→ fetching
→ fenced
→ assembling
→ authorizing
→ executing
→ validating
→ presenting
→ awaitingApproval
→ applying
→ completed

from any active state
→ cancelled / failed / expired / superseded
```

The orchestrator is the only component allowed to advance the state. Each transition emits an invocation event.

### 9.1 Execution Sequence

1. The feature submits `InteractionRequest`.
2. `ExtensionRegistry` resolves the exact recipe and version.
3. `ContextFetcher` executes the recipe's `FetchPolicy` through read-only gateways.
4. `ContextFencer` normalizes and partitions untrusted content.
5. The platform freezes `ContextSnapshot`, `SeenSet`, and `ConsentSnapshot`.
6. `PromptAssembler` builds ordered tools, static system, dynamic context, persisted history, and current input.
7. `InputGate` validates scope, consent, payload limits, runtime capability, and budget.
8. `RuntimeRouter` selects `MessagesRuntime`.
9. The runtime executes one structured model request and emits standard events.
10. `ArtifactValidator` decodes schema and runs provenance plus recipe validators.
11. `PresentationGate` validates references and hydrates current display fields from business stores.
12. Read-only artifacts are shown. Mutating artifacts enter `awaitingApproval`.
13. The host UI issues a one-use `ApprovalToken`; `MutationGate` revalidates before applying.
14. `InvocationRecorder` stores execution outcome; `OutcomeTracker` later attaches task start and completion.

## 10. Fetching and Fencing

### 10.1 FetchPolicy

```swift
struct FetchPolicy: Sendable {
    let allowedResourceTypes: Set<ResourceType>
    let allowedScopes: Set<ResourceScope>
    let fieldProjection: [ResourceType: Set<String>]
    let maxItems: [ResourceType: Int]
    let maxCharactersPerItem: Int
    let maxTotalCharacters: Int
    let freshness: FreshnessPolicy
    let includesRawUserContent: Bool
}
```

Feature UI supplies resource references, not model-ready text. The fetcher verifies ownership and converts domain objects into neutral `ContextSection` values.

### 10.2 Fencing Rules

- Normalize external text using Unicode NFKC.
- remove zero-width, bidi, and invalid control characters;
- neutralize forged `system`, `user`, and `assistant` boundaries;
- escape or remove protocol-like tags such as `<tool_use>` and `<system>`;
- apply per-item and total character limits;
- keep trusted facts, confirmed memory, untrusted user material, and media metadata in distinct sections;
- exclude local absolute paths, credentials, and internal database details;
- emit warnings for truncation, filtering, unavailable memory, and removed conflicts.

Fencing must preserve readable user content where possible. It is not a broad profanity or content filter.

## 11. Security Gates

### 11.1 InputGate

Runs before model execution and verifies:

- user/project ownership and current consent;
- selected-media authorization and disclosure;
- context and media limits;
- provider/runtime capabilities;
- recipe budget and timeout.

### 11.2 ProvenanceGate

Validates all model-provided resource and evidence references:

```text
resource ID ∈ SeenSet
evidence reference ∈ ContextSnapshot
media time range ∈ actual media duration
requested field/tool ∈ recipe grant
```

Failure returns a typed `GateRefusal`. It is never converted into a generic retry that omits the gate.

### 11.3 PresentationGate

The model supplies only stable references and explanatory text. The application reloads titles, durations, thumbnails, completion state, and other current facts before rendering. If provenance or hydration fails, the complete referenced card is refused.

### 11.4 MutationGate

All business changes use:

```text
stage → draft ledger → preview → host approve → apply
```

`ApprovalToken` is one-use, short-lived, and bound to user, session, draft ID, and draft hash. Natural-language confirmation does not create a token. Before apply, the gate reloads the affected resources and rejects stale or conflicting drafts.

Phase 1 exposes no direct model tools for deletion, task completion, overwriting goals, or promoting long-term memory.

## 12. Prompt Assembly and Caching

### 12.1 Ordered Prompt Layout

```text
BP1  complete ordered Tool Schema list
BP2  byte-stable static System block
     dynamic context and consent information
     persisted conversation history and large tool results
BP3  latest persisted message, rolling when enabled
     current user input and media
```

Phase 1 implements and tests BP1 and BP2. It calculates `historyPrefixFingerprint` but does not enable BP3 by default until Gita has a persistent long-conversation flow worth caching.

### 12.2 Byte Stability

- Sort tools by stable ID.
- Serialize schemas deterministically.
- Do not include dates, user names, project names, random IDs, or context in the static system block.
- Change `corePromptVersion` or `extensionVersion` whenever corresponding static bytes change.
- Put detailed recipes behind stable versioned definitions rather than mutating the global system string.
- Keep rounded `contextClock`, current page, tasks, memory, and consent in dynamic context.

### 12.3 Cache Instrumentation

Record when available:

```text
toolsetFingerprint
staticPromptFingerprint
historyPrefixFingerprint
contextFingerprint
runtime / provider / model
inputTokens / outputTokens
cacheWriteTokens / cacheReadTokens
```

Provider-side prompt cache does not cache authorization decisions. Scope, ownership, `SeenSet`, business rules, and approval are revalidated on every request.

### 12.4 Media Preprocessing Cache

Keep deterministic media preprocessing separate from provider prompt caching. Suggested key:

```text
mediaDigest
+ samplerVersion
+ framePolicy
+ waveformVersion
+ analyzerVersion
```

Do not persist final personalized model responses as reusable cache entries.

## 13. MessagesRuntime

`MessagesRuntime` absorbs the useful behavior currently in `AITransport` while exposing standard events.

Responsibilities:

- convert `PromptAssembly` into provider request DTOs;
- attach selected image inputs without exposing local paths;
- support a structured-output request when the provider allows it;
- perform at most one format-compatibility retry;
- map network and HTTP failures into neutral runtime errors;
- extract text/content and token/cache usage;
- support cancellation and timeout;
- never decode a Gita-specific artifact.

`AITransport` can initially become an internal dependency of `MessagesRuntime`. Once all clients migrate, either rename it as the provider adapter or remove it if its responsibilities are fully absorbed.

Credentials remain host-owned through `LLMCredentialsStore`. They are passed to the runtime at execution and never stored in plans, snapshots, artifacts, or logs.

## 14. GitaPracticeExtension

The Extension provides four Phase 1 recipe definitions and their domain adapters.

| Existing ID | Phase 1 Recipe Role | Context | Artifact | Approval |
|---|---|---|---|---|
| `practice.next_session` | plan next session | budget, project, confirmed memory | `AIPracticeDraft` envelope | required before task creation |
| `practice.plan.from_image` | plan from selected material | image, project, budget, confirmed memory | `AIPracticeDraft` envelope | required before task creation |
| `practice.review.media` | bounded media observation | selected media, associated session, confirmed memory | `MediaReviewDraft` envelope | none for display; required for memory candidate |
| `practice.diagnose.video` | timestamped video observation | sampled frames, duration, optional waveform | video finding envelope | none for display; required for memory candidate |

### 14.1 Domain Validators

- Practice plan target is clamped to the user budget.
- Step minutes align with steps and do not exceed the total budget.
- Practice categories map to supported `PracticeCategory` values.
- Video ranges are ordered and bounded by actual duration.
- Findings without required evidence are removed or downgraded.
- Media observations do not claim precise pitch or medical conclusions without supported deterministic inputs.
- Candidate memory is staged, never promoted automatically.

Existing pure logic such as `AIPracticeDraft.normalize` and `NextSessionClient.capRaw` should move behind recipe validators before the old client is removed.

## 15. Artifact and Approval Lifecycle

```text
generated
→ validated
→ presented
→ accepted / edited / rejected / regenerated
→ applied, when approval is required
→ expired / superseded
```

Rules:

- Store the original validated artifact before presentation.
- Store the user's final accepted values separately from original model payload.
- `accepted` and `edited` do not mean the resulting task was started.
- Link created tasks to `artifactID` and `invocationID`.
- Continue using `PracticeStore` as the sole source of truth for practice items.
- Mark downstream `started` and `completed` outcomes from actual practice events.
- Cancellation before presentation records `abandoned` only for flows where a draft was expected.

## 16. Persistence and Schema Strategy

Phase 1 extends `AIInvocationLog` rather than creating a full server-style conversation database.

Required invocation fields:

- invocation/session IDs;
- recipe ID and version;
- runtime/provider/model;
- state and typed error/refusal;
- context snapshot ID and referenced memory IDs;
- prompt/context fingerprints;
- token and cache usage when returned;
- format retry and fallback used;
- draft outcome;
- linked artifact and business-object IDs;
- later start/completion timestamps.

Artifact payload persistence should use a versioned encoded envelope plus indexed metadata needed for UI and cleanup. Raw prompts, raw media, API keys, and full provider responses are not persisted.

Any SwiftData schema change follows the repository's existing versioned schema and migration pattern. Deleted memory or media must invalidate pending artifacts and remove corresponding references from future context.

## 17. Error Handling

### 17.1 Error Classes

| Class | Examples | Behavior |
|---|---|---|
| Recoverable | transient timeout, rate limit | retry within budget using same snapshot |
| Degradable | unsupported response format | one compatible-format retry, then manual fallback |
| Security refusal | cross-project ID, missing provenance | no automatic bypass; surface typed refusal |
| Business conflict | resource changed after preview | expire approval and regenerate preview |
| Cancellation | user closes or cancels | stop runtime; never apply pending mutation |

### 17.2 Retry Rules

- Reuse the same immutable `ContextSnapshot` for transport or format retry.
- Never retry a consumed or expired approval token.
- Never relax a gate to make a retry succeed.
- A provider success with an invalid artifact is an invocation failure.
- Logging failure may not block read-only display, but emits a warning; mutation is blocked when required audit state cannot be persisted.

## 18. Migration Strategy

Platform construction precedes feature migration, but migration remains incremental and reversible.

### Stage A: Contracts and State Machine

Add the neutral contracts, orchestrator state transitions, runtime protocol, and test fixtures. Do not change feature behavior.

### Stage B: Fetching, Fencing, and Gates

Implement security modules using stub gateways and adversarial unit tests. Add preview/apply boundaries where existing flows auto-commit.

### Stage C: Prompt and Messages Runtime

Wrap or reuse `AITransport`, implement deterministic prompt assembly, fingerprints, token/cache metrics, and neutral errors.

### Stage D: Artifact and Observability

Add the envelope, validators, artifact persistence, expanded invocation records, and downstream outcome links.

### Stage E: Feature Migration

Recommended migration order:

1. `practice.next_session` — simplest complete draft/approval flow;
2. `practice.plan.from_image` — shares practice draft validators but adds image input;
3. `practice.review.media` — exercises observation and memory-candidate rules;
4. `practice.diagnose.video` — highest media, duration, and provenance complexity.

Each flow uses a feature flag during parity verification. Once all tests and manual parity checks pass, remove the flag and old client implementation for that flow.

### Stage F: Cleanup

Delete duplicated prompt, parsing, logging, credential, and transport code from the four clients. Retain small feature-facing generator protocols only if they remain useful for UI tests; their implementations call the orchestrator.

## 19. Testing Strategy

### 19.1 Unit Tests

- deterministic tool ordering and prompt serialization;
- NFKC, zero-width, bidi, forged-role, and fake-tool-tag fencing;
- fetch scope and field projection;
- `SeenSet` construction;
- all provenance rejection cases;
- approval token binding, expiry, replay, and stale-draft rejection;
- artifact decoding and domain validation;
- runtime routing to Messages;
- error classification and retry budget;
- fingerprint stability and change detection.

### 19.2 Contract Tests

- Extension recipes conform to platform contracts;
- Messages provider requests and responses map to neutral runtime events;
- gateway adapters preserve user/project scope;
- artifact presenters hydrate only current store data;
- no provider DTO or domain store leaks across prohibited boundaries.

### 19.3 Integration Tests

- request → fetch → fence → execute → validate → present;
- draft → preview → approve → apply;
- timeout, cancellation, format retry, and provider failure;
- missing or deleted memory/media invalidates references;
- cache metrics are recorded without changing authorization behavior;
- created practice item links to artifact and later start/completion outcome.

### 19.4 Regression Tests

Port existing client fixtures for all four flows to recipe-level tests. Keep the old tests until each migration reaches parity, then replace transport duplication tests with runtime and recipe contract tests.

### 19.5 Security Tests

- prompt injection embedded in OCR and memory;
- guessed IDs and IDs copied from old sessions;
- cross-project and cross-user references;
- media time ranges outside actual duration;
- natural-language “approve” without host token;
- replayed, expired, or draft-mismatched approval tokens;
- data deletion followed by retry, cache hit, or pending apply.

## 20. Acceptance Criteria

The design is implemented when:

- all four existing features invoke AI through `AgentOrchestrator` and `MessagesRuntime`;
- feature code no longer assembles system prompts or provider request bodies;
- every invocation has an immutable ContextSnapshot and SeenSet;
- all model-provided resource references pass ProvenanceGate;
- display cards hydrate current facts outside the model;
- no AI-generated practice task or memory candidate applies without host approval;
- prompt BP1/BP2 prefixes pass byte-stability tests;
- cache and token usage are recorded when providers expose them;
- AI failure leaves manual practice, recording, and review available;
- old duplicated Client orchestration is removed after parity;
- the full unit, integration, regression, migration, and security suites pass.

## 21. Rollout and Rollback

- Ship the platform with all recipes disabled behind internal feature flags.
- Enable one migrated recipe at a time for development and TestFlight cohorts.
- Compare artifact acceptance, edits, failures, latency, and downstream practice behavior with the legacy path.
- Roll back by switching the recipe flag to the legacy client while preserving new invocation records.
- Do not roll back or delete already approved practice items; they remain normal `PracticeStore` data.
- Remove each legacy path only after its parity window passes and no unresolved security or data migration issue remains.

## 22. Deferred Runtime Extension Points

The following are deliberate contract considerations, not Phase 1 files or tasks:

- `RuntimeRequirements` can later express bounded tool steps and durability.
- `RuntimeEvent` can later add tool-request and approval-pause events.
- `AgentExecutionPlan` carries stable grants and budget independent of provider.
- `ToolGateway` tools are already narrow enough for a future agent loop.

No Agent SDK adapter, Managed Agents adapter, durable job store, queue, callback handler, or cloud session service is created in Phase 1.

## 23. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Platform-first work becomes abstract infrastructure | Require each type to support an existing flow; reject unused extension points |
| Migration changes user-visible output | Preserve existing recipe prompts initially; change behavior only after platform parity |
| Security pipeline adds latency | Keep fetches local and projected; measure each state transition |
| Provider differences break structured output | Maintain one format retry and recipe-level decoding; record capability failures |
| New persistence migration risks user data | Use versioned SwiftData schemas and migration tests before rollout |
| Feature flags leave permanent duplicate paths | Assign deletion criteria to each recipe migration stage |
| Cache optimization encourages stale context | Keep all dynamic data after BP2 and re-run gates on every invocation |

## 24. Documentation Deliverables During Implementation

- Contract reference for recipes, snapshots, gates, artifacts, and runtime events.
- Extension authoring guide limited to internal Gita recipes.
- Security test matrix and gate refusal catalog.
- Prompt assembly and fingerprint debugging guide.
- Migration checklist for each of the four existing flows.
- Provider capability and prompt-cache observation table based on actual tests.

## 25. Final Design Principle

Phase 1 succeeds when Gita has one trustworthy execution path, not when it has the most agent abstractions:

> The host controls identity and side effects; Fetching controls what the model sees; Gates control what it may cite and do; the Extension provides practice meaning; MessagesRuntime remains replaceable.
