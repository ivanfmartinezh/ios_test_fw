//
//  PinCodeConfirmationViewController.swift
//  Proton Mail
//
//
//  Copyright (c) 2021 Proton AG
//
//  This file is part of Proton Mail.
//
//  Proton Mail is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Proton Mail is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Proton Mail.  If not, see <https://www.gnu.org/licenses/>.
//

import ProtonCore_UIFoundations
import UIKit

class PinCodeConfirmationViewController: ProtonMailViewController {
    @IBOutlet private weak var passwordTextField: PMTextField!
    @IBOutlet private weak var confirmButton: ProtonButton!

    var viewModel: PinCodeViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = LocalString._pin_code_setup2_title

        view.backgroundColor = ColorProvider.BackgroundNorm

        passwordTextField.isPassword = true
        passwordTextField.title = LocalString._pin_code_setup2_textfield_title
        passwordTextField.allowOnlyNumbers = true

        confirmButton.setMode(mode: .solid)
        confirmButton.setTitle(LocalString._general_confirm_action, for: .normal)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        _ = passwordTextField.becomeFirstResponder()
    }

    @IBAction func confirmClicked(_ sender: Any) {
        self.passwordTextField.isError = false
        self.passwordTextField.errorMessage = nil

        let step = self.viewModel?.setCode(self.passwordTextField.value)
        guard step == .done else { return }
        viewModel?.isPinMatched { [weak self] isMatch in
            if isMatch {
                self?.viewModel?.done(completion: { shouldPop in
                    if shouldPop {
                        self?.dismissPinScreen()
                    }
                })
            } else {
                self?.displayErrorInTextField()
            }
        }
    }

    private func dismissPinScreen() {
        self.navigationController?.dismiss(animated: true)
    }

    private func displayErrorInTextField() {
        self.passwordTextField.isError = true
        self.passwordTextField.errorMessage = LocalString._pin_code_setup2_textfield_invalid_password
    }
}
