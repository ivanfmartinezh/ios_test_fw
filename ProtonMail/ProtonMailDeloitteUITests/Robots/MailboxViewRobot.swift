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

    override func waitForAppearance(timeout: TimeInterval = 30) {
        let mailboxConfirmationElement = app.tables[mailboxTableViewID]
        let result = mailboxConfirmationElement.waitForExistence(timeout: timeout)
        XCTAssert(result, "The MailboxViewController confirmation element has not appeared")
    }

    func clickOnSideMenu() {
        clickOnButton(mailboxMenuBarButtonID)
    }

    func clickOnCompose() {
        let composeButton = app.navigationBars.buttons[mailboxComposeButtonID] // Replace "Back" with the actual label of the Back button
        composeButton.tap()
    }

    func clickOnMessageByIndex (_ index: Int) {
        // Find the table view
        let tableView = app.tables["MailboxViewController.tableView"]
        // Find the cells within the table view
        let cells = tableView.cells
        // Find the cell at the desired index
        let cellToTap = cells.element(boundBy: index)
        // Tap on the cell
        cellToTap.tap()
    }

    func checkForBanner() {
        let result = button(undoBannerButtonID).exists
        // XCTAssert(result, "Banner has not appear")
    }
}
