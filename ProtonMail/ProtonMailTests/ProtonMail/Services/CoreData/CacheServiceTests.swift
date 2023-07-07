//
//  CacheServiceTests.swift
//  ProtonMailTests
//
//  Copyright (c) 2021 Proton AG
//
//  This file is part of Proton Mail.
//
//  Proton Mail is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Proton Mail is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Proton Mail.  If not, see <https://www.gnu.org/licenses/>.

import XCTest
@testable import ProtonMail
import CoreData
import Groot

class CacheServiceTest: XCTestCase {
    var testMessage: Message!
    var lastUpdatedStore: MockLastUpdatedStore!
    var sut: CacheService!
    var contextProviderMock: MockCoreDataContextProvider!
    var testContext: NSManagedObjectContext!

    override func setUpWithError() throws {
        contextProviderMock = .init()
        testContext = contextProviderMock.viewContext
        
        let parsedObject = testMessageMetaData.parseObjectAny()!
        testMessage = try GRTJSONSerialization.object(withEntityName: "Message",
                                                      fromJSONDictionary: parsedObject, in: testContext) as? Message
        testMessage.userID = "userID"

        let parsedLabel = testLabelsData.parseJson()!
        _ = try GRTJSONSerialization.objects(withEntityName: Label.Attributes.entityName, fromJSONArray: parsedLabel, in: testContext)
        
        try testContext.save()

        let mock = MockLastUpdatedStore()
        mock.testContext = testContext
        lastUpdatedStore = mock

        let dependencies = CacheService.Dependencies(
            coreDataService: contextProviderMock,
            lastUpdatedStore: lastUpdatedStore
        )
        sut = CacheService(userID: "userID", dependencies: dependencies)
    }
    
    override func tearDown() {
        testMessage = nil
        sut = nil
        testContext = nil
        lastUpdatedStore.resetUnreadCounts()
        lastUpdatedStore = nil
        contextProviderMock = nil
    }

    func testMoveMessageToArchive() {
        let label = Message.Location.inbox.labelID
        let unreadCountOfInbox: Int = lastUpdatedStore.unreadCount(by: label, userID: sut.userID, type: .singleMessage)
        let unreadCountOfArchive: Int = lastUpdatedStore.unreadCount(by: Message.Location.archive.labelID, userID: sut.userID, type: .singleMessage)

        let result = sut.move(message: MessageEntity(self.testMessage), from: label, to: Message.Location.archive.labelID)
        XCTAssertTrue(result)

        let newMsg = Message.messageForMessageID(testMessage.messageID, inManagedObjectContext: testContext)
        let msg = try! XCTUnwrap(newMsg)
        let newLabels: [String] = msg.getLabelIDs()
        XCTAssertFalse(newLabels.contains(label.rawValue))

        let unreadCountOfInboxAfterMove: Int = lastUpdatedStore.unreadCount(by: label, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInbox, unreadCountOfInboxAfterMove)

        let unreadCountOfArchiveAfterMove: Int = lastUpdatedStore.unreadCount(by: Message.Location.archive.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfArchive, unreadCountOfArchiveAfterMove)
    }
    
    func testMoveUnreadMessageToArchive() {
        let label = Message.Location.inbox.labelID
        self.testMessage.unRead = true
        loadTestDataOfUnreadCount(defaultUnreadCount: 1, labelID: label)
        loadTestDataOfUnreadCount(defaultUnreadCount: 0, labelID: Message.Location.archive.labelID)

        let unreadCountOfInbox: Int = lastUpdatedStore.unreadCount(by: label, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInbox, 1)
        let unreadCountOfArchive: Int = lastUpdatedStore.unreadCount(by: Message.Location.archive.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfArchive, 0)

        let result = sut.move(message: MessageEntity(self.testMessage), from: label, to: Message.Location.archive.labelID)
        XCTAssertTrue(result)
        
        let newLabels: [String] = self.testMessage.getLabelIDs()
        XCTAssertFalse(newLabels.contains(label.rawValue))
        XCTAssertTrue(newLabels.contains(Message.Location.archive.rawValue))

        let unreadCountOfInboxAfterMove: Int = lastUpdatedStore.unreadCount(by: label, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInboxAfterMove, 0)
        let unreadCountOfArchiveAfterMove: Int = lastUpdatedStore.unreadCount(by: Message.Location.archive.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfArchiveAfterMove, 1)
    }
    
