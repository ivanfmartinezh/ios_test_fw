//
// This file is part of Deloitte testing framework.
//
// Class: BaseRobot
// Description: Robot containing genric methods to perform action and make assertions on common UI elements

import Foundation
import XCTest

open class BaseRobot: UIElementsProtocol {

    let userEmail = "ivanf.martinezh.test@protonmail.com"

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
    func clickOnImage(_ id: String) -> Self {
        image(id).tap()
        return self
    }

    @discardableResult
    func clickOnCell(_ id: String) -> Self {
        cell(id).tap()
        return self
    }

    @discardableResult
    func clickOnNavigationButton(_ id: String) -> Self {
        navigationButton(id).tap()
        return self
    }

    @discardableResult
    func clickOnCellByIndex (_ id: String, _ index: Int) -> Self{
        let tableView = table(id)
        let cells = tableView.cells
        let cellToTap = cells.element(boundBy: index)
        cellToTap.tap()
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

    @discardableResult
    func checkElementExists(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let elemenExists = element.waitForExistence(timeout: timeout)
        return elemenExists
    }

    @discardableResult
    func clickOnKeyboardButton(_ id: String) -> Self {
        app.keyboards.buttons[id].tap()
        return self
    }
}
