//
//  PracticeActiveTaskMerge.swift
//  foxgita
//

import Foundation

/// One-shot migration: fold legacy `active-{templateId}-{dayKey}` rows onto
/// stable `active-{templateId}` ids. Soft-deleted dailies are never undeleted.
enum PracticeActiveTaskMerge {
    static let defaultsKey = "gita.practice.mergedActiveTasks.v1"

    struct Plan: Equatable {
        var canonicalId: String
        var sourceTaskIds: [String]
        var softDeleteTaskIds: [String]
        /// Task ids whose live sessions should be retargeted to `canonicalId`.
        var reassignSessionTaskIds: [String]
    }

    /// Pure: given task id/deletedAt/updatedAt + session counts per taskId.
    static func plans(
        tasks: [(id: String, deletedAt: Date?, updatedAt: Date)],
        effectiveSessionCount: [String: Int]
    ) -> [Plan] {
        var dailiesByTemplate: [String: [(id: String, deletedAt: Date?, updatedAt: Date)]] = [:]
        var taskById: [String: (id: String, deletedAt: Date?, updatedAt: Date)] = [:]

        for task in tasks {
            taskById[task.id] = task
            if let parsed = PracticeTaskOrigin.parseDailyActiveId(task.id) {
                dailiesByTemplate[parsed.templateId, default: []].append(task)
            }
        }

        var result: [Plan] = []
        for (templateId, dailies) in dailiesByTemplate.sorted(by: { $0.key < $1.key }) {
            let stableId = PracticeTaskOrigin.stableActiveId(templateId: templateId)
            let stable = taskById[stableId]
            let liveStable = stable.flatMap { $0.deletedAt == nil ? $0 : nil }
            let liveDailies = dailies.filter { $0.deletedAt == nil }
            let allDailyIds = dailies.map(\.id).sorted()

            if liveStable != nil {
                let softDelete = liveDailies.map(\.id).sorted()
                let reassign = allDailyIds
                if softDelete.isEmpty && reassign.isEmpty { continue }
                // Still emit when only soft-deleted sources need session retarget.
                if softDelete.isEmpty && !reassign.contains(where: { (effectiveSessionCount[$0] ?? 0) > 0 }) {
                    continue
                }
                result.append(
                    Plan(
                        canonicalId: stableId,
                        sourceTaskIds: allDailyIds,
                        softDeleteTaskIds: softDelete,
                        reassignSessionTaskIds: reassign
                    )
                )
                continue
            }

            if stable != nil {
                // Tombstone stable: never undelete / recreate same id.
                continue
            }

            guard !liveDailies.isEmpty else {
                // Tombstone-only dailies: never revive by creating stable.
                continue
            }

            // Winner among live dailies is chosen in apply (max sessions, then updatedAt).
            let softDelete = liveDailies.map(\.id).sorted()
            result.append(
                Plan(
                    canonicalId: stableId,
                    sourceTaskIds: allDailyIds,
                    softDeleteTaskIds: softDelete,
                    reassignSessionTaskIds: allDailyIds
                )
            )
        }
        return result
    }

    /// Gather inputs, plan, and apply. Caller owns the UserDefaults once-gate.
    @MainActor
    static func applyPending(repository: PracticeRepository) throws {
        let collected = try collectTasks(repository: repository)
        let sessions = try repository.sessions()
        let counts = effectiveSessionCounts(from: sessions)
        let planned = plans(tasks: collected, effectiveSessionCount: counts)
        try apply(planned, repository: repository)
    }

    @MainActor
    static func apply(_ plans: [Plan], repository: PracticeRepository) throws {
        let sessions = try repository.sessions()
        let counts = effectiveSessionCounts(from: sessions)

        for plan in plans {
            if try repository.task(id: plan.canonicalId) == nil {
                let liveSources = plan.softDeleteTaskIds.compactMap { id in
                    try? repository.task(id: id)
                }
                guard let winner = liveSources.max(by: { lhs, rhs in
                    let lCount = counts[lhs.id] ?? 0
                    let rCount = counts[rhs.id] ?? 0
                    if lCount != rCount { return lCount < rCount }
                    return lhs.updatedAt < rhs.updatedAt
                }) else {
                    continue
                }
                // Preserve today visibility: max startedOn among live sources.
                let maxStartedOn = liveSources.compactMap(\.startedOn).max()
                let copy = TaskItem(
                    id: plan.canonicalId,
                    title: winner.title,
                    subtitle: winner.subtitle,
                    category: winner.category,
                    targetMin: winner.targetMin,
                    defaultBpm: winner.defaultBpm,
                    timeSig: winner.timeSig,
                    steps: winner.steps,
                    status: winner.status,
                    startedOn: maxStartedOn ?? winner.startedOn,
                    sortOrder: winner.sortOrder,
                    isTemplate: false,
                    profileId: winner.profileId,
                    originKey: winner.originKey
                )
                try repository.add(copy)
            } else if let stable = try repository.task(id: plan.canonicalId) {
                // Live stable already exists: bump startedOn before soft-deleting dailies.
                var startedOns: [Date] = []
                if let existing = stable.startedOn { startedOns.append(existing) }
                for taskId in plan.softDeleteTaskIds {
                    if let daily = try repository.task(id: taskId), let started = daily.startedOn {
                        startedOns.append(started)
                    }
                }
                if let maxStarted = startedOns.max(), maxStarted != stable.startedOn {
                    stable.startedOn = maxStarted
                    stable.touch()
                }
            }

            let reassign = Set(plan.reassignSessionTaskIds)
            for session in sessions where reassign.contains(session.taskId) {
                session.taskId = plan.canonicalId
                session.updatedAt = Date()
            }

            let now = Date()
            for taskId in plan.softDeleteTaskIds {
                guard let task = try repository.task(id: taskId) else { continue }
                task.deletedAt = now
                task.touch(now)
            }
        }
        try repository.save()
    }

    /// Counts only effective sessions (duration / note / recording). Soft-deleted
    /// sessions follow whatever `repository.sessions()` already returns.
    private static func effectiveSessionCounts(from sessions: [PracticeSession]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for session in sessions where session.isEffective {
            counts[session.taskId, default: 0] += 1
        }
        return counts
    }

    @MainActor
    private static func collectTasks(
        repository: PracticeRepository
    ) throws -> [(id: String, deletedAt: Date?, updatedAt: Date)] {
        var byId: [String: (id: String, deletedAt: Date?, updatedAt: Date)] = [:]
        for task in try repository.tasks() {
            byId[task.id] = (task.id, task.deletedAt, task.updatedAt)
        }
        for session in try repository.sessions() {
            if byId[session.taskId] == nil,
               let task = try repository.taskIncludingDeleted(id: session.taskId) {
                byId[task.id] = (task.id, task.deletedAt, task.updatedAt)
            }
        }
        for id in Array(byId.keys) {
            guard let parsed = PracticeTaskOrigin.parseDailyActiveId(id) else { continue }
            let stableId = PracticeTaskOrigin.stableActiveId(templateId: parsed.templateId)
            if byId[stableId] == nil,
               let task = try repository.taskIncludingDeleted(id: stableId) {
                byId[task.id] = (task.id, task.deletedAt, task.updatedAt)
            }
        }
        return Array(byId.values)
    }
}
