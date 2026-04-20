//
//  DurationFormatterTests.swift
//  GitLab Timetracking Tests
//

import Foundation
import Testing
@testable import GitLab_Timetracking

struct DurationFormatterTests {
    @Test func zeroMinutesRendersAsZeroM() {
        #expect(DurationFormatter.format(minutes: 0) == "0m")
    }

    @Test func negativeMinutesClampToZero() {
        #expect(DurationFormatter.format(minutes: -5) == "0m")
    }

    @Test func subHourRendersAsMinutes() {
        #expect(DurationFormatter.format(minutes: 30) == "30m")
    }

    @Test func wholeHoursOmitZeroMinutes() {
        #expect(DurationFormatter.format(minutes: 60) == "1h")
        #expect(DurationFormatter.format(minutes: 120) == "2h")
    }

    @Test func hoursAndMinutesCombine() {
        #expect(DurationFormatter.format(minutes: 90) == "1h 30m")
        #expect(DurationFormatter.format(minutes: 125) == "2h 5m")
    }

    @Test func eightHoursCollapseToOneDay() {
        #expect(DurationFormatter.format(minutes: 480) == "1d")
    }

    @Test func longSessionRendersAsDaysAndHours() {
        #expect(DurationFormatter.format(minutes: 510) == "1d 30m")
        #expect(DurationFormatter.format(minutes: 570) == "1d 1h 30m")
    }

    @Test func fiveDaysCollapseToOneWeek() {
        #expect(DurationFormatter.format(minutes: 2400) == "1w")
    }

    @Test func fullStackedUnits() {
        // 1w + 2d + 3h + 4m = 2400 + 960 + 180 + 4 = 3544
        #expect(DurationFormatter.format(minutes: 3544) == "1w 2d 3h 4m")
    }

    @Test func subTenMinutesShowsSeconds() {
        #expect(DurationFormatter.format(seconds: 0) == "0m 0s")
        #expect(DurationFormatter.format(seconds: 45) == "0m 45s")
        #expect(DurationFormatter.format(seconds: 125) == "2m 5s")
    }

    @Test func tenMinutesAndAboveDropsSeconds() {
        #expect(DurationFormatter.format(seconds: 600) == "10m")
        #expect(DurationFormatter.format(seconds: 3600) == "1h")
        // 30_600s = 510 min = 1d 30m under GitLab's 8h-day convention
        #expect(DurationFormatter.format(seconds: 30_600) == "1d 30m")
        // 9h = 1d 1h
        #expect(DurationFormatter.format(seconds: 9 * 3600) == "1d 1h")
    }

    @Test func negativeSecondsClampToZero() {
        #expect(DurationFormatter.format(seconds: -10) == "0m 0s")
    }
}
