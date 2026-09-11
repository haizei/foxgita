# AI Platform verification

## SwiftData test baseline

Unit tests are hosted by `foxgita.app`. During an XCTest run the app must use the
current production schema with an in-memory configuration. Non-migration tests
must also construct the current schema; only `MigrationTests` may construct an
older versioned schema.

The previous crash was caused by mixing a `GitaSchemaV14` test container with
current-model aliases (`MemoryItem` and `LocalProfile`, formerly V17 and now
V18). SwiftData trapped while `SwiftDataMemoryRepository.fetch` attempted to
cast an old-schema instance to the current model type. A second mismatch in the
host app opened a V17 container while its services used V18 aliases.

## Focused verification

Run the AI, Memory, Migration, and Store baseline:

```sh
xcodebuild -quiet -project foxgita.xcodeproj -scheme foxgita \
  -derivedDataPath /private/tmp/gita-ai-focused \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AIInvocationStoreTests \
  -only-testing:foxgitaTests/MemoryStoreTests \
  -only-testing:foxgitaTests/PracticeStoreInvocationTests \
  -only-testing:foxgitaTests/MemoryConsentCoordinatorTests \
  -only-testing:foxgitaTests/TaskMemorySyncTests \
  -only-testing:foxgitaTests/AICandidateSyncTests \
  -only-testing:foxgitaTests/DurationPreferenceSyncTests \
  -only-testing:foxgitaTests/MemoryDebugSeederTests \
  -only-testing:foxgitaTests/MemoryRepositoryTests \
  -only-testing:foxgitaTests/MemoryContextTests \
  -only-testing:foxgitaTests/MigrationTests test
```

## Full verification

```sh
xcodebuild -quiet -project foxgita.xcodeproj -scheme foxgita \
  -derivedDataPath /private/tmp/gita-full \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Existing non-blocking warnings are primarily Swift 6 actor-isolation diagnostics,
captured-variable concurrency diagnostics in URLProtocol test doubles, and an
AVFoundation duration deprecation. They do not cause the SwiftData runner crash,
but should be addressed before enabling Swift 6 language mode.
