import Foundation

public enum AlarmReconciliation {
    // Preserve challenge ownership when the primary alert was stopped but its
    // pre-scheduled recovery alerts still exist. Ordinary alarms stay one-shot.
    private static func existsPrimary(_ record: AlarmRecord, _ ids: Set<UUID>) -> Bool { ids.contains(record.id) }
    public static func reconcile(_ records: [AlarmRecord], systemIDs: Set<UUID>, stoppedIDs: Set<UUID>, now: Date, alertingIDs: Set<UUID> = []) -> [AlarmRecord] {
        records.compactMap { original in
            var record = original
            if !record.isEnabled { return record }
            // Migration owns these records until AlarmKit has accepted them.
            if record.requiresSystemMigration { return record }
            if !record.isTimer && !record.hasTests && record.target <= now && !alertingIDs.contains(record.id) {
                if record.days.isEmpty { record.enabled = false }
                else if !existsPrimary(record, systemIDs) { record.status = .notScheduled }
                else { record.target = (try? AlarmRoutine.next(hour: record.clockHour ?? Calendar.current.component(.hour, from: record.target), minute: record.clockMinute ?? Calendar.current.component(.minute, from: record.target), days: record.days, now: now)) ?? record.target }
                return record
            }
            if stoppedIDs.contains(record.id), record.hasTests { record.status = .needsChallenge }
            let existsInSystem = record.nativeAlarmIDs.contains { systemIDs.contains($0) }
            if record.hasTests && record.target <= now && !systemIDs.contains(record.id) {
                record.status = .needsChallenge
            }
            if record.status == .scheduled && !existsInSystem {
                record.status = record.target > now ? .notScheduled : (record.hasTests ? .needsChallenge : .notScheduled)
            }
            if record.isTimer && !record.hasTests && record.target <= now && !existsInSystem { return nil }
            return record
        }
    }
}
