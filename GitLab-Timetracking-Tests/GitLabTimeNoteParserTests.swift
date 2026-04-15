//
//  GitLabTimeNoteParserTests.swift
//  GitLab Timetracking Tests
//

import Foundation
import Testing
@testable import GitLab_Timetracking

struct GitLabTimeNoteParserTests {
    @Test func addsMinutesFromBasicMinutes() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "added 30m of time spent") == 30)
    }

    @Test func addsMinutesFromHours() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "added 2h of time spent") == 120)
    }

    @Test func addsMinutesFromHoursAndMinutes() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "added 1h 30m of time spent") == 90)
    }

    @Test func addsMinutesFromDaysUsesEightHourDay() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "added 1d of time spent") == 480)
    }

    @Test func addsMinutesFromWeeksUsesFiveDayWeek() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "added 1w of time spent") == 2400)
    }

    @Test func toleratesDateSuffix() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "added 15m of time spent at 2024-01-15") == 15)
    }

    @Test func ignoresSecondsInsideDuration() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "added 1h 30s of time spent") == 60)
    }

    @Test func returnsNilForSubtractions() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "subtracted 30m of time spent") == nil)
    }

    @Test func returnsNilForUnrelatedNote() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "changed title from **x** to **y**") == nil)
    }

    @Test func returnsNilForEmptyDuration() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "added  of time spent") == nil)
    }

    @Test func combinesMixedUnits() {
        #expect(GitLabTimeNoteParser.addedMinutes(from: "added 1d 2h 15m of time spent") == 480 + 120 + 15)
    }
}
