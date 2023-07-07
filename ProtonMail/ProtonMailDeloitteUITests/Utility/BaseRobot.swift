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

open class BaseRobot: UIElementsProtocol {

open func waitForAppearance(timeout: TimeInterval = 15) {

    }

    @discardableResult
    func clickOnButton(_ id: String) -> Self {
        button(id).tap()
        return self
    }

    @discardableResult
    func clickOnTable(_ id: String) -> Self {
        table(id).tap()
        return self
    }

    @discardableResult
    func clickOnStaticText(_ id: String) -> Self {
        staticText(id).tap()
        return self
    }

    @discardableResult
    func clickOnTextField(_ id: String) -> Self {
        textField(id).tap()
        return self
    }

    @discardableResult
    func clickOnSecureTextField(_ id: String) -> Self {
        secureTextField(id).tap()
        return self
    }

    @discardableResult
    func writeOnTextField(_ id: String, _ text: String) -> Self {
        textField(id).tap()
        textField(id).typeText(text)
        return self
    }

    @discardableResult
    func writeOnSecureTextField(_ id: String, _ text: String) -> Self {
        secureTextField(id).tap()
        secureTextField(id).typeText(text)
        return self
    }
}

