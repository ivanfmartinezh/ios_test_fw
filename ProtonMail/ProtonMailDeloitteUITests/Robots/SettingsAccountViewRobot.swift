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

class SettingsAccountViewRobot: BaseRobot {

    let settingsAccountViewID = "Account settings"
    let folderCellID = "SettingsGeneralCell.Folders"
    let backButtonID = "BackButton"

    override func waitForAppearance(timeout: TimeInterval = 30) {
        let settingsAccountConfirmationElement = app.staticTexts[settingsAccountViewID]
        let result = settingsAccountConfirmationElement.waitForExistence(timeout: timeout)
        XCTAssert(result, "The SettingsAccountViewController confirmation element has not appeared")
    }

    func clickOnFolder() {
        clickOnCell(folderCellID)
    }

    func clickOnBackButton() {
        clickOnButton(backButtonID)
    }

    func swipeDownMenu() {
        let tableView = app.tables.firstMatch
        tableView.swipeUp()
    }

    func swipeUpMenu() {
        let tableView = app.tables.firstMatch
        tableView.swipeDown()
    }

}


