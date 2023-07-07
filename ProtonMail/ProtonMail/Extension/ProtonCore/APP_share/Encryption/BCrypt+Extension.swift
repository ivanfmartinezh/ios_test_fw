//
//  BCrypt+Extension.swift
//  Proton Mail - Created on 10/5/17.
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

import Foundation
import OpenPGP

func PMNBCrypt (password: String, salt: String) -> String {
    var hash_out: String = ""
    do {
        try ObjC.catchException {
            hash_out = PMNBCryptHash.hashString(password, salt: salt)
        }
    } catch {
        // TODO:: log error
    }
    return hash_out
}
