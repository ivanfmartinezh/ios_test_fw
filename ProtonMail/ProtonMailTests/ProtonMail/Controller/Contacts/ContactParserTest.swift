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

import ProtonCore_Crypto
import ProtonCore_DataModel
import XCTest
@testable import ProtonMail

final class ContactParserTest: XCTestCase {
    private var resultMock: ContactParserResultViewMock!
    private var contactParser: ContactParser!

    override func setUpWithError() throws {
        self.resultMock = ContactParserResultViewMock()
        self.contactParser = ContactParser(resultDelegate: resultMock)
    }

    override func tearDownWithError() throws {
        self.resultMock = nil
        self.contactParser = nil
    }

    func getWrongKey() -> ArmoredKey {
        let privateKey = ContactParserTestData.privateKey
        let index = ContactParserTestData.passphrase.value.index(privateKey.value.startIndex,
                                                           offsetBy: 10)
        let wrongPrivateKey = String(privateKey.value[index...])
        return ArmoredKey(value: wrongPrivateKey)
    }

    func testParsePlainTextContact() throws {
        let coreDataService = CoreDataService(container: MockCoreDataStore.testPersistentContainer)
        let contactID: ContactID = .init(rawValue: UUID().uuidString)
        let plainText = ContactParserTestData.plainTextData
        self.contactParser
            .parsePlainTextContact(data: plainText,
                                   coreDataService: coreDataService,
                                   contactID: contactID)
        XCTAssertEqual(self.resultMock.emails.count, 1)
        XCTAssertEqual(self.resultMock.emails[0].newEmail, "iamtest@aaa.bbb")
    }

    func testParseEncryptedOnlyContact_succeed() throws {
        let card = CardData(type: .EncryptedOnly,
                            data: ContactParserTestData.encryptedOnlyData,
                            signature: "")
        let passphrase = ContactParserTestData.passphrase
        let key = ContactParserTestData.privateKey
        try self.contactParser
            .parseEncryptedOnlyContact(card: card,
                                       passphrase: passphrase,
                                       userKeys: [key])
        XCTAssertFalse(self.resultMock.decryptError)
        XCTAssertEqual(self.resultMock.addresses.count, 1)
        let address = self.resultMock.addresses[0]
        XCTAssertEqual(address.newStreet, "Dange Chowk Rd")
        XCTAssertEqual(address.newStreetTwo, "Bhatewara Nagar, Hinjawadi Village, Hinjawadi")
        XCTAssertEqual(address.newLocality, "Pimpri-Chinchwad")
        XCTAssertEqual(address.newRegion, "Maharashtra")
        XCTAssertEqual(self.resultMock.telephones.count, 1)
        XCTAssertEqual(self.resultMock.telephones[0].newPhone, "0912 345 678")
    }

    func testParseEncryptedOnlyContact_wrongPassphrase() throws {
        let card = CardData(type: .EncryptedOnly,
                            data: ContactParserTestData.encryptedOnlyData,
                            signature: "")
        let passphrase = Passphrase(value: ContactParserTestData.passphrase.value + "fjeilfejlf")
        let key = ContactParserTestData.privateKey
        XCTAssertThrowsError(
            try self.contactParser
                .parseEncryptedOnlyContact(card: card,
                                           passphrase: passphrase,
                                           userKeys: [key])
        )
        XCTAssertTrue(self.resultMock.decryptError)
    }

    func testParseEncryptedOnlyContact_wrongPrivateKey() throws {
        let card = CardData(type: .EncryptedOnly,
                            data: ContactParserTestData.encryptedOnlyData,
                            signature: "")
        let passphrase = ContactParserTestData.passphrase
        let key = self.getWrongKey()
        XCTAssertThrowsError(
            try self.contactParser
                .parseEncryptedOnlyContact(card: card,
                                           passphrase: passphrase,
                                           userKeys: [key])
        )
        XCTAssertTrue(self.resultMock.decryptError)
    }

    func testParseSignature_succeed() throws {
        let signature = ContactParserTestData.signedOnlySignature
        let data = ContactParserTestData.signedOnlyData
        let passphrase = ContactParserTestData.passphrase
        let key = ContactParserTestData.privateKey
        let isVerify = self.contactParser.verifySignature(signature: signature,
                                                          plainText: data,
                                                          userKeys: [key],
                                                          passphrase: passphrase)
        XCTAssertTrue(isVerify)
    }

