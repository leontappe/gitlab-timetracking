//
//  DurationFormatter.swift
//  My GitLab Timetracking
//

import Foundation

enum DurationFormatter {
    // GitLab conventions, mirroring GitLabTimeNoteParser.
    static let hoursPerDay = 8
    static let daysPerWeek = 5
    private static let minutesPerHour = 60
    private static var minutesPerDay: Int { hoursPerDay * minutesPerHour }
    private static var minutesPerWeek: Int { daysPerWeek * minutesPerDay }

    static func format(minutes: Int) -> String {
        let total = max(0, minutes)
        guard total > 0 else { return "0m" }

        var remaining = total
        var parts: [String] = []

        let weeks = remaining / minutesPerWeek
        remaining %= minutesPerWeek
        if weeks > 0 { parts.append("\(weeks)w") }

        let days = remaining / minutesPerDay
        remaining %= minutesPerDay
        if days > 0 { parts.append("\(days)d") }

        let hours = remaining / minutesPerHour
        remaining %= minutesPerHour
        if hours > 0 { parts.append("\(hours)h") }

        if remaining > 0 { parts.append("\(remaining)m") }

        return parts.joined(separator: " ")
    }

    static func format(seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 600 {
            let minutes = total / 60
            let remainingSeconds = total % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
        return format(minutes: total / 60)
    }
}
