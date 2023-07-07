// Copyright (c) 2022 Proton AG
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

final class FetchMessagesWithResetTests: XCTestCase {
    var sut: FetchMessagesWithReset!

    var mockFetchLatestEventId: MockFetchLatestEventId!
    var mockFetchMessages: MockFetchMessages!
    var mockLocalMessagesService: MockLocalMessageDataService!
    var mockLastUpdatedStore: MockLastUpdatedStore!
    var mockContactProvider: MockContactProvider!
    var mockLabelProvider: MockLabelProviderProtocol!

    private let timeout = 2.0

    override func setUp() {
        super.setUp()
        mockFetchLatestEventId = MockFetchLatestEventId()
        mockFetchMessages = MockFetchMessages()
        mockLocalMessagesService = MockLocalMessageDataService()
        mockLastUpdatedStore = MockLastUpdatedStore()
        mockContactProvider = MockContactProvider(coreDataContextProvider: MockCoreDataContextProvider())
        mockLabelProvider = MockLabelProviderProtocol()

        sut = FetchMessagesWithReset(
            userID: "dummy_user_id",
            dependencies: makeDependencies(
                mockFetchLatestEventId: mockFetchLatestEventId,
                mockFetchMessages: mockFetchMessages,
                mockLocalMessageDataService: mockLocalMessagesService,
                mockLastUpdatedStore: mockLastUpdatedStore,
                mockContactProvider: mockContactProvider,
                mockLabelProvider: mockLabelProvider))

        mockLabelProvider.fetchV4LabelsStub.bodyIs { _, completion in
            completion?(.success(()))
        }
    }

    override func tearDown() {
        super.tearDown()
        mockFetchLatestEventId = nil
        mockFetchMessages = nil
        mockLocalMessagesService = nil
        mockLastUpdatedStore = nil
        mockContactProvider = nil
        mockLabelProvider = nil
    }

    func testExecute_cleaningContacts_whenAllRequestsSucceed() {
        let cleanContact = true
        let expectation = expectation(description: "callback is called")

        let params = FetchMessagesWithReset.Params(
            endTime: 0,
            fetchOnlyUnreadMessages: Bool.random(),
            refetchContacts: cleanContact,
            removeAllDrafts: Bool.random()
        )
        sut.execute(params: params) { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: timeout)
        checkMocksForCleaningContacts(cleanContactIs: cleanContact)
    }

    func testExecute_withoutCleaningContacts_whenAllRequestsSucceed() {
        let cleanContact = false
        let expectation = expectation(description: "callback is called")

        let params = FetchMessagesWithReset.Params(
            endTime: 0,
            fetchOnlyUnreadMessages: Bool.random(),
            refetchContacts: cleanContact,
            removeAllDrafts: Bool.random()
        )
        sut.execute(params: params) { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: timeout)
        checkMocksForCleaningContacts(cleanContactIs: cleanContact)
    }

    func testExecute_removingDrafts_whenAllRequestsSucceed() {
        let removeAllDraft = true
        let expectation = expectation(description: "callback is called")

        let params = FetchMessagesWithReset.Params(
            endTime: 0,
            fetchOnlyUnreadMessages: Bool.random(),
            refetchContacts: Bool.random(),
            removeAllDrafts: removeAllDraft
        )
        sut.execute(params: params) { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: timeout)
        checkMocksForRemoveAllDraft(whenRemoveAllDraftIs: removeAllDraft)
    }

    func testExecute_withoutRemovingDrafts_whenAllRequestsSucceed() {
        let removeAllDraft = false
        let expectation = expectation(description: "callback is called")

        let params = FetchMessagesWithReset.Params(
            endTime: 0,
            fetchOnlyUnreadMessages: Bool.random(),
            refetchContacts: Bool.random(),
            removeAllDrafts: removeAllDraft
        )
        sut.execute(params: params) { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: timeout)
        checkMocksForRemoveAllDraft(whenRemoveAllDraftIs: removeAllDraft)
    }

