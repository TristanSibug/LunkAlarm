import Foundation

public enum AlarmReconciliation {
    // iOS is authoritative. Never re-schedule an alarm that iOS no longer owns:
    // that could resurrect an alarm the user stopped on the Lock Screen.
    public static func reconcile(_ records: [AlarmRecord], systemIDs: Set<UUID>, stoppedIDs: Set<UUID>, now: Date) -> [AlarmRecord] {
        records.compactMap { original in
            var record = original
            if stoppedIDs.contains(record.id), record.hasTests { record.status = .needsChallenge }
            if record.status == .scheduled && !systemIDs.contains(record.id) {
                record.status = record.target > now ? .notScheduled : (record.hasTests ? .needsChallenge : .notScheduled)
            }
            if !record.hasTests && record.target <= now && !systemIDs.contains(record.id) { return nil }
            return record
        }
    }
}