    func testParseSignature_wrongPassphrase() throws {
        let signature = ContactParserTestData.signedOnlySignature
        let data = ContactParserTestData.signedOnlyData
        let passphrase = Passphrase(value: ContactParserTestData.passphrase.value + "efsfd")
        let key = ContactParserTestData.privateKey
        let isVerify = self.contactParser.verifySignature(signature: signature,
                                                          plainText: data,
                                                          userKeys: [key],
                                                          passphrase: passphrase)
        XCTAssertFalse(isVerify)
    }

    func testParseSignature_wrongKey() throws {
        let signature = ContactParserTestData.signedOnlySignature
        let data = ContactParserTestData.signedOnlyData
        let passphrase = ContactParserTestData.passphrase
        let key = self.getWrongKey()
        let isVerify = self.contactParser.verifySignature(signature: signature,
                                                          plainText: data,
                                                          userKeys: [key],
                                                          passphrase: passphrase)
        XCTAssertFalse(isVerify)
    }

    func testParseSignAndEncrypt_succeed() throws {
        let data = ContactParserTestData.signAndEncryptData
        let signature = ContactParserTestData.signedOnlySignature
        let card = CardData(type: .SignAndEncrypt, data: data, signature: signature)
        let passphrase = ContactParserTestData.passphrase
        let key = ContactParserTestData.privateKey
        try self.contactParser
            .parseSignAndEncryptContact(card: card,
                                        passphrase: passphrase,
                                        firstUserKey: key,
                                        userKeys: [key])
        XCTAssertEqual(self.resultMock.addresses.count, 4)
        XCTAssertEqual(self.resultMock.telephones.count, 8)
        XCTAssertEqual(self.resultMock.informations.count, 4)
        XCTAssertEqual(self.resultMock.notes.count, 1)
        XCTAssertEqual(self.resultMock.urls.count, 1)
    }

    func testParseSignAndEncrypt_withoutFirstUserKey() {
        let data = ContactParserTestData.signAndEncryptData
        let signature = ContactParserTestData.signedOnlySignature
        let card = CardData(type: .SignAndEncrypt, data: data, signature: signature)
        let passphrase = ContactParserTestData.passphrase
        let key = ContactParserTestData.privateKey
        XCTAssertThrowsError(
            try self.contactParser
                .parseSignAndEncryptContact(card: card,
                                            passphrase: passphrase,
                                            firstUserKey: nil,
                                            userKeys: [key])
        )
    }

    func testParseSignAndEncrypt_wrongPassphrase() {
        let data = ContactParserTestData.signAndEncryptData
        let signature = ContactParserTestData.signedOnlySignature
        let card = CardData(type: .SignAndEncrypt, data: data, signature: signature)
        let passphrase = Passphrase(value: ContactParserTestData.passphrase.value + "fidld")
        let key = ContactParserTestData.privateKey
        XCTAssertThrowsError(
            try self.contactParser
                .parseSignAndEncryptContact(card: card,
                                            passphrase: passphrase,
                                            firstUserKey: key,
                                            userKeys: [key])
        )
        XCTAssertTrue(self.resultMock.decryptError)
    }

    func testParseSignAndEncrypt_wrongKey() {
        let data = ContactParserTestData.signAndEncryptData
        let signature = ContactParserTestData.signedOnlySignature
        let card = CardData(type: .SignAndEncrypt, data: data, signature: signature)
        let passphrase = ContactParserTestData.passphrase
        let key = self.getWrongKey()
        XCTAssertThrowsError(
            try self.contactParser
                .parseSignAndEncryptContact(card: card,
                                            passphrase: passphrase,
                                            firstUserKey: key,
                                            userKeys: [key])
        )
        XCTAssertTrue(self.resultMock.decryptError)
    }

    func testParseSignAndEncrypt_signatureFailed() throws {
        let data = ContactParserTestData.signAndEncryptData
        let signature = ContactParserTestData.signedOnlySignature
        let index = ContactParserTestData.passphrase.value.index(signature.value.startIndex,
                                                           offsetBy: 10)
        let wrongSignature = String(signature.value[index...])
        let card = CardData(type: .SignAndEncrypt, data: data, signature: wrongSignature)
        let passphrase = ContactParserTestData.passphrase
        let key = ContactParserTestData.privateKey
        try self.contactParser
            .parseSignAndEncryptContact(card: card,
                                        passphrase: passphrase,
                                        firstUserKey: key,
                                        userKeys: [key])
        XCTAssertFalse(self.resultMock.verifyType3)
        XCTAssertEqual(self.resultMock.addresses.count, 4)
        XCTAssertEqual(self.resultMock.telephones.count, 8)
        XCTAssertEqual(self.resultMock.informations.count, 4)
        XCTAssertEqual(self.resultMock.notes.count, 1)
        XCTAssertEqual(self.resultMock.urls.count, 1)
    }
}
