// Copyright (c) 2023 Proton Technologies AG
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

final class ProtonMailDeloitteUITests: MainTestCase {

    private let loginRobot = LoginViewRobot()
    private let mailboxRobot = MailboxViewRobot()
    private let menuRobot = MenuViewRobot()
    private let contactsRobot = ContactsViewRobot()
    private let contactEditRobot = ContactEditViewRobot()
    private let folderEditRobot = FolderEditViewRobot()

    override func setUp() {
        super.setUp()
        setUpTestCase()
        continueAfterFailure = false
        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testLogin() {
        // ACT
        loginRobot.waitForAppearance()
        loginRobot.signIn()
        // ASSERT
        mailboxRobot.waitForAppearance()
        /*
        app/*@START_MENU_TOKEN@*/.scrollViews/*[[".otherElements[\"Would you like to save this password in your Keychain to use with apps and websites?\"].scrollViews",".scrollViews"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.otherElements.buttons["Not Now"].tap()
        XCTAssert(result, "The table view in MailboxViewController has not appeared")
        */
    }

    func testAddNewContact() {

        mailboxRobot.waitForAppearance()

        mailboxRobot.clickOnSideMenu()
        menuRobot.waitForAppearance()
        menuRobot.swipeDownMenu()
        sleep(5)
        menuRobot.clickOnContacts()
        contactsRobot.waitForAppearance()
        contactsRobot.clickOnAddButton()
        contactsRobot.clickOnNewContact()
        contactEditRobot.waitForAppearance()
        contactEditRobot.enterContactName("smith")
        contactEditRobot.saveContact()
        contactsRobot.waitForAppearance()
        contactsRobot.checkForContact("smith")
    }

    func testCustomFolder() {
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnSideMenu()
        menuRobot.waitForAppearance()
        menuRobot.addFolder()
        folderEditRobot.waitForAppearance()
        folderEditRobot.editFolderName("TestFolder")
        folderEditRobot.clickOnDone()
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnSideMenu()
        menuRobot.waitForAppearance()
        menuRobot.checkForItem("TestFolde")

    }
}


