//
//  SignInManager.swift
//  Proton Mail - Created on 18/10/2018.
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
import LifetimeTracker
import ProtonCore_Crypto
import ProtonCore_DataModel
import ProtonCore_Login
import ProtonCore_Networking
import ProtonCore_Services

class SignInManager: Service {
    let usersManager: UsersManager
    let queueHandlerRegister: QueueHandlerRegister
    private var contactCacheStatus: ContactCacheStatusProtocol
    private let updateSwipeAction: UpdateSwipeActionDuringLoginUseCase

    init(usersManager: UsersManager,
         contactCacheStatus: ContactCacheStatusProtocol,
         queueHandlerRegister: QueueHandlerRegister,
         updateSwipeActionUseCase: UpdateSwipeActionDuringLoginUseCase)
    {
        self.usersManager = usersManager
        self.contactCacheStatus = contactCacheStatus
        self.queueHandlerRegister = queueHandlerRegister
        self.updateSwipeAction = updateSwipeActionUseCase
        trackLifetime()
    }

    internal func mailboxPassword(from cleartextPassword: Passphrase, auth: AuthCredential) -> Passphrase {
        var mailboxPassword = cleartextPassword
        if let keysalt = auth.passwordKeySalt, !keysalt.isEmpty {
            let keysalt_byte: Data = keysalt.decodeBase64()
            mailboxPassword = PasswordUtils.getMailboxPassword(cleartextPassword, salt: keysalt_byte)
        }
        return mailboxPassword
    }

    func saveLoginData(loginData userData: LoginData) -> LoginDataSavingResult {
        let userInfo = userData.toUserInfo
        let auth = userData.credential

        if self.usersManager.isExist(userID: UserID(rawValue: userInfo.userId)) {
            return .errorOccurred
        }

        guard self.usersManager.isAllowedNewUser(userInfo: userInfo) else {
            return .freeAccountsLimitReached
        }

        if usersManager.count == 0 {
            userCachedStatus.initialUserLoggedInVersion = Bundle.main.majorVersion
        }

        // The spotlight views are only shown when user updates from old version.
        // When a user logs into a version, they should not see the spotlight for any feature that is enabled in that version at that time.
        for feature in SpotlightableFeatureKey.allCases where feature.isFeatureEnabledLocallyByDefault {
            userCachedStatus.markSpotlight(for: feature, asSeen: true, byUserWith: UserID(userInfo.userId))
        }

        self.usersManager.add(auth: auth, user: userInfo, mailSettings: .init())
        self.usersManager.firstUser?.appRatingService.preconditionEventDidOccur(.userSignIn)

        self.usersManager.loggedIn()
        self.usersManager.active(by: auth.sessionID)
        self.contactCacheStatus.contactsCached = 0

        return .success
    }

    func finalizeSignIn(loginData userData: LoginData,
                        onError: @escaping (NSError) -> Void,
                        showSkeleton: () -> Void,
                        tryUnlock: @escaping () -> Void)
    {
        let auth = userData.credential
        let userInfo = userData.toUserInfo

        guard let user = usersManager.getUser(by: auth.sessionID),
              let activeUser = usersManager.firstUser else {
            assertionFailure("Signin flow was misconfigured - you should be able to find a user.")
            return
        }

        showSkeleton()

        if UserInfo.isBlockSenderEnabled {
            user.blockedSenderCacheUpdater.requestUpdate()
        }

        let userDataService = user.userService
        userDataService.fetchSettings(
            userInfo: userInfo,
            auth: auth
        ).done(on: .main) { [weak self] result in
            guard let self = self else { return }
            let userInfo = result.0
            let mailSettings = result.1
            self.updateSwipeAction.execute(
                activeUserInfo: activeUser.userInfo,
                newUserInfo: user.userInfo,
                newUserApiService: user.apiService
            ) { [weak self] in
                guard let self = self else { return }
                user.mailSettings = mailSettings
                self.usersManager.update(userInfo: userInfo, for: auth.sessionID)

                guard userInfo.delinquentParsed.isAvailable else {
                    self.queueHandlerRegister.unregisterHandler(for: user.userID)
                    self.usersManager.logout(user: user, shouldShowAccountSwitchAlert: false) {
                        onError(NSError(domain: "", code: 0, localizedDescription: LocalString._general_account_disabled_non_payment))
                    }
                    return
                }

                tryUnlock()
            }
        }.catch(on: .main) { [weak self] error in
            self?.queueHandlerRegister.unregisterHandler(for: user.userID)
            _ = self?.usersManager.logout(user: user, completion: {
                onError(error as NSError)
            })
            // this will happen if fetchUserInfo fails - maybe because of connectivity issues
        }
    }
}

extension SignInManager {
    enum LoginDataSavingResult {
        case success
        case freeAccountsLimitReached
        case errorOccurred
    }
}

extension SignInManager: LifetimeTrackable {
    static var lifetimeConfiguration: LifetimeConfiguration {
        .init(maxCount: 1)
    }
}

private extension SpotlightableFeatureKey {
    var isFeatureEnabledLocallyByDefault: Bool {
        switch self {
        case .scheduledSend:
            return true
        case .toolbarCustomization:
            return UserInfo.isToolbarCustomizationEnable
        case .messageSwipeNavigation:
            return UserInfo.isConversationSwipeEnabled
        case .encryptedSearchAvailable:
            return false
        }
    }
}
