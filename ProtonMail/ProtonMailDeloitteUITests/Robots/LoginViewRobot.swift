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

class LoginViewRobot: BaseRobot {

    let email = "ivanf.martinezh.test@protonmail.com"
    let password = "Wanted11"
    let loginViewTitleLabelID = "LoginViewController.titleLabel"
    let userTextFieldID = "LoginViewController.loginTextField.textField"
    let passwordSecureTextFieldID = "LoginViewController.passwordTextField.textField"
    let signInButtonID = "LoginViewController.signInButton"
    let mailboxTableViewID = "MailboxViewController.tableView"

    override func waitForAppearance(timeout: TimeInterval = 30) {
        let loginConfirmationElement = app.staticTexts[loginViewTitleLabelID]
        let result = loginConfirmationElement.waitForExistence(timeout: timeout)
        XCTAssert(result, "The login confirmation element has not appeared")
    }

    func signIn() {
        writeOnTextField(userTextFieldID, email)
            .writeOnSecureTextField(passwordSecureTextFieldID, password)
            .clickOnButton(signInButtonID)
    }
}

