import Foundation

public enum AlarmReconciliation {
    // Preserve challenge ownership when the primary alert was stopped but its
    // pre-scheduled recovery alerts still exist. Ordinary alarms stay one-shot.
    public static func reconcile(_ records: [AlarmRecord], systemIDs: Set<UUID>, stoppedIDs: Set<UUID>, now: Date) -> [AlarmRecord] {
        records.compactMap { original in
            var record = original
            if stoppedIDs.contains(record.id), record.hasTests { record.status = .needsChallenge }
            let existsInSystem = record.nativeAlarmIDs.contains { systemIDs.contains($0) }
            if record.hasTests && record.target <= now && !systemIDs.contains(record.id) {
                record.status = .needsChallenge
            }
            if record.status == .scheduled && !existsInSystem {
                record.status = record.target > now ? .notScheduled : (record.hasTests ? .needsChallenge : .notScheduled)
            }
            if !record.hasTests && record.target <= now && !existsInSystem { return nil }
            return record
        }
    }
}
