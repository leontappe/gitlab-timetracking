//
//  GitLabErrorMessageTests.swift
//  GitLab Timetracking Tests
//

import Foundation
import Testing
@testable import GitLab_Timetracking

struct GitLabErrorMessageTests {
    private func message(_ json: String) -> String? {
        GitLabAPI.readableErrorMessage(from: Data(json.utf8))
    }

    @Test func extractsPerFieldValidationMessage() {
        let result = message(#"{"message":{"title":["is too long (maximum is 255 characters)"]}}"#)
        #expect(result == "title is too long (maximum is 255 characters)")
    }

    @Test func joinsMultipleFieldErrors() {
        let result = message(#"{"message":{"title":["is too long"],"labels":["is invalid"]}}"#)
        #expect(result == "labels is invalid; title is too long")
    }

    @Test func extractsPlainStringMessage() {
        #expect(message(#"{"message":"404 Project Not Found"}"#) == "404 Project Not Found")
    }

    @Test func extractsOAuthErrorDescription() {
        let result = message(#"{"error":"invalid_token","error_description":"Token has expired"}"#)
        #expect(result == "Token has expired")
    }

    @Test func fallsBackToRawBodyForUnknownShape() {
        #expect(message("plain text failure") == "plain text failure")
    }

    @Test func returnsNilForEmptyBody() {
        #expect(GitLabAPI.readableErrorMessage(from: Data()) == nil)
    }
}