    func testMoveMessageToTrash() {
        let label = Message.Location.inbox.labelID
        let unreadCountOfInbox: Int = lastUpdatedStore.unreadCount(by: label, userID: sut.userID, type: .singleMessage)
        let unreadCountOfTrash: Int = lastUpdatedStore.unreadCount(by: Message.Location.trash.labelID, userID: sut.userID, type: .singleMessage)

        let result = sut.move(message: MessageEntity(self.testMessage), from: label, to: Message.Location.trash.labelID)
        XCTAssertTrue(result)
        
        let newLabels: [String] = self.testMessage.getLabelIDs()
        XCTAssertFalse(newLabels.contains(label.rawValue))
        XCTAssertTrue(newLabels.contains(Message.Location.trash.rawValue))

        let unreadCountOfInboxAfterMove: Int = lastUpdatedStore.unreadCount(by: label, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInbox, unreadCountOfInboxAfterMove)

        let unreadCountOfTrashAfterMove: Int = lastUpdatedStore.unreadCount(by: Message.Location.archive.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfTrash, unreadCountOfTrashAfterMove)
    }
    
    func testMoveUnreadMessageToTrash() {
        let label = Message.Location.inbox.labelID
        self.testMessage.unRead = true
        loadTestDataOfUnreadCount(defaultUnreadCount: 1, labelID: label)

        let unreadCountOfInbox: Int = lastUpdatedStore.unreadCount(by: label, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInbox, 1)
        let unreadCountOfTrash: Int = lastUpdatedStore.unreadCount(by: Message.Location.trash.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfTrash, 0)

        let result = sut.move(message: MessageEntity(self.testMessage), from: label, to: Message.Location.trash.labelID)
        XCTAssertTrue(result)
        
        let newLabels: [String] = self.testMessage.getLabelIDs()
        XCTAssertFalse(newLabels.contains(label.rawValue))
        XCTAssertTrue(newLabels.contains(Message.Location.trash.rawValue))

        let unreadCountOfInboxAfterMove: Int = lastUpdatedStore.unreadCount(by: label, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInboxAfterMove, 0)
        let unreadCountOfTrashAfterMove: Int = lastUpdatedStore.unreadCount(by: Message.Location.trash.labelID, userID: sut.userID, type: .singleMessage)
        //Move to trash will mark msg as read
        XCTAssertEqual(unreadCountOfTrashAfterMove, 0)
    }
    
    func testRemoveLabel() {
        sut.removeLabel(on: self.testMessage, labels: [Message.Location.inbox.rawValue], cleanUnread: false)
        let newLabels: [String] = self.testMessage.getLabelIDs()
        XCTAssertFalse(newLabels.contains(Message.Location.inbox.rawValue))
    }
    
    func testDeleteMessage() {
        self.testMessage.unRead = true
        loadTestDataOfUnreadCount(defaultUnreadCount: 1, labelID: Message.Location.inbox.labelID)
        
        let msgID = self.testMessage.messageID
        XCTAssertNotNil(Message.messageForMessageID(msgID, inManagedObjectContext: self.testContext))
        
        XCTAssertTrue(sut.delete(message: MessageEntity(self.testMessage), label: Message.Location.inbox.labelID))
        
        XCTAssertNil(Message.messageForMessageID(msgID, inManagedObjectContext: self.testContext))

        let unreadCountOfInboxAfterDelete: Int = lastUpdatedStore.unreadCount(by: Message.Location.inbox.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInboxAfterDelete, 0)
    }

    func testMessageUpdateEO() {
        let expirationTime = TimeInterval(100.0)
        let pwd = "PWD"
        let pwdHint = "Hint"

        let expect = expectation(description: "Update EO")
        sut.updateExpirationOffset(of: self.testMessage.objectID, expirationTime: expirationTime, pwd: pwd, pwdHint: pwdHint) {
            expect.fulfill()
        }
        wait(for: [expect], timeout: 1)

        XCTAssertEqual(self.testMessage.password, pwd)
        XCTAssertEqual(self.testMessage.passwordHint, pwdHint)
        XCTAssertEqual(self.testMessage.expirationOffset, Int32(expirationTime))
    }
    
