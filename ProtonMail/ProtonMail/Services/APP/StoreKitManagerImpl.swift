//
//  StoreKitManagerImpl.swift
//  Proton Mail - Created on 04/02/2021.
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
import ProtonCore_Payments
import ProtonCore_Services

class StoreKitManagerImpl: StoreKitManagerDelegate, Service {
    var tokenStorage: PaymentTokenStorage? {
        return nil
    }

    var isUnlocked: Bool {
        return UnlockManager.shared.isUnlocked()
    }

    var isSignedIn: Bool {
        return sharedServices.get(by: UsersManager.self).hasUsers()
    }

    var activeUsername: String? {
        return sharedServices.get(by: UsersManager.self).firstUser?.defaultEmail
    }

    var userId: String? {
        return sharedServices.get(by: UsersManager.self).firstUser?.userInfo.userId
    }
}
