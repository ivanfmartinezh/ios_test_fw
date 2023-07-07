// Copyright (c) 2022 Proton Technologies AG
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
import class ProtonCore_DataModel.UserInfo
import class ProtonCore_Networking.AuthCredential
import ProtonCore_TestingToolkit

final class PushNotificationActionsHandlerTests: XCTestCase {
    private var sut: PushNotificationActionsHandler!

    private var mockQueueManager: MockQueueManager!
    private var mockExecuteNotificationAction: MockExecuteNotificationAction!
    private var mockIsNetworkAvailable: Bool!
    private var mockCacheStatusInject: CacheStatusStub!
    private var mockNotificationCenter: NotificationCenter!
    private var mockUserNotificationCenter: UNUserNotificationCenter!

    private var dummyUserManager: UserManager!
    private let dummyMessageId = "dummy_message_id"
    private let dummyUserId = UserID(rawValue: "dummy_user_id")

    override func setUp() {
        super.setUp()
        dummyUserManager = createUserManager(userID: dummyUserId.rawValue)
        sharedServices.get(by: UsersManager.self).add(newUser: dummyUserManager)

        mockQueueManager = MockQueueManager()
        mockExecuteNotificationAction = MockExecuteNotificationAction()
        mockIsNetworkAvailable = true
        mockCacheStatusInject = CacheStatusStub()
        mockNotificationCenter = NotificationCenter()
        mockUserNotificationCenter = UNUserNotificationCenter.current()
        sut = PushNotificationActionsHandler(dependencies: makeDependencies())
    }

    override func tearDown() {
        super.tearDown()
        sharedServices.get(by: UsersManager.self).remove(user: dummyUserManager)

        mockQueueManager = nil
        mockExecuteNotificationAction = nil
        mockIsNetworkAvailable = nil
        mockCacheStatusInject = nil
        mockNotificationCenter = nil

        mockUserNotificationCenter.setNotificationCategories([])
        mockUserNotificationCenter.removeAllDeliveredNotifications()
        mockUserNotificationCenter.removeAllPendingNotificationRequests()
        mockUserNotificationCenter = nil
        sut = nil
    }

