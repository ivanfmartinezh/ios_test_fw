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
    private let settingsDeviceRobot = SettingsDeviceViewRobot()
    private let settingsAccountRobot = SettingsAccountViewRobot()
    private let toolbarRobot = ToolbarSettingViewRobot()
    private let conversationRobot = ConversationViewRobot()
    private let composerRobot = ComposerViewRobot()
    private let searchRobot = SearchViewRobot()

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

    // Test Case 1: Buttons
    // Description: Check login is perform with according credentials when Sign in button is pressed
    func Login() {
        // ACT
        loginRobot.waitForAppearance()
        loginRobot.signIn()
        // ASSERT
        mailboxRobot.waitForAppearance()
    }

    // Test case 2: Text Field
    // Description: Check Contacts List shows the name of a newly added contact.
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

    // Test case 3: Lists (information components)
    // Description: Check Folders List shows all added Folders.

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

    // Test case 4: Lists (user input)
    // Description: Check the toolbar action selected is added and displayed under a mail toolbar

    func testAddToolbarAction() {
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnSideMenu()
        menuRobot.waitForAppearance()
        menuRobot.swipeDownMenu()
        menuRobot.clickOnSettings()
        settingsDeviceRobot.waitForAppearance()
        settingsDeviceRobot.clickOnCustomizeToolbar()
        toolbarRobot.waitForAppearance()
        toolbarRobot.addToolbarAction("Reply")
        toolbarRobot.clickOnDone()
        settingsDeviceRobot.waitForAppearance()
        settingsDeviceRobot.clickOnCancel()
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnMessageByIndex(1)
        conversationRobot.waitForAppearance()
        conversationRobot.checkActionInToolbar("ic reply")
        conversationRobot.clickOnBackButton()
    }

    // Test case 6: Toast Messages
    // Description: Verify that the "Not all required fields are filled" toast message is displayed when trying to save a new product when only the name has been filled.

    func testSendMessage() {
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnCompose()
        composerRobot.waitForAppearance()
        composerRobot.sendBlankEmail(composerRobot.userEmail, "Test_Message")
        sleep(3)
        mailboxRobot.checkForBanner()
    }

    // Test case 7: Icons
    // Description: Check that the mail icon is displayed in the navigation menu.

    func testSideMenuIconsAppear() {
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnSideMenu()
        menuRobot.waitForAppearance()
        menuRobot.checkForIconsExists()
    }

    // Test case 8: Search Field
    // Description: Check that the mails are filtered by entering criteria of the mail in the search field.

    func testMailSearch() {
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnSearch()
        searchRobot.search("notify")
        searchRobot.checkMailAppear("Proton")
    }

    // Test case 9: Settings menu
    // Description: Verify that the Settings screen can be accessed using the top menu button and that it contains the expected options.

    func testSettingsAppear() {
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnSideMenu()
        menuRobot.waitForAppearance()
        menuRobot.swipeDownMenu()
        menuRobot.clickOnSettings()
        settingsDeviceRobot.waitForAppearance()
        settingsDeviceRobot.checkForItemsExists()
    }

    // Test case 11: Navigation var
    // Description: Check that the main screen is displayed when the back button is clicked on the Shopping list screen.

    func testNavigationBar() {
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnSideMenu()
        menuRobot.waitForAppearance()
        menuRobot.swipeDownMenu()
        menuRobot.clickOnSettings()
        settingsDeviceRobot.waitForAppearance()
        settingsDeviceRobot.clickOnAccountSettings()
        settingsAccountRobot.waitForAppearance()
        settingsAccountRobot.clickOnBackButton()
        settingsDeviceRobot.waitForAppearance()
        settingsDeviceRobot.clickOnCancel()
        mailboxRobot.waitForAppearance()
    }

    // Test case 12: Container
    // Description: Check that languages menu is shown

    func testConatiner() {
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnSideMenu()
        menuRobot.waitForAppearance()
        menuRobot.swipeDownMenu()
        menuRobot.clickOnSettings()
        settingsDeviceRobot.waitForAppearance()
        settingsDeviceRobot.swipeDown()
        settingsDeviceRobot.clickOnLanguages()
        settingsDeviceRobot.checkForLanguageExists()
    }

    // Test case 13: Interaction with internet
    // Description: Verify that mail can be send and received
    func testReceiveMessage() {
        mailboxRobot.waitForAppearance()
        mailboxRobot.clickOnCompose()
        composerRobot.waitForAppearance()
        composerRobot.sendBlankEmail(composerRobot.userEmail, "Test_Message5")
        sleep(60)
        mailboxRobot.checkForMail("Test_Message5")
    }
}
