# Split metronome into Speed Sheet and Meter Sheet

Practice detail metronome settings were one scrollable sheet anchored by column tap. Figma PRD splits Speed (Tempo Ruler, 56pt BPM, dedicated title) from Meter/Subdivision (three-column header, accent row, 2×4 grid). We keep **Speed Sheet** and **Meter Sheet** as separate presentation surfaces; Sound Sheet stays separate. Meter and Subdivision share one sheet because they edit the same meter state and share one scroll context in Figma.

**Considered:** (A) four sheets matching every Figma frame — rejected as over-split for shared meter/subdivision state; (C) single sheet — rejected because Speed UX (Ruler) diverges too much from meter editing.

**Consequences:** `MetronomeSheetAnchor.speed` opens `MetronomeSpeedSheet`; `.meter` and `.subdivision` open `MetronomeSettingsSheet` (renamed presentation, same engine). TAP tempo deferred to a follow-up ticket. Tempo Ruler displays 40–160; engine still allows 40–200 via steppers.
