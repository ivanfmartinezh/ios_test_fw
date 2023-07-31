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

import Foundation
import XCTest

class MailboxViewRobot: BaseRobot {

    let mailboxTableViewID = "MailboxViewController.tableView"
    let mailboxMenuBarButtonID = "MailboxViewController.menuBarButtonItem"
    let mailboxComposeButtonID = "MailboxViewController.composeBarButtonItem"
    let undoBannerButtonID = "Undo"
    let searchButtonID = "MailboxViewController.searchBarButtonItem"
    let mailID = ".titleLabel"

    override func waitForAppearance(timeout: TimeInterval = 30) {
        let mailboxConfirmationElement = app.tables[mailboxTableViewID]
        let result = mailboxConfirmationElement.waitForExistence(timeout: timeout)
        XCTAssert(result, "The MailboxViewController confirmation element has not appeared")
    }

    func clickOnSideMenu() {
        clickOnButton(mailboxMenuBarButtonID)
    }

    func clickOnCompose() {
        clickOnNavigationButton(mailboxComposeButtonID)
    }

    func clickOnMessageByIndex (_ index: Int) {
        clickOnCellByIndex("MailboxViewController.tableView", index)
    }

    func checkForBanner() {
        let result = checkElementExists(button(undoBannerButtonID), timeout: 5)
        XCTAssert(result, "Banner has not appear")
    }

    func clickOnSearch() {
        clickOnButton(searchButtonID)
    }

    func checkForMail(_ mailSubject: String) {
        let result = checkElementExists(cell(mailSubject + mailID), timeout: 5)
        XCTAssert(result)
    }
}
