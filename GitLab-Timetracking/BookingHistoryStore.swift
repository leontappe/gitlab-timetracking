//
//  BookingHistoryStore.swift
//  My GitLab Timetracking
//

import Foundation

enum GitLabTimeNoteParser {
    private static let hoursPerDay = 8
    private static let daysPerWeek = 5

    static func addedMinutes(from body: String) -> Int? {
        let prefix = "added "
        let suffix = " of time spent"

        guard body.hasPrefix(prefix), let suffixRange = body.range(of: suffix) else {
            return nil
        }

        let start = body.index(body.startIndex, offsetBy: prefix.count)
        guard start <= suffixRange.lowerBound else { return nil }
        let durationText = body[start..<suffixRange.lowerBound]

        return minutes(fromDuration: String(durationText))
    }

    static func minutes(fromDuration text: String) -> Int? {
        var total = 0
        var buffer = ""
        var anyUnitFound = false

        for char in text {
            if char.isWhitespace {
                continue
            }

            if char.isNumber {
                buffer.append(char)
                continue
            }

            guard let value = Int(buffer) else {
                buffer = ""
                continue
            }

            switch char {
            case "w", "W":
                total += value * daysPerWeek * hoursPerDay * 60
                anyUnitFound = true
            case "d", "D":
                total += value * hoursPerDay * 60
                anyUnitFound = true
            case "h", "H":
                total += value * 60
                anyUnitFound = true
            case "m", "M":
                total += value
                anyUnitFound = true
            case "s", "S":
                anyUnitFound = true
            default:
                break
            }

            buffer = ""
        }

        return anyUnitFound ? total : nil
    }
}

struct BookingHistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let issueID: Int
    let issueReference: String
    let issueTitle: String
    let issueWebURL: URL
    let minutes: Int
    let bookedAt: Date
    var gitLabEventID: Int?
}

struct BookingHistoryStore {
    private let defaults: UserDefaults
    private let key = "tracking.bookingHistory"
    private let maxEntries = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [BookingHistoryEntry] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        return (try? JSONDecoder().decode([BookingHistoryEntry].self, from: data)) ?? []
    }

    func save(_ entries: [BookingHistoryEntry]) {
        let trimmed = Array(entries.suffix(maxEntries))
        guard let data = try? JSONEncoder().encode(trimmed) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func append(_ entry: BookingHistoryEntry) -> [BookingHistoryEntry] {
        var entries = load()
        entries.append(entry)
        save(entries)
        return entries
    }

    func mergeRemote(_ remoteEntries: [BookingHistoryEntry]) -> [BookingHistoryEntry] {
        var entries = load()
        let knownEventIDs = Set(entries.compactMap(\.gitLabEventID))

        for remote in remoteEntries where remote.gitLabEventID != nil {
            guard let eventID = remote.gitLabEventID, !knownEventIDs.contains(eventID) else {
                continue
            }

            if let localIndex = entries.firstIndex(where: { local in
                local.gitLabEventID == nil
                    && local.issueID == remote.issueID
                    && local.minutes == remote.minutes
                    && abs(local.bookedAt.timeIntervalSince(remote.bookedAt)) < 180
            }) {
                entries[localIndex].gitLabEventID = eventID
            } else {
                entries.append(remote)
            }
        }

        entries.sort { $0.bookedAt < $1.bookedAt }
        save(entries)
        return entries
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
