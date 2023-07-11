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

class ConversationViewRobot: BaseRobot {

    let composerViewID = "PMToolBarView.unreadButton"
    let backButtonID = "ic-arrow-left"
    let toTextFieldID = "To:TextField"

    override func waitForAppearance(timeout: TimeInterval = 30) {
        let composerViewConfirmationElement = app.buttons[composerViewID]
        let result = composerViewConfirmationElement.waitForExistence(timeout: timeout)
        XCTAssert(result, "The ComposerViewController confirmation element has not appeared")
    }

    func checkActionInToolbar(_ action: String) {
        let actionVisible = button(action).exists
        XCTAssert(actionVisible, "The action is not visible on screen")
    }

    func clickOnBackButton() {
        let backButton = app.navigationBars.buttons["Inbox"] // Replace "Back" with the actual label of the Back button
        backButton.tap()
    }
}





