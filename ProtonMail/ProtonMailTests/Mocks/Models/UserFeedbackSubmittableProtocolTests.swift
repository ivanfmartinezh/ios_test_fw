// Copyright (c) 2021 Proton AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Mail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Mail. If not, see https://www.gnu.org/licenses/.

@testable import ProtonMail
import XCTest

private class ViewController: UIViewController, UserFeedbackSubmittableProtocol {}

class UserFeedbackSubmittableProtocolTests: XCTestCase {
    private var mockedService: MockUserFeedbackServiceProtocol!

    override func setUp() {
        super.setUp()

        mockedService = MockUserFeedbackServiceProtocol()

        mockedService.sendStub.bodyIs { _, _, completion in
            completion(nil)
        }
    }

    override func tearDown() {
        mockedService = nil

        super.tearDown()
    }

    func testThatSuccessHandlerIsCalled() {
        let expectation = expectation(description: "successHandler should get called")
        let viewController = ViewController()
        let feedback = UserFeedback(type: "feedback_type", score: 1, text: "feedback")
        viewController.submit(feedback, service: mockedService, successHandler: {
            expectation.fulfill()
        }, failureHandler: nil)
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testThatFailureHandlerIsCalled() {
        mockedService.sendStub.bodyIs { _, _, completion in
            completion(.feedbackTypeIsTooLong)
        }
        let expectation = expectation(description: "failureHandler should get called")
        let viewController = ViewController()
        let feedback = UserFeedback(type: "feedback_type", score: 1, text: "feedback")
        viewController.submit(feedback, service: mockedService, successHandler: {
            XCTFail("Shouldn't get called")
        }, failureHandler: {
            expectation.fulfill()
        })
        waitForExpectations(timeout: 1.0, handler: nil)
    }
}
