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

class MenuViewRobot: BaseRobot {

    let menuViewPrimaryUserID = "MenuViewController.primaryUserview"
    let menuItemContactsID = "Contacts.name"
    let menuTableViewID = "MenuViewController.tableView"

    override func waitForAppearance(timeout: TimeInterval = 30) {
        let menuConfirmationElement = app.tables[menuTableViewID]
        let result = menuConfirmationElement.waitForExistence(timeout: timeout)
        XCTAssert(result, "The MenuViewController confirmation element has not appeared")
    }

    func clickOnContacts() {
        clickOnStaticText(menuItemContactsID)
    }

    func swipeDownMenu() {
        app.tables[menuTableViewID].swipeUp()
    }
}
