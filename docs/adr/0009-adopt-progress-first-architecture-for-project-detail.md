# Adopt Progress-First Architecture for Project Detail and Evidence

Project detail adopts the "Progress First" architecture featuring a qualitative Project Progress Story, Last Practice Evidence with Audio Comparison, Next Practice Focus, and read-only Project Note Projections. We explicitly reject percentage-based completion scoring and rigid curriculum stage gates in favor of evidence-backed qualitative progression derived from logged practice scope. Project notes remain pure read-only projections of underlying practice records to enforce a Single Source of Truth.

## Considered Options

- Phase Roadmap (Direction 02) with percentage bars and strict checklist stages was rejected because music learning is non-linear and arbitrary completion percentages create false friction or gamified guilt.
- Completion Portfolio (Direction 03) focusing only on finished master takes was rejected because learners spend weeks on partial fragments and need to perceive incremental qualitative shifts before reaching a final rendition.
- In-place editing of notes on project detail was rejected because allowing edits in two separate contexts creates dual-write conflicts and data drift; notes must be edited only at their source of truth in the respective PracticeItem.

## Consequences

- Milestones in Project Progress Story are extracted from actual practice scopes (e.g., segment practice → fluent playback → full take) rather than calculated completion percentages.
- Audio Comparison uses the user-confirmed milestone version (falling back to the earliest recorded take) as Audio Benchmark Version A, enabling A/B alternation and timestamped evidence observations.
- Tapping Next Practice Focus strictly routes through Project Practice State Handoff to start or resume today's practice.
- Project notes display as a chronological projection linking directly to original practice records for editing.
