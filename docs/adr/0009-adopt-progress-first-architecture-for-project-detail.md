# Adopt Progress-First Architecture for Project Detail and Evidence

Project detail adopts the "Progress First" architecture featuring a qualitative Project Progress Story, Last Practice Evidence with Audio Comparison, Next Practice Focus, and read-only Project Note Projections. We explicitly reject percentage-based completion scoring and rigid curriculum stage gates in favor of evidence-backed qualitative progression derived from logged practice scope. Project notes remain pure read-only projections of underlying practice records to enforce a Single Source of Truth.

## Considered Options

- Phase Roadmap (Direction 02) with percentage bars and strict checklist stages was rejected because music learning is non-linear and arbitrary completion percentages create false friction or gamified guilt.
- Completion Portfolio (Direction 03) focusing only on finished master takes was rejected because learners spend weeks on partial fragments and need to perceive incremental qualitative shifts before reaching a final rendition.
- In-place editing of notes on project detail was rejected because allowing edits in two separate contexts creates dual-write conflicts and data drift; notes must be edited only at their source of truth in the respective PracticeItem.

## Consequences

- Project Progress Story links to effective practice records. Without an explicitly recorded scope, it shows a neutral practice timeline; titles, notes, duration, and recordings do not prove a change in playing ability.
- Audio Comparison can suggest a playable milestone recording or the earliest playable take for A, and a later playable take for B. These are candidates until the user confirms the exact two recordings and the shared fragment. Replacing or losing a recording invalidates that confirmation.
- Manual A/B listening and citations to original notes work without AI analysis. Audio observations require a separate, real analysis workflow and are omitted until one exists.
- Tapping “开始这项练习” from project detail or comparison creates a new practice item for the local day. The record page's separate “继续这次练习” action retains its resume semantics.
- Project notes display as a chronological projection linking directly to original practice records for editing.
