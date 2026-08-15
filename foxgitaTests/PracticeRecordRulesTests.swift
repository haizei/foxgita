import Testing
@testable import foxgita

struct PracticeRecordRulesTests {
    @Test func userAddedAcceptsCustomAndActivePrefixes() {
        #expect(PracticeRecordRules.isUserAddedTask(id: "custom-abc"))
        #expect(PracticeRecordRules.isUserAddedTask(id: "active-tpl-chord"))
        #expect(PracticeRecordRules.isUserAddedTask(id: "warm") == false)
        #expect(PracticeRecordRules.isUserAddedTask(id: "chord") == false)
        #expect(PracticeRecordRules.isUserAddedTask(id: "song") == false)
    }

    @Test func effectiveRequiresTimeNoteOrRecording() {
        #expect(
            PracticeRecordRules.isEffective(durationSec: 0, noteText: "", recordingCount: 0) == false
        )
        #expect(PracticeRecordRules.isEffective(durationSec: 60, noteText: "", recordingCount: 0))
        #expect(PracticeRecordRules.isEffective(durationSec: 0, noteText: "  有笔记  ", recordingCount: 0))
        #expect(PracticeRecordRules.isEffective(durationSec: 0, noteText: "   ", recordingCount: 0) == false)
        #expect(PracticeRecordRules.isEffective(durationSec: 0, noteText: "", recordingCount: 1))
    }
}
