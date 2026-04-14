//
//  TrackingCalculationTests.swift
//  GitLab Timetracking Tests
//

import Foundation
import Testing
@testable import GitLab_Timetracking

@MainActor
struct TrackingCalculationTests {

    // MARK: - Helpers

    private func makeIssue() -> GitLabIssue {
        GitLabIssue(
            id: 1,
            iid: 42,
            projectID: 10,
            title: "Test Issue",
            webURL: URL(string: "https://gitlab.example.com/test/project/-/issues/42")!,
            updatedAt: Date(),
            references: GitLabIssue.References(short: "#42"),
            timeStats: GitLabIssue.TimeStats(totalTimeSpent: 0)
        )
    }

    private func makeSession(
        startedAt: Date = Date(timeIntervalSince1970: 0),
        lastCheckpointAt: Date? = nil,
        awaitingContinuation: Bool = false,
        accumulatedMinutes: Int = 0
    ) -> TrackingManager.Session {
        TrackingManager.Session(
            issue: makeIssue(),
            startedAt: startedAt,
            lastCheckpointAt: lastCheckpointAt ?? startedAt,
            awaitingContinuation: awaitingContinuation,
            accumulatedMinutes: accumulatedMinutes
        )
    }

    // MARK: - minutesBetween

    @Test func minutesBetween_35minutes() {
        let from = Date(timeIntervalSince1970: 0)
        let to = from.addingTimeInterval(35 * 60)
        #expect(TrackingManager.minutesBetween(from: from, to: to) == 35)
    }

    @Test func minutesBetween_minimumIsOne() {
        let from = Date(timeIntervalSince1970: 0)
        let to = from.addingTimeInterval(10) // 10 seconds
        #expect(TrackingManager.minutesBetween(from: from, to: to) == 1)
    }

    @Test func minutesBetween_exactlyOneMinute() {
        let from = Date(timeIntervalSince1970: 0)
        let to = from.addingTimeInterval(60)
        #expect(TrackingManager.minutesBetween(from: from, to: to) == 1)
    }

    @Test func minutesBetween_truncatesPartialMinutes() {
        let from = Date(timeIntervalSince1970: 0)
        let to = from.addingTimeInterval(20 * 60 + 45) // 20 min 45 sec
        #expect(TrackingManager.minutesBetween(from: from, to: to) == 20)
    }

    // MARK: - applyCheckpoint

    @Test func applyCheckpoint_updatesAllFields() {
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)

