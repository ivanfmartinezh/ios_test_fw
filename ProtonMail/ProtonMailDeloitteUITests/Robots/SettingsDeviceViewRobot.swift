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

class SettingsDeviceViewRobot: BaseRobot {

    let settingsDeviceViewID = "Settings"
    let accountSettingsID = "ic-chevron-right"
    let cancelButtonID = "Close"
    let customizeToolbarID = "SettingsGeneralCell.Customize_toolbar"
    let languageCellID = "SettingsGeneralCell.Language"
    let languagesIdentifiers = ["беларуская мова", "Català", "简体中文"]
    let textIdentifiers = [
        "Dark_mode.leftText",
        "App_PIN.leftText",
        "Combined_contacts.leftText",
        "Default_browser.leftText",
        "Alternative_routing.leftText",
        "Swipe_actions.leftText",
        "Customize_toolbar.leftText",
        "Notifications.leftText",
        "Language.leftText",
        "Localization_Preview.leftText"
    ]

    override func waitForAppearance(timeout: TimeInterval = 30) {
        let settingsDeviceConfirmationElement = staticText(settingsDeviceViewID)
        let result = settingsDeviceConfirmationElement.waitForExistence(timeout: timeout)
        XCTAssert(result, "The SettingsDeviceViewController confirmation element has not appeared")
    }

    func clickOnAccountSettings() {
        clickOnImage(accountSettingsID)
    }

    func clickOnCancel() {
        clickOnButton(cancelButtonID)
    }

    func clickOnCustomizeToolbar() {
        clickOnCell(customizeToolbarID)
    }

    func clickOnLanguages() {
        clickOnCell(languageCellID)
    }

    func checkForItemsExists() {
        for identifier in textIdentifiers {
            let icon = image(identifier)
            XCTAssertTrue(icon.exists, "Icon \(identifier) does not exist.")
        }
    }

    func checkForLanguageExists() {
        for identifier in languagesIdentifiers {
            let text = checkElementExists(staticText(identifier), timeout: 5)
            XCTAssertTrue(text, "Language \(identifier) does not exist.")
        }
    }

    func swipeDown() {
        let tableView = app.tables.firstMatch
        tableView.swipeUp()
    }
}
