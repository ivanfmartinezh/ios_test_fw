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

import Foundation
@testable import ProtonMail
import XCTest

extension MailboxViewModelTests {
    func testFetchConversation() {
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        createSut(labelID: "1245", labelType: .folder, isCustom: false, labelName: nil)

        self.conversationProviderMock.fetchConversationsStub.bodyIs { _, _, _, _, _, completion in
            completion?(.success)
        }

        let expectation1 = expectation(description: "Closure is called")
        sut.fetchMessages(time: 999, forceClean: false, isUnread: false) { _ in
            XCTAssertTrue(self.conversationProviderMock.fetchConversationsStub.wasCalledExactlyOnce)
            do {
                let argument = try XCTUnwrap(self.conversationProviderMock.fetchConversationsStub.lastArguments)
                XCTAssertEqual(argument.first, self.sut.labelID)
                XCTAssertEqual(argument.a2, 999)
                XCTAssertFalse(argument.a3)
                XCTAssertFalse(argument.a4)
            } catch {
                XCTFail("Should not reach here")
            }
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testFetchConversationWithReset() {
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        createSut(labelID: "1245", labelType: .folder, isCustom: false, labelName: nil)

        self.conversationProviderMock.fetchConversationsStub.bodyIs { _, _, _, _, _, completion in
            completion?(.success)
        }

        let expectation1 = expectation(description: "Closure is called")
        sut.updateMailbox(showUnreadOnly: false, isCleanFetch: true, time: 999) { error in
            XCTFail("Shouldn't have error")
        } completion: {
            XCTAssertTrue(self.conversationProviderMock.fetchConversationsStub.wasCalledExactlyOnce)
            XCTAssertTrue(self.conversationProviderMock.fetchConversationCountsStub.wasCalledExactlyOnce)
            do {
                let argument = try XCTUnwrap(self.conversationProviderMock.fetchConversationsStub.lastArguments)
                XCTAssertEqual(argument.first, self.sut.labelID)
                XCTAssertEqual(argument.a2, 999)
                XCTAssertFalse(argument.a3)
                XCTAssertTrue(argument.a4)

                let argument2 = try XCTUnwrap(self.conversationProviderMock.fetchConversationCountsStub.lastArguments)
                XCTAssertNil(argument2.first)
            } catch {
                XCTFail("Should not reach here")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // There could be a race condition with this check. FetchLatestEventId runs in a
                // background thread (as any UseCase by default). FetchLatestEventId is called inside
                // updateMailbox but the callback is ignored and the execution continues without
                // waiting.
                // Therefore the following assert could run even before FetchLatestEventId runs.
                XCTAssertTrue(self.mockFetchLatestEventId.callExecutionBlock.wasCalledExactlyOnce)
                expectation1.fulfill()
            }
        }

//        sut.fetchDataWithReset(time: 999,
//                               cleanContact: false,
//                               unreadOnly: false) { _, _, _ in
//            XCTAssertTrue(self.conversationProviderMock.fetchConversationsStub.wasCalledExactlyOnce)
//            XCTAssertTrue(self.conversationProviderMock.callFetchConversationCounts.wasCalledExactlyOnce)
//            XCTAssertTrue(self.mockFetchLatestEventId.executeWasCalled)
//            do {
//                let argument = try XCTUnwrap(self.conversationProviderMock.fetchConversationsStub.lastArguments)
//                XCTAssertEqual(argument.first, self.sut.labelID)
//                XCTAssertEqual(argument.a2, 999)
//                XCTAssertFalse(argument.a3)
//                XCTAssertTrue(argument.a4)
//
//                let argument2 = try XCTUnwrap(self.conversationProviderMock.callFetchConversationCounts.lastArguments)
//                XCTAssertNil(argument2.first)
//            } catch {
//                XCTFail("Should not reach here")
//            }
//            expectation1.fulfill()
//        }
        waitForExpectations(timeout: 5, handler: nil)
    }

    func testSelectionContainsReadItems_inConversation_withReadConversation() {
        conversationStateProviderMock.viewModeStub.fixture = .conversation

        let conversationIDs = setupConversations(labelID: sut.labelID.rawValue, unreadStates: [true, false])
        sut.setupFetchController(nil)

        for id in conversationIDs {
            sut.select(id: id)
        }

        XCTAssertTrue(
            sut.selectionContainsReadItems(),
            "Should return true because the selected conversations contain at least one read message"
        )
    }

    func testSelectionContainsReadItems_inConversation_withoutReadConversation() {
        conversationStateProviderMock.viewModeStub.fixture = .conversation

        let conversationIDs = setupConversations(labelID: sut.labelID.rawValue, unreadStates: [true, true])
        sut.setupFetchController(nil)

        for id in conversationIDs {
            sut.select(id: id)
        }

        XCTAssertFalse(
            sut.selectionContainsReadItems(),
            "Should return false because all messages in all of the selected conversations are unread"
        )
    }

    func testSelectionContainsReadItems_inSingleMode_withReadMessage() {
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage

        let messageIDs = setupMessages(labelID: sut.labelID.rawValue, unreadStates: [true, false])
        sut.setupFetchController(nil)

        for id in messageIDs {
            sut.select(id: id)
        }

        XCTAssertTrue(
            sut.selectionContainsReadItems(),
            "Should return true because the selected conversations contain at least one read message"
        )
    }

    func testSelectionContainsReadItems_inSingleMode_withoutReadMessage() {
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage

        let messageIDs = setupMessages(labelID: sut.labelID.rawValue, unreadStates: [true, true])
        sut.setupFetchController(nil)

        for id in messageIDs {
            sut.select(id: id)
        }

        XCTAssertFalse(
            sut.selectionContainsReadItems(),
            "Should return false because all messages in all of the selected conversations are unread"
        )
    }

    private func setupConversations(labelID: String, unreadStates: [Bool]) -> [String] {
        let messageCount: NSNumber = 3

        return unreadStates.map { unreadState in
            let conversation = Conversation(context: testContext)
            conversation.conversationID = UUID().uuidString
            conversation.numMessages = messageCount

            let contextLabel = ContextLabel(context: testContext)
            contextLabel.labelID = labelID
            contextLabel.conversation = conversation
            contextLabel.unreadCount = unreadState ? messageCount : 0
            contextLabel.userID = "1"

            return conversation.conversationID
        }
    }

    private func setupMessages(labelID: String, unreadStates: [Bool]) -> [String] {
        let label = Label(context: testContext)
        label.labelID = labelID

        return unreadStates.map { unreadState in
            let testMessage = Message(context: testContext)
            testMessage.conversationID = UUID().uuidString
            testMessage.add(labelID: labelID)
            testMessage.messageStatus = 1
            testMessage.unRead = unreadState
            testMessage.userID = "1"
            return testMessage.messageID
        }
    }
}
