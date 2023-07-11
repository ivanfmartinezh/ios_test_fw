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

class ComposerViewRobot: BaseRobot {

    lazy var userID = userEmail
    let composerViewID = "ComposeContainerViewController.tableView"
    let backButtonID = "ic-arrow-left"
    let toTextFieldID = "To:TextField"
    let subjectID = "ComposeHeaderViewController.subject"
    let sendButtonID = "ComposeContainerViewController.sendButton"
    lazy var contactID = userID + ".nameLabel"

    override func waitForAppearance(timeout: TimeInterval = 30) {
        let composerViewConfirmationElement = app.tables[composerViewID]
        let result = composerViewConfirmationElement.waitForExistence(timeout: timeout)
        XCTAssert(result, "The ComposerViewController confirmation element has not appeared")
    }

    func sendBlankEmail(_ receiver: String, _ subject: String) {
        writeOnTextField(toTextFieldID, receiver)
        clickOnContactSuggest()
        writeOnTextField(subjectID, subject)
        let sendButton = app.navigationBars.buttons[sendButtonID] // Replace "Back" with the actual label of the Back button
        sendButton.tap()
    }

    func clickOnContactSuggest() {
        let contactListConfirmationElement = app.staticTexts[contactID]
        let result = contactListConfirmationElement.waitForExistence(timeout: 5)
        contactListConfirmationElement.tap()
    }
}




