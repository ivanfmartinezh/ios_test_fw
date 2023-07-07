//
//  ExpirationView.swift
//  Proton Mail - Created on 3/22/16.
//
//
//  Copyright (c) 2019 Proton AG
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

import UIKit

// @IBDesignable
class ExpirationView: PMView {

    @IBOutlet weak var expirationLabel: UILabel!

    override func getNibName() -> String {
        return "ExpirationView"
    }

    func setExpirationTime(_ offset: Int) {
        let (d, h, m, s) = durationsBySecond(seconds: offset)
        if offset <= 0 {
            expirationLabel.text = LocalString._message_expired
        } else {
            expirationLabel.text = String(format: LocalString._expires_in_days_hours_mins_seconds, d, h, m, s)
        }
    }

    func durationsBySecond(seconds s: Int) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        return (s / (24 * 3600), (s % (24 * 3600)) / 3600, s % 3600 / 60, s % 60)
    }
}