    func testMarkReadMessageAsRead() {
        loadTestDataOfUnreadCount(defaultUnreadCount: 0, labelID: Message.Location.inbox.labelID)
        XCTAssertTrue(sut.mark(messageObjectID: testMessage.objectID, labelID: Message.Location.inbox.labelID, unRead: false))
        
        XCTAssertFalse(self.testMessage.unRead)
        let unreadCountOfInbox: Int = lastUpdatedStore.unreadCount(by: Message.Location.inbox.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInbox, 0)
    }
    
    func testMarkReadMessageAsUnread() {
        loadTestDataOfUnreadCount(defaultUnreadCount: 0, labelID: Message.Location.inbox.labelID)
        XCTAssertTrue(sut.mark(messageObjectID: testMessage.objectID, labelID: Message.Location.inbox.labelID, unRead: true))
        
        XCTAssertTrue(self.testMessage.unRead)
        let unreadCountOfInbox: Int = lastUpdatedStore.unreadCount(by: Message.Location.inbox.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInbox, 1)
    }
    
    func testMarkUnreadMessageAsRead() {
        self.testMessage.unRead = true
        loadTestDataOfUnreadCount(defaultUnreadCount: 1, labelID: Message.Location.inbox.labelID)
        
        XCTAssertTrue(sut.mark(messageObjectID: testMessage.objectID, labelID: Message.Location.inbox.labelID, unRead: false))
        
        XCTAssertFalse(self.testMessage.unRead)
        let unreadCountOfInbox: Int = lastUpdatedStore.unreadCount(by: Message.Location.inbox.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInbox, 0)
    }
    
    func testMarkUnreadMessageAsUnread() {
        self.testMessage.unRead = true
        loadTestDataOfUnreadCount(defaultUnreadCount: 1, labelID: Message.Location.inbox.labelID)
        
        XCTAssertTrue(sut.mark(messageObjectID: testMessage.objectID, labelID: Message.Location.inbox.labelID, unRead: true))
        
        XCTAssertTrue(self.testMessage.unRead)
        let unreadCountOfInbox: Int = lastUpdatedStore.unreadCount(by: Message.Location.inbox.labelID, userID: sut.userID, type: .singleMessage)
        XCTAssertEqual(unreadCountOfInbox, 1)
    }
    
    func testLabelAndUnLabelMessage() {
        let labelIDToAdd: LabelID = "dixQoKdS1OPVzHB0nZ5Yp7MDlZM4-nHhvspULoUSdWKFRKhHLOQEmU58ExrwFHJY2cejSP1TrDOyc7mvVcSa6Q=="
        
        XCTAssertTrue(sut.label(messages: [MessageEntity(self.testMessage)], label: labelIDToAdd, apply: true))
        let labels: [String] = self.testMessage.getLabelIDs()
        XCTAssertTrue(labels.contains(labelIDToAdd.rawValue))
        
        XCTAssertTrue(sut.label(messages: [MessageEntity(self.testMessage)], label: labelIDToAdd, apply: false))
        let newLabels: [String] = self.testMessage.getLabelIDs()
        XCTAssertFalse(newLabels.contains(labelIDToAdd.rawValue))
    }

    func testCleanReviewItems() {
        let msgID = self.testMessage.messageID
        self.testMessage.messageType = NSNumber(value: 1)

        let expect = expectation(description: "CleanReviewItems")
        sut.cleanReviewItems(completion: {
            expect.fulfill()
        })
        wait(for: [expect], timeout: 1)

        XCTAssertNil(Message.messageForMessageID(msgID, inManagedObjectContext: testContext))
    }
}

extension CacheServiceTest {
    func loadTestDataOfUnreadCount(defaultUnreadCount: Int, labelID: LabelID) {
        _ = lastUpdatedStore.lastUpdateDefault(by: labelID, userID: sut.userID, type: .singleMessage)
        lastUpdatedStore.updateUnreadCount(by: labelID, userID: sut.userID, unread: defaultUnreadCount, total: nil, type: .singleMessage, shouldSave: true)
        _ = lastUpdatedStore.lastUpdateDefault(by: labelID, userID: sut.userID, type: .conversation)
        lastUpdatedStore.updateUnreadCount(by: labelID, userID: sut.userID, unread: defaultUnreadCount, total: nil, type: .conversation, shouldSave: true)
    }
}