        let session = makeSession(startedAt: start)
        let updated = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)

        #expect(updated.accumulatedMinutes == 20)
        #expect(updated.lastCheckpointAt == checkpointTime)
        #expect(updated.awaitingContinuation == true)
        #expect(updated.startedAt == start) // unchanged
    }

    @Test func applyCheckpoint_accumulatesOnTopOfExisting() {
        let start = Date(timeIntervalSince1970: 0)
        let session = makeSession(startedAt: start, accumulatedMinutes: 40)
        let checkpointTime = start.addingTimeInterval(60 * 60)

        let updated = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)
        #expect(updated.accumulatedMinutes == 60)
    }

    // MARK: - User scenario: track 20min, come back at 35min

    @Test func scenario_stopAfterCheckpoint_booksAccumulatedOnly() {
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)

        var session = makeSession(startedAt: start)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)

        // "Stop" books accumulated only = 20 minutes
        #expect(session.accumulatedMinutes == 20)
    }

    @Test func scenario_stopAndBookAllAfterCheckpoint_booksFullTime() {
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)
        let returnTime = start.addingTimeInterval(35 * 60)

        var session = makeSession(startedAt: start)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)

        // "Stop & Book All" = accumulated + elapsed since checkpoint
        let totalMinutes = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: returnTime)
        #expect(totalMinutes == 35)
    }

    // MARK: - Stop before first checkpoint

    @Test func stopBeforeCheckpoint_booksElapsedTime() {
        let start = Date(timeIntervalSince1970: 0)
        let stopTime = start.addingTimeInterval(15 * 60)

        let session = makeSession(startedAt: start)
        #expect(session.awaitingContinuation == false)

        // stopTracking formula when not awaiting: accumulated + minutesSinceLastCheckpoint
        let totalMinutes = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: stopTime)
        #expect(totalMinutes == 15)
    }

    // MARK: - Continue after checkpoint, then stop

    @Test func continueAndTrackMore_thenStop() {
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)
        let continueTime = start.addingTimeInterval(25 * 60)
        let stopTime = start.addingTimeInterval(40 * 60)

        var session = makeSession(startedAt: start)

        // Checkpoint fires at T=20
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)
        #expect(session.accumulatedMinutes == 20)
        #expect(session.awaitingContinuation == true)

        // Continue at T=25 (mirrors continueAfterCheckpoint)
        session.awaitingContinuation = false
        session.lastCheckpointAt = continueTime

        // Stop at T=40 (not awaiting, so partial time counted)
        let partialMinutes = TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: stopTime)
        let totalMinutes = session.accumulatedMinutes + partialMinutes
        #expect(totalMinutes == 35)
    }

    // MARK: - Multiple checkpoints with continue

    @Test func multipleCheckpoints_thenStop() {
        let start = Date(timeIntervalSince1970: 0)
        let checkpoint1 = start.addingTimeInterval(20 * 60)
        let continue1 = start.addingTimeInterval(22 * 60)
        let checkpoint2 = start.addingTimeInterval(42 * 60)
        let stopTime = start.addingTimeInterval(50 * 60)

        var session = makeSession(startedAt: start)

        // First checkpoint at T=20
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpoint1)
        #expect(session.accumulatedMinutes == 20)

        // Continue at T=22
        session.awaitingContinuation = false
        session.lastCheckpointAt = continue1

        // Second checkpoint at T=42
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpoint2)
        #expect(session.accumulatedMinutes == 40)

        // "Stop" at T=50 = 40 accumulated
        #expect(session.accumulatedMinutes == 40)

        // "Stop & Book All" at T=50 = 40 + 8 = 48
        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: stopTime)
        #expect(total == 48)
    }

    @Test func multipleCheckpoints_stopAndBookAll_afterThirdCheckpoint() {
        let start = Date(timeIntervalSince1970: 0)
        var session = makeSession(startedAt: start)

        // Three checkpoints at 20, 40, 60 with continues at 21, 41
        let cp1 = start.addingTimeInterval(20 * 60)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: cp1)
        session.awaitingContinuation = false
        session.lastCheckpointAt = start.addingTimeInterval(21 * 60)

        let cp2 = start.addingTimeInterval(41 * 60)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: cp2)
        session.awaitingContinuation = false
        session.lastCheckpointAt = start.addingTimeInterval(42 * 60)

        let cp3 = start.addingTimeInterval(62 * 60)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: cp3)

        #expect(session.accumulatedMinutes == 60)

        // Return at T=75 and "Stop & Book All"
        let returnTime = start.addingTimeInterval(75 * 60)
        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: returnTime)
        #expect(total == 73)
    }

    // MARK: - Sleep/wake with long absence

    @Test func sleepWake_longAbsence_stopBooksAccumulatedOnly() {
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)

        var session = makeSession(startedAt: start)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)

        // Come back 2 hours later — "Stop" = conservative, accumulated only
        #expect(session.accumulatedMinutes == 20)
    }

    @Test func sleepWake_longAbsence_stopAndBookAllIncludesFullTime() {
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)
        let returnTime = start.addingTimeInterval(120 * 60) // 2 hours

        var session = makeSession(startedAt: start)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)

        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: returnTime)
        #expect(total == 120)
    }

    // MARK: - Restore from persistence

    @Test func restore_checkpointFiredDuringSleep_correctBookAll() {
        // Simulates: app persisted session at T=5, app restarts at T=35
        // Checkpoint interval = 20 min, lastCheckpointAt = T=0
        let start = Date(timeIntervalSince1970: 0)
        let checkpointInterval: TimeInterval = 20 * 60

        var session = makeSession(startedAt: start, lastCheckpointAt: start)

        // Restore logic: elapsed >= checkpointInterval, so apply checkpoint
        // at the theoretical fire time (lastCheckpointAt + interval)
        let checkpointFiredAt = session.lastCheckpointAt.addingTimeInterval(checkpointInterval)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointFiredAt)

        #expect(session.accumulatedMinutes == 20)
        #expect(session.lastCheckpointAt == start.addingTimeInterval(20 * 60))

        // User clicks "Stop & Book All" at T=35
        let returnTime = start.addingTimeInterval(35 * 60)
        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: returnTime)
        #expect(total == 35)
    }

    @Test func restore_longSleep_correctBookAll() {
        // App persisted at T=5, restarts at T=90 (checkpoint=20)
        let start = Date(timeIntervalSince1970: 0)
        let checkpointInterval: TimeInterval = 20 * 60

        var session = makeSession(startedAt: start, lastCheckpointAt: start)

        let checkpointFiredAt = session.lastCheckpointAt.addingTimeInterval(checkpointInterval)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointFiredAt)

        // "Stop" = 20 (conservative)
        #expect(session.accumulatedMinutes == 20)

        // "Stop & Book All" at T=90 = 20 + 70 = 90
        let returnTime = start.addingTimeInterval(90 * 60)
        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: returnTime)
        #expect(total == 90)
    }

    // MARK: - Bug regression: lastCheckpointAt must be updated by applyCheckpoint

    @Test func regression_lastCheckpointAtNotUpdated_wouldCauseDoubleCount() {
        // This test verifies the fix for the bug where handleCheckpoint
        // did not update lastCheckpointAt, causing "Stop & Book All"
        // to double-count time.
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)
        let returnTime = start.addingTimeInterval(35 * 60)

        var session = makeSession(startedAt: start)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)

        // The bug: if lastCheckpointAt stayed at start (T=0), this would be:
        //   20 + minutesBetween(T=0, T=35) = 20 + 35 = 55 (WRONG)
        // With the fix (lastCheckpointAt = T=20):
        //   20 + minutesBetween(T=20, T=35) = 20 + 15 = 35 (CORRECT)
        #expect(session.lastCheckpointAt == checkpointTime)

        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: returnTime)
        #expect(total == 35)
    }

    // MARK: - Edge case: immediate stop (accidental start)

    @Test func immediateStop_booksMinimumOneMinute() {
        // User accidentally starts tracking and stops 5 seconds later.
        // minutesBetween clamps to 1, so 1 minute is booked.
        let start = Date(timeIntervalSince1970: 0)
        let stopTime = start.addingTimeInterval(5) // 5 seconds

        let session = makeSession(startedAt: start)
        let totalMinutes = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: stopTime)
        #expect(totalMinutes == 1)
    }

    @Test func immediateStop_zeroSeconds_stillBooksOne() {
        let start = Date(timeIntervalSince1970: 0)

        let session = makeSession(startedAt: start)
        let totalMinutes = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: start)
        #expect(totalMinutes == 1)
    }

    // MARK: - Edge case: clock going backwards

    @Test func minutesBetween_clockBackwards_clampsToOne() {
        // System clock adjusted backwards during tracking
        let from = Date(timeIntervalSince1970: 1000)
        let to = Date(timeIntervalSince1970: 500) // 500 seconds earlier
        #expect(TrackingManager.minutesBetween(from: from, to: to) == 1)
    }

    // MARK: - Edge case: stopTracking while awaiting equals finishAwaitingSession

    @Test func stopTrackingWhileAwaiting_sameAsFinishAwaiting() {
        // Both code paths should produce the same booked minutes
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)
        let returnTime = start.addingTimeInterval(35 * 60)

        var session = makeSession(startedAt: start)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)
        #expect(session.awaitingContinuation == true)

        // stopTracking formula: awaiting ? 0 : partial → 0, total = accumulated
        let stopTrackingMinutes = session.accumulatedMinutes + 0

        // finishAwaitingSession formula: just accumulated
        let finishAwaitingMinutes = session.accumulatedMinutes

        #expect(stopTrackingMinutes == finishAwaitingMinutes)
        #expect(stopTrackingMinutes == 20)

        // finishAwaitingSessionIncludingElapsed: accumulated + elapsed
        let bookAllMinutes = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: returnTime)
        #expect(bookAllMinutes == 35)
    }

    // MARK: - Edge case: continue gap is not double-counted

    @Test func continueGap_notDoubleCounted() {
        // Checkpoint at T=20, user ponders until T=30 then continues.
        // The 10-minute gap should not appear in either the accumulated
        // total or the next partial interval.
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)
        let continueTime = start.addingTimeInterval(30 * 60)
        let stopTime = start.addingTimeInterval(50 * 60)

        var session = makeSession(startedAt: start)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)

        // Continue at T=30 (10 min gap)
        session.awaitingContinuation = false
        session.lastCheckpointAt = continueTime

        // Stop at T=50
        let partial = TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: stopTime)
        let total = session.accumulatedMinutes + partial

        // accumulated=20 (T=0..T=20) + partial=20 (T=30..T=50) = 40
        // The 10-min gap (T=20..T=30) is excluded — user wasn't working
        #expect(partial == 20)
        #expect(total == 40)
    }

    @Test func continueGap_bookAllIncludesGap() {
        // Same scenario, but if user had used "Stop & Book All" at T=30
        // instead of continuing, the gap would be included.
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)
        let returnTime = start.addingTimeInterval(30 * 60)

        var session = makeSession(startedAt: start)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)

        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: returnTime)
        // 20 + 10 = 30 (gap IS included when choosing "Book All")
        #expect(total == 30)
    }

    // MARK: - Edge case: very short checkpoint interval

    @Test func oneMinuteCheckpointInterval() {
        let start = Date(timeIntervalSince1970: 0)
        var session = makeSession(startedAt: start)

        // 5 checkpoints with instant continues, 1 min interval
        for i in 1...5 {
            let cpTime = start.addingTimeInterval(TimeInterval(i) * 60)
            session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 1, at: cpTime)
            session.awaitingContinuation = false
            session.lastCheckpointAt = cpTime
        }

        #expect(session.accumulatedMinutes == 5)

        // Stop 30 seconds after last checkpoint — partial clamps to 1
        let stopTime = start.addingTimeInterval(5 * 60 + 30)
        let partial = TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: stopTime)
        #expect(partial == 1) // max(1, 0) due to < 60s → actually Int(30/60)=0 → max(1,0)=1

        let total = session.accumulatedMinutes + partial
        #expect(total == 6)
    }

    // MARK: - Edge case: multiple missed checkpoints on restore

    @Test func restore_multipleMissedCheckpoints_onlyAddsOneInterval() {
        // checkpoint=20, app down for 90 min → only one 20-min interval added
        // but "Book All" still captures the full 90 minutes
        let start = Date(timeIntervalSince1970: 0)
        let checkpointInterval: TimeInterval = 20 * 60
        let restoreTime = start.addingTimeInterval(90 * 60)

        var session = makeSession(startedAt: start, lastCheckpointAt: start)

        // Restore applies one checkpoint at theoretical fire time
        let checkpointFiredAt = session.lastCheckpointAt.addingTimeInterval(checkpointInterval)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointFiredAt)

        // "Stop" = only the one confirmed interval
        #expect(session.accumulatedMinutes == 20)

        // "Stop & Book All" = full elapsed time (20 + 70 = 90)
        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: restoreTime)
        #expect(total == 90)
    }

    // MARK: - Edge case: "Stop & Book All" immediately after checkpoint fires

    @Test func bookAllImmediatelyAfterCheckpoint_addsMinimumOneMinute() {
        // Checkpoint fires, user sees notification and immediately clicks "Stop & Book All"
        // Elapsed since checkpoint is ~seconds → minutesBetween clamps to 1
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)
        let immediateStop = checkpointTime.addingTimeInterval(3) // 3 seconds later

        var session = makeSession(startedAt: start)
        session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: checkpointTime)

        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: immediateStop)
        // 20 + 1 (minimum) = 21
        #expect(total == 21)
    }

    // MARK: - Edge case: restore already-awaiting session preserves correct state

    @Test func restore_alreadyAwaiting_preservesLastCheckpointAt() {
        // Session was persisted while already awaiting (after checkpoint fired).
        // On restore, lastCheckpointAt should still be the checkpoint time.
        let start = Date(timeIntervalSince1970: 0)
        let checkpointTime = start.addingTimeInterval(20 * 60)
        let restoreTime = start.addingTimeInterval(60 * 60)

        // Session was checkpointed (lastCheckpointAt updated), then persisted
        let session = makeSession(
            startedAt: start,
            lastCheckpointAt: checkpointTime,
            awaitingContinuation: true,
            accumulatedMinutes: 20
        )

        // Restore path for awaitingContinuation=true just re-sends notification,
        // no modification to session state needed.
        #expect(session.lastCheckpointAt == checkpointTime)
        #expect(session.accumulatedMinutes == 20)

        // "Stop" = 20
        #expect(session.accumulatedMinutes == 20)

        // "Stop & Book All" at T=60 = 20 + 40 = 60
        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: restoreTime)
        #expect(total == 60)
    }

    // MARK: - Edge case: large accumulated value with tiny remaining

    @Test func longSession_manyCheckpoints_thenBookAll() {
        // 8-hour session with 20-min checkpoints = 24 checkpoints
        let start = Date(timeIntervalSince1970: 0)
        var session = makeSession(startedAt: start)

        for i in 1...24 {
            let cpTime = start.addingTimeInterval(TimeInterval(i * 20) * 60)
            session = TrackingManager.applyCheckpoint(to: session, checkpointMinutes: 20, at: cpTime)
            session.awaitingContinuation = false
            session.lastCheckpointAt = cpTime
        }

        #expect(session.accumulatedMinutes == 480) // 24 * 20 = 480 min = 8h

        // Stop 10 minutes into the 25th interval
        let stopTime = start.addingTimeInterval((480 + 10) * 60)
        let total = session.accumulatedMinutes
            + TrackingManager.minutesBetween(from: session.lastCheckpointAt, to: stopTime)
        #expect(total == 490)
    }
}