    func testExecute_whenThereIsNoNewEvent() {
        let expectation = expectation(description: "callback is called")

        let emptyEvent = EventLatestIDResponse()
        mockFetchLatestEventId.result = .success(emptyEvent)

        let params = FetchMessagesWithReset.Params(
            endTime: 0,
            fetchOnlyUnreadMessages: Bool.random(),
            refetchContacts: Bool.random(),
            removeAllDrafts: Bool.random()
        )
        sut.execute(params: params) { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: timeout)

        XCTAssertTrue(mockFetchLatestEventId.callExecutionBlock.wasCalledExactlyOnce)
        XCTAssertFalse(mockFetchMessages.executeWasCalled)

        XCTAssertFalse(mockLocalMessagesService.wasCleanMessageCalled)

        XCTAssertFalse(mockContactProvider.wasCleanUpCalled)
        XCTAssertFalse(mockContactProvider.isFetchContactsCalled)

        XCTAssertEqual(mockLabelProvider.fetchV4LabelsStub.callCounter, 0)

        XCTAssertFalse(mockLastUpdatedStore.removeUpdateTimeExceptUnreadWasCalled)
    }

    func testExecute_whenFetchMessagesFails() {
        let expectation = expectation(description: "callback is called")

        mockFetchMessages.result = .failure(NSError.badResponse())

        let params = FetchMessagesWithReset.Params(
            endTime: 0,
            fetchOnlyUnreadMessages: Bool.random(),
            refetchContacts: Bool.random(),
            removeAllDrafts: Bool.random()
        )
        sut.execute(params: params) { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: timeout)

        XCTAssertTrue(mockFetchLatestEventId.callExecutionBlock.wasCalledExactlyOnce)
        XCTAssertTrue(mockFetchMessages.executeWasCalled)

        XCTAssertFalse(mockLocalMessagesService.wasCleanMessageCalled)

        XCTAssertFalse(mockContactProvider.wasCleanUpCalled)
        XCTAssertFalse(mockContactProvider.isFetchContactsCalled)

        XCTAssertEqual(mockLabelProvider.fetchV4LabelsStub.callCounter, 1)

        XCTAssertFalse(mockLastUpdatedStore.removeUpdateTimeExceptUnreadWasCalled)
    }
}

extension FetchMessagesWithResetTests {
    private func checkMocksForCleaningContacts(cleanContactIs value: Bool) {
        XCTAssertTrue(mockFetchLatestEventId.callExecutionBlock.wasCalledExactlyOnce)
        XCTAssertTrue(mockFetchMessages.executeWasCalled)

        XCTAssertTrue(mockLocalMessagesService.wasCleanMessageCalled)
        XCTAssertFalse(mockLocalMessagesService.cleanBadgeAndNotificationsValue)

        XCTAssert(mockContactProvider.wasCleanUpCalled == value)
        XCTAssert(mockContactProvider.isFetchContactsCalled == value)

        XCTAssertTrue(mockLastUpdatedStore.removeUpdateTimeExceptUnreadWasCalled)
    }

    private func checkMocksForRemoveAllDraft(whenRemoveAllDraftIs value: Bool) {
        XCTAssertTrue(mockFetchLatestEventId.callExecutionBlock.wasCalledExactlyOnce)
        XCTAssertTrue(mockFetchMessages.executeWasCalled)

        XCTAssertTrue(mockLocalMessagesService.wasCleanMessageCalled)
        XCTAssert(mockLocalMessagesService.removeAllDraftValue == value)
        XCTAssertFalse(mockLocalMessagesService.cleanBadgeAndNotificationsValue)

        XCTAssertTrue(mockLastUpdatedStore.removeUpdateTimeExceptUnreadWasCalled)
    }

    private func makeDependencies(
        mockFetchLatestEventId: FetchLatestEventIdUseCase,
        mockFetchMessages: FetchMessagesUseCase,
        mockLocalMessageDataService: LocalMessageDataServiceProtocol,
        mockLastUpdatedStore: LastUpdatedStoreProtocol,
        mockContactProvider: ContactProviderProtocol,
        mockLabelProvider: LabelProviderProtocol
    ) -> FetchMessagesWithReset.Dependencies {
        FetchMessagesWithReset.Dependencies(
            fetchLatestEventId: mockFetchLatestEventId,
            fetchMessages: mockFetchMessages,
            localMessageDataService: mockLocalMessageDataService,
            lastUpdatedStore: mockLastUpdatedStore,
            contactProvider: mockContactProvider,
            labelProvider: mockLabelProvider
        )
    }
}
