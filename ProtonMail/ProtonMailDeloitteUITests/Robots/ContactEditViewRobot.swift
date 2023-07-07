// Copyright (c) 2023 Proton Technologies AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at /Users/imartinezhernandez/Documents/TestingFW/ProtonMailDeloitteUITests/Robots/ContactEditViewRobot.swiftyour option) any later version.
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

class ContactEditViewRobot: BaseRobot {

    let contactEditTableViewID = "ContactEditViewController.tableView"
    let displayNameTextFieldID = "ContactEditViewController.displayNameField"
    let saveButtonID = "ContactEditViewController.doneItem"

    override func waitForAppearance(timeout: TimeInterval = 30) {
        let contactEditConfirmationElement = app.tables[contactEditTableViewID]
        let result = contactEditConfirmationElement.waitForExistence(timeout: timeout)
        XCTAssert(result, "The ContactEditViewController confirmation element has not appeared")
    }

    func enterContactName(_ name: String) {
        writeOnTextField(displayNameTextFieldID, name)
    }

    func saveContact() {
        clickOnButton(saveButtonID)
    }
}

