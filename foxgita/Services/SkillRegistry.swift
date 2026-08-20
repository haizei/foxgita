import Foundation

struct SkillRegistry: Sendable {
    static let builtin = SkillRegistry(skills: [
        .planFromImage,
        .reviewMedia,
        .diagnoseVideo,
    ])

    private let skills: [String: SkillDefinition]

    init(skills: [SkillDefinition]) {
        var map: [String: SkillDefinition] = [:]
        map.reserveCapacity(skills.count)
        for skill in skills {
            precondition(map[skill.id] == nil, "duplicate skill id \(skill.id)")
            map[skill.id] = skill
        }
        self.skills = map
    }

    func skill(id: String) -> SkillDefinition? {
        skills[id]
    }
}
