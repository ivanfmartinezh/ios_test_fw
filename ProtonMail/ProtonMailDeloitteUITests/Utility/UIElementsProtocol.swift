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

var currentApp: XCUIApplication?

public protocol UIElementsProtocol: AnyObject {
    var app: XCUIApplication { get }
}

public extension UIElementsProtocol {

    var app: XCUIApplication {
        if let app = currentApp {
            return app
        } else {
            currentApp = XCUIApplication()
            return currentApp!
        }
    }

    func button(_ indentifier: String) -> XCUIElement {
        return app.buttons[indentifier]
    }

    func staticText(_ identifier: String) -> XCUIElement {
        return app.staticTexts[identifier]
    }

    func textField(_ identifier: String) -> XCUIElement {
        return app.textFields[identifier]
    }

    func secureTextField(_ identifier: String) -> XCUIElement {
        return app.secureTextFields[identifier]
    }

    func table(_ identifier: String) -> XCUIElement {
        return app.tables[identifier]
    }
}