    func testRegisterActions_whenAppLockedAndAppKeyEnabled() {
        mockCacheStatusInject.isAppLockedAndAppKeyEnabled = true
        sut.registerActions()

        let expectation = expectation(description: "categories are registered")
        mockUserNotificationCenter.getNotificationCategories { categories in
            XCTAssertTrue(categories.isEmpty)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }

    func testRegisterActions_whenNotAppLockedAndAppKeyEnabled() {
        mockCacheStatusInject.isAppLockedAndAppKeyEnabled = false
        sut.registerActions()

        let expectation = expectation(description: "categories are registered")
        mockUserNotificationCenter.getNotificationCategories { categories in
            XCTAssertTrue(categories.count > 0)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }

    func testIsKnown_whenExpectedActionIsPassed() {
        XCTAssertTrue(sut.isKnown(action: "MARK_AS_READ_ACTION"))
    }

    func testIsKnown_whenUnexpectedActionIsPassed() {
        XCTAssertFalse(sut.isKnown(action: UNNotificationDefaultActionIdentifier))
    }

    func testHandleAction_whenNetworkUnavailable() {
        mockIsNetworkAvailable = false
        let expectation = expectation(description: "completion is called")
        sut.handle(action: PushNotificationAction.archive.rawValue, userId: dummyUserId, messageId: dummyMessageId) {
            XCTAssert(self.mockQueueManager.addTaskWasCalled == true)
            XCTAssert(self.mockExecuteNotificationAction.executionBlock.wasCalled == false)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }

    func testHandleAction_whenNetworkAvailableAndRequestSucceeds() {
        mockIsNetworkAvailable = true
        mockExecuteNotificationAction.result = .success(Void())
        let expectation = expectation(description: "completion is called")
        sut.handle(action: PushNotificationAction.archive.rawValue, userId: dummyUserId, messageId: dummyMessageId) {
            XCTAssert(self.mockQueueManager.addTaskWasCalled == false)
            XCTAssert(self.mockExecuteNotificationAction.executionBlock.wasCalled == true)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }

    func testHandleAction_whenNetworkAvailableAndRequestFails() {
        mockIsNetworkAvailable = true
        mockExecuteNotificationAction.result = .failure(NSError.badResponse())
        let expectation = expectation(description: "completion is called")
        sut.handle(action: PushNotificationAction.archive.rawValue, userId: dummyUserId, messageId: dummyMessageId) {
            XCTAssert(self.mockQueueManager.addTaskWasCalled == true)
            XCTAssert(self.mockExecuteNotificationAction.executionBlock.wasCalled == true)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }

    func testHandleAction_whenUnrecognisedAction() {
        mockIsNetworkAvailable = Bool.random()
        let expectation = expectation(description: "completion is called")
        sut.handle(action: "unexisting action", userId: dummyUserId, messageId: dummyMessageId) {
            XCTAssertFalse(self.mockQueueManager.addTaskWasCalled)
            XCTAssertFalse(self.mockExecuteNotificationAction.executionBlock.wasCalled)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }

    func testRegisterActions_whenActionsAreRegisteredAndAppKeyEnabledReceived_itShouldDeregisterActions() {
        mockCacheStatusInject.isAppLockedAndAppKeyEnabled = false
        sut.registerActions()

        let expectation1 = expectation(description: "categories are registered")
        mockUserNotificationCenter.getNotificationCategories { categories in
            XCTAssertTrue(categories.count > 0)
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 2.0)

        // Security is enabled
        mockCacheStatusInject.isAppLockedAndAppKeyEnabled = true
        mockNotificationCenter.post(name: .appKeyEnabled, object: nil)

        let expectation2 = expectation(description: "categories are unregistered")
        mockUserNotificationCenter.getNotificationCategories { categories in
            XCTAssertTrue(categories.isEmpty)
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testRegisterActions_whenActionsAreNotRegisteredAndAppKeyDisabledReceived_itShouldRegisterActions() {
        mockCacheStatusInject.isAppLockedAndAppKeyEnabled = true
        sut.registerActions()

        let expectation1 = expectation(description: "categories are not registered")
        mockUserNotificationCenter.getNotificationCategories { categories in
            XCTAssertTrue(categories.isEmpty)
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 2.0)

        // Security is disabled
        mockCacheStatusInject.isAppLockedAndAppKeyEnabled = false
        mockNotificationCenter.post(name: .appKeyDisabled, object: nil)

        let expectation2 = expectation(description: "categories are registered")
        mockUserNotificationCenter.getNotificationCategories { categories in
            XCTAssertTrue(categories.count > 0)
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    private func makeDependencies() -> PushNotificationActionsHandler.Dependencies {
        return PushNotificationActionsHandler.Dependencies(
            queue: mockQueueManager,
            actionRequest: mockExecuteNotificationAction,
            isNetworkAvailable: { self.mockIsNetworkAvailable },
            cacheStatusInject: mockCacheStatusInject,
            notificationCenter: mockNotificationCenter,
            userNotificationCenter: mockUserNotificationCenter,
            isNotificationActionsFeatureEnabled: true
        )
    }

    private func createUserManager(userID: String) -> UserManager {
        let apiMock = APIServiceMock()
        let userInfo = UserInfo(
            maxSpace: nil,
            usedSpace: nil,
            language: nil,
            maxUpload: nil,
            role: 0,
            delinquent: nil,
            keys: [],
            userId: userID,
            linkConfirmation: nil,
            credit: nil,
            currency: nil,
            subscribed: nil
        )
        let auth = AuthCredential(
            sessionID: "SessionID_\(userID)",
            accessToken: "",
            refreshToken: "",
            expiration: Date(),
            userName: userID,
            userID: userID,
            privateKey: nil,
            passwordKeySalt: nil
        )
        return UserManager(
            api: apiMock,
            userInfo: userInfo,
            authCredential: auth,
            mailSettings: nil,
            parent: nil
        )
    }
}
