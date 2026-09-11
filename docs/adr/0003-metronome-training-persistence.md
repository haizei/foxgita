# Persist tempo-ramp plans and results as dedicated Schema V18 models

Tempo-ramp configuration and outcomes have a lifecycle distinct from both a daily `PracticeItem` and the legacy `PracticeSession`. Schema V18 will therefore add a per-PracticeItem `TempoRampPlan` and append-only `MetronomeTrainingSession` summaries rather than adding ramp fields to those existing models. A validated plan is saved when training starts; raw TAP timestamps are never persisted; an unfinished running result is closed as `interrupted` on the next app launch and audio is not resumed automatically.

**Consequences:** V17 remains immutable and V17 → V18 requires a migration test. The repository owns ID-based cleanup when a PracticeItem is deleted. Target hold does not create a second result, and drafts that never start do not overwrite the saved plan.
