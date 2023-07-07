//
//  UnlockManager.swift
//  Proton Mail - Created on 02/11/2018.
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
import LocalAuthentication
import ProtonCore_Keymaker
import ProtonMailAnalytics
#if !APP_EXTENSION
import LifetimeTracker
import ProtonCore_Payments
#endif

enum SignInUIFlow: Int {
    case requirePin = 0
    case requireTouchID = 1
    case restore = 2
}

protocol CacheStatusInject {
    var isPinCodeEnabled: Bool { get }
    var isTouchIDEnabled: Bool { get }
    var isAppKeyEnabled: Bool { get }
    var pinFailedCount: Int { get set }

    /// Returns `true` if there is some kind of protection to access the app, but
    /// the main key is accessible without the user having to interact to unlock the app.
    var isAppLockedAndAppKeyDisabled: Bool { get }

    /// Returns `true` if there is some kind of protection to access the app, and
    /// the main key is only accessible if user interacts to unlock the app (e.g. enters pin, uses FaceID,...)
    var isAppLockedAndAppKeyEnabled: Bool { get }
}

protocol UnlockManagerDelegate: AnyObject {
    func cleanAll()
    func isUserStored() -> Bool
    func isMailboxPasswordStored(forUser uid: String?) -> Bool
    func setupCoreData()
}

class UnlockManager: Service {
    var cacheStatus: CacheStatusInject
    private var mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    unowned let delegate: UnlockManagerDelegate

    static var shared: UnlockManager {
        return sharedServices.get(by: UnlockManager.self)
    }

    init(cacheStatus: CacheStatusInject, delegate: UnlockManagerDelegate) {
        self.cacheStatus = cacheStatus
        self.delegate = delegate

        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
        #if !APP_EXTENSION
        trackLifetime()
        #endif
    }

    internal func isUnlocked() -> Bool {
        return self.validate(mainKey: keymaker.mainKey(by: nil))
    }

    internal func getUnlockFlow() -> SignInUIFlow {
        migrateProtectionSetting()
        if cacheStatus.isPinCodeEnabled {
            return SignInUIFlow.requirePin
        }
        if cacheStatus.isTouchIDEnabled {
            return SignInUIFlow.requireTouchID
        }
        return SignInUIFlow.restore
    }

    internal func match(userInputPin: String, completion: @escaping (Bool) -> Void) {
        guard !userInputPin.isEmpty else {
            cacheStatus.pinFailedCount += 1
            completion(false)
            return
        }
        keymaker.obtainMainKey(with: PinProtection(pin: userInputPin)) { key in
            guard self.validate(mainKey: key) else {
                userCachedStatus.pinFailedCount += 1
                completion(false)
                return
            }
            self.cacheStatus.pinFailedCount = 0
            completion(true)
        }
    }

    private func migrateProtectionSetting() {
        if cacheStatus.isPinCodeEnabled && cacheStatus.isTouchIDEnabled {
            keymaker.deactivate(PinProtection(pin: "doesnotmatter"))
        }
    }

    private func validate(mainKey: MainKey?) -> Bool {
        guard let _ = mainKey else { // currently enough: key is Array and will be nil in case it was unlocked incorrectly
            keymaker.lockTheApp() // remember to remove invalid key in case validation will become more complex
            return false
        }
        return true
    }

    internal func biometricAuthentication(requestMailboxPassword: @escaping () -> Void) {
        self.biometricAuthentication(afterBioAuthPassed: { self.unlockIfRememberedCredentials(requestMailboxPassword: requestMailboxPassword) })
    }

    var isRequestingBiometricAuthentication: Bool = false
    internal func biometricAuthentication(afterBioAuthPassed: @escaping () -> Void) {
        var error: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            assert(false, "LAContext canEvaluatePolicy is false")
            return
        }

        guard !self.isRequestingBiometricAuthentication else { return }
        self.isRequestingBiometricAuthentication = true
        keymaker.obtainMainKey(with: BioProtection()) { key in
            defer {
                self.isRequestingBiometricAuthentication = false
            }
            guard self.validate(mainKey: key) else { return }
            afterBioAuthPassed()
        }
    }

    internal func initiateUnlock(flow signinFlow: SignInUIFlow,
                                 requestPin: @escaping () -> Void,
                                 requestMailboxPassword: @escaping () -> Void) {
        if userCachedStatus.isAppLockedAndAppKeyDisabled {
            unlockIfRememberedCredentials(requestMailboxPassword: requestMailboxPassword)
        } else {
            switch signinFlow {
            case .requirePin:
                requestPin()

            case .requireTouchID:
                self.biometricAuthentication(requestMailboxPassword: requestMailboxPassword) // will send message

            case .restore:
                self.unlockIfRememberedCredentials(requestMailboxPassword: requestMailboxPassword)
            }
        }
    }

    internal func unlockIfRememberedCredentials(forUser uid: String? = nil,
                                                requestMailboxPassword: () -> Void,
                                                unlockFailed: (() -> Void)? = nil,
                                                unlocked: (() -> Void)? = nil) {
        Breadcrumbs.shared.add(message: "UnlockManager.unlockIfRememberedCredentials called", to: .randomLogout)
        guard keymaker.mainKeyExists(), self.delegate.isUserStored() else {
            delegate.setupCoreData()
            delegate.cleanAll()
            unlockFailed?()
            return
        }

        guard self.delegate.isMailboxPasswordStored(forUser: uid) else { // this will provoke mainKey obtention
            delegate.setupCoreData()
            requestMailboxPassword()
            return
        }

        delegate.setupCoreData()

        cacheStatus.pinFailedCount = 0

        // need move to delegation
        let usersManager = sharedServices.get(by: UsersManager.self)
        usersManager.run()
        usersManager.tryRestore()

        #if !APP_EXTENSION
        sharedServices.get(by: UsersManager.self).users.forEach {
            $0.messageService.injectTransientValuesIntoMessages()
        }
        if let primaryUser = usersManager.firstUser {
            primaryUser.payments.storeKitManager.retryProcessingAllPendingTransactions(finishHandler: nil)
        }
        #endif

        if !userCachedStatus.isTouchIDEnabled && !userCachedStatus.isPinCodeEnabled {
            NotificationCenter.default.post(name: Notification.Name.didUnlock, object: nil) // needed for app unlock
        }
        unlocked?()
    }
}

#if !APP_EXTENSION
extension UnlockManager: LifetimeTrackable {
    static var lifetimeConfiguration: LifetimeConfiguration {
        .init(maxCount: 1)
    }
}
#endif
