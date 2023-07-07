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

import XCTest
import ProtonCore_Crypto
@testable import ProtonMail

final class PushNotificationHandlerTests: XCTestCase {
    var sut: PushNotificationHandler!
    private var mockEncryptionKitProvider: EncryptionKitProviderMock!

    override func setUp() {
        super.setUp()
        mockEncryptionKitProvider = EncryptionKitProviderMock()
        let dependencies = PushNotificationHandler.Dependencies(
            encryptionKitProvider: mockEncryptionKitProvider
        )
        sut = PushNotificationHandler(dependencies: dependencies)
    }

    override func tearDown() {
        super.tearDown()
        sut = nil
        mockEncryptionKitProvider = nil
    }

    func testHandle_shouldProperlyDecryptNotification_whenIsEmailNotification() {
        let testBody = "Test subject"
        let testSender = "A sender"
        let identifier = UUID().uuidString
        let request = mailNotificationRequest(
            uid: mockEncryptionKitProvider.UID,
            identifier: identifier,
            sender: testSender,
            body: testBody
        )

        let expectation = self.expectation(description: "Decryption expectation")
        sut.handle(request: request) { decryptedContent in
            XCTAssertEqual(decryptedContent.threadIdentifier, self.mockEncryptionKitProvider.UID)
            XCTAssertEqual(decryptedContent.title, testSender)
            XCTAssertEqual(decryptedContent.body, testBody)
            XCTAssertFalse(self.mockEncryptionKitProvider.markForUnsubscribingWasCalled)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandle_shouldProperlyDecryptNotification_whenIsOpenUrlNotification() {
        let expectedSender = "ProntonMail"
        let expectedBody = "New sign in to your account"
        let identifier = UUID().uuidString
        let request = mailNotificationRequest(
            uid: mockEncryptionKitProvider.UID,
            identifier: identifier,
            sender: expectedSender,
            body: expectedBody
        )

        let expectation = self.expectation(description: "Decryption expectation")
        sut.handle(request: request) { decryptedContent in
            XCTAssertEqual(decryptedContent.threadIdentifier, self.mockEncryptionKitProvider.UID)
            XCTAssertEqual(decryptedContent.title, expectedSender)
            XCTAssertEqual(decryptedContent.body, expectedBody)
            XCTAssertFalse(self.mockEncryptionKitProvider.markForUnsubscribingWasCalled)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandle_whenEncriptionKitNotFound_shoudRemoveDeviceToken() {
        let nonExistingUID = UUID().uuidString
        let request = mailNotificationRequest(
            uid: nonExistingUID,
            identifier: UUID().uuidString,
            sender: String.randomString(10),
            body: String.randomString(20)
        )

        let expectation = self.expectation(description: "Decryption expectation")
        sut.handle(request: request) { decryptedContent in
            XCTAssertTrue(self.mockEncryptionKitProvider.markForUnsubscribingWasCalled)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}

private extension PushNotificationHandlerTests {
    private func mailNotificationRequest(
        uid: String,
        identifier: String,
        sender: String,
        body: String
    ) -> UNNotificationRequest {
        let plainTextPayload = """
        {
          "data": {
            "title": "ProtonMail",
            "subtitle": "",
            "body": "\(body)",
            "sender": {
              "Name": "\(sender)",
              "Address": "foo@bar.com",
              "Group": ""
            },
            "vibrate": 1,
            "sound": 1,
            "largeIcon": "large_icon",
            "smallIcon": "small_icon",
            "badge": \(Int.random(in: 0..<100)),
            "messageId": "\(UUID().uuidString)"
          },
          "type": "email",
          "version": 2
        }
        """
        let encryptedPayload = try! Encryptor.encrypt(
            publicKey: mockEncryptionKitProvider.publicKey,
            cleartext: plainTextPayload
        ).value
        let userInfo: [NSString: Any?] = [
            "UID": uid,
            "unreadConversations": nil,
            "unreadMessages": Int.random(in: 0..<100),
            "viewMode": Int.random(in: 0...1),
            "encryptedMessage": encryptedPayload,
            "aps": ["alert": "New message received",
                    "badge": Int.random(in: 0..<100),
                    "mutable-content": 1]
        ]
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo as [AnyHashable: Any]
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content,
                                            trigger: nil)
        return request
    }

    private func openUrlNotificationRequest(identifier: String, sender: String, body: String) -> UNNotificationRequest {
        let encryptedPayload = PushEncryptedMessageTestData
            .openUrlNotification(with: mockEncryptionKitProvider, sender: sender, body: body)
        let userInfo: [NSString: Any?] = [
            "UID": mockEncryptionKitProvider.UID,
            "unreadConversations": nil,
            "unreadMessages": Int.random(in: 0..<100),
            "viewMode": Int.random(in: 0...1),
            "encryptedMessage": encryptedPayload,
            "aps": ["alert": "New message received",
                    "badge": Int.random(in: 0..<100),
                    "mutable-content": 1]
        ]
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo as [AnyHashable: Any]
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content,
                                            trigger: nil)
        return request
    }
}
