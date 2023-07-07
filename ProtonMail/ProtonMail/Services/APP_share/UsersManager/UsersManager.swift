//
//  UsersManager.swift
//  Proton Mail - Created on 8/14/19.
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
import GoLibs
#if !APP_EXTENSION
import LifetimeTracker
#endif
import PromiseKit
import ProtonCore_Challenge
import ProtonCore_DataModel
import ProtonCore_Doh
import ProtonCore_Keymaker
import ProtonCore_Networking
import ProtonCore_Services
import ProtonMailAnalytics

/// manager all the users and there services
class UsersManager: Service {
    enum Version: Int {
        static let version: Int = 1 // this is app cache version

        case ver0 = 0
        case ver1 = 1
    }

    // For Migrate protocol
    var latestVersion: Int

    /// saver for versioning
    let versionSaver: Saver<Int>

    enum CoderKey {
        // tracking the cache version added 1.12.0
        static let Version = "Last.Users.Manager.Version"

        // old
        static let keychainStore = "keychainStoreKeyProtectedWithMainKey"
        // new
        static let authKeychainStore = "authKeychainStoreKeyProtectedWithMainKey"
        // old
        static let userInfo = "userInfoKeyProtectedWithMainKey"
        // new
        static let usersInfo = "usersInfoKeyProtectedWithMainKey"

        // new one, check if user logged in already
        static let atLeastOneLoggedIn = "UsersManager.AtLeastoneLoggedIn"

        // set at least one password set
        static let mailboxPassword = "mailboxPasswordKeyProtectedWithMainKey"
        static let username = "usernameKeyProtectedWithMainKey"

        static let twoFAStatus = "twofaKey"
        static let userPasswordMode = "userPasswordModeKey"

        static let disconnectedUsers = "disconnectedUsers"
        static let mailSettingsStore = "mailSettingsKeyProtectedWithMainKey"
    }

    /// Server's config like url port path etc..
    var doh: DoHInterface

    private(set) var users: [UserManager] = [] {
        didSet {
            userCachedStatus.primaryUserSessionId = self.users.first?.authCredential.sessionID
        }
    }

    var firstUser: UserManager? {
        return self.users.first
    }

    var count: Int {
        return self.users.count
    }

    let internetConnectionStatusProvider: InternetConnectionStatusProvider

    // Used to check if the account is already being deleted.
    private(set) var loggingOutUserIDs: Set<UserID> = Set()
    private let userDataCache: CachedUserDataProvider
    private let userDefaultCache: SharedCacheBase
    private let keychain: Keychain

    #if !APP_EXTENSION
    private var encryptedSearchCache: EncryptedSearchUserCache {
        return sharedServices.get(by: EncryptedSearchUserDefaultCache.self)
    }
    #endif

    init(
        doh: DoHInterface,
        userDataCache: CachedUserDataProvider = UserDataCache(),
        internetConnectionStatusProvider: InternetConnectionStatusProvider = .init(),
        userDefaultCache: SharedCacheBase = .init(),
        keychain: Keychain = KeychainWrapper.keychain
    ) {
        self.doh = doh
        self.doh.status = userCachedStatus.isDohOn ? .on : .off
        /// for migrate
        self.latestVersion = Version.version
        self.versionSaver = UserDefaultsSaver<Int>(key: CoderKey.Version)
        self.internetConnectionStatusProvider = internetConnectionStatusProvider
        self.userDataCache = userDataCache
        self.userDefaultCache = userDefaultCache
        self.keychain = keychain
        setupValueTransforms()
        #if !APP_EXTENSION
        trackLifetime()
        #endif
    }

    /**
     add a new user after login

     - Parameter auth: auth credential
     - Parameter user: user information
     - Parameter mailSettings: mail settings of the user
     **/
    func add(auth: AuthCredential, user: UserInfo, mailSettings: MailSettings?) {
        self.cleanRandomKeyIfNeeded()
        let session = auth.sessionID
        let apiService = PMAPIService.createAPIService(
            doh: self.doh, sessionUID: session, challengeParametersProvider: .forAPIService(clientApp: .mail, challenge: PMChallenge())
        )
        apiService.serviceDelegate = self
        #if !APP_EXTENSION
        apiService.humanDelegate = HumanVerificationManager.shared.humanCheckHelper(apiService: apiService)
        apiService.forceUpgradeDelegate = ForceUpgradeManager.shared.forceUpgradeHelper

        // We've been seeing crashes caused by CoreDataService not being ready by the time a UserManager is instantiated.
        // Setting up the Core Data stack before the main key is available might mess up migration, however it's a lesser evil compared to a crash.
        (UIApplication.shared.delegate as? AppDelegate)?.setupCoreData()
        #endif

        let newUser = UserManager(
            api: apiService,
            userInfo: user,
            authCredential: auth,
            mailSettings: mailSettings,
            parent: self
        )
        self.add(newUser: newUser)
    }

    func add(newUser: UserManager) {
        newUser.delegate = self
        self.removeDisconnectedUser(.init(defaultDisplayName: newUser.defaultDisplayName,
                                          defaultEmail: newUser.defaultEmail,
                                          userID: newUser.userID.rawValue))
        self.users.append(newUser)

        self.save()
    }

    func isAllowedNewUser(userInfo: UserInfo) -> Bool {
        if numberOfFreeAccounts > 0, !userInfo.isPaid {
            return false
        }
        return true
    }

    func update(userInfo: UserInfo, for sessionID: String) {
        for user in users where user.isMatch(sessionID: sessionID) {
            user.update(userInfo: userInfo)
            user.save()
        }
    }

    func user(at index: Int) -> UserManager? {
        return users[safe: index]
    }

    func active(by sessionID: String) {
        guard let index = users.firstIndex(where: { $0.isMatch(sessionID: sessionID) }) else {
            return
        }
        firstUser?.resignAsActiveUser()
        let user = users.remove(at: index)
        users.insert(user, at: 0)
        save()
        firstUser?.becomeActiveUser()
    }

    func getUser(by sessionID: String) -> UserManager? {
        let found = self.users.filter { user -> Bool in
            user.isMatch(sessionID: sessionID)
        }
        guard let user = found.first else {
            return nil
        }
        return user
    }

    func getUser(by userId: UserID) -> UserManager? {
        let found = self.users.filter { user -> Bool in
            user.userID == userId
        }
        guard let user = found.first else {
            return nil
        }
        return user
    }

    func isExist(userID: UserID) -> Bool {
        return getUser(by: userID) != nil
    }

    // tempery mirgration. will change this to version check
    func hasUserName() -> Bool {
        return userDefaultCache.getShared().data(forKey: CoderKey.username) != nil
    }

    func tryRestore() {
        // try new version first
        guard keymaker.mainKey(by: RandomPinProtection.randomPin) != nil else {
            return
        }

        if let result = loadUserDataInLegacyFormatFromCache() {
            let oldAuth = result.auth
            let oldUserInfo = result.userInfo

            let user = createUserFromLegacyData(auth: oldAuth, userInfo: oldUserInfo)
            self.users.append(user)
            self.save()

            clearLegacyData()
        } else if let result = loadUserDataFromCache() {
            self.users.removeAll()

            for cachedUserData in result {
                let session = cachedUserData.authCredentials.sessionID
                let apiService = PMAPIService.createAPIService(
                    doh: self.doh,
                    sessionUID: session,
                    challengeParametersProvider: .forAPIService(clientApp: .mail, challenge: PMChallenge())
                )
                apiService.serviceDelegate = self
                #if !APP_EXTENSION
                apiService.humanDelegate = HumanVerificationManager.shared.humanCheckHelper(apiService: apiService)
                apiService.forceUpgradeDelegate = ForceUpgradeManager.shared.forceUpgradeHelper
                #endif
                let newUser = UserManager(
                    api: apiService,
                    userInfo: cachedUserData.userInfo,
                    authCredential: cachedUserData.authCredentials,
                    mailSettings: cachedUserData.mailSettings,
                    parent: self
                )
                newUser.delegate = self
                self.users.append(newUser)
            }
        }

        self.users.forEach { $0.fetchUserInfo() }
        self.users.first?.cacheService.cleanSoftDeletedMessagesAndConversation()
        self.loggedIn()
    }

    func save() {
        guard let mainKey = keymaker.mainKey(by: RandomPinProtection.randomPin) else {
            return
        }

        let authList = self.users.compactMap { $0.authCredential }
        userCachedStatus.isForcedLogout = false
        guard let lockedAuth = try? Locked<[AuthCredential]>(clearValue: authList, with: mainKey)
        else {
            return
        }
        userDefaultCache.getShared().setValue(lockedAuth.encryptedValue, forKey: CoderKey.authKeychainStore)

        let userList = self.users.compactMap { $0.userInfo }
        guard let lockedUsers = try? Locked<[UserInfo]>(clearValue: userList, with: mainKey) else {
            return
        }
        // Check MAILIOS-854, MAILIOS-1208
        userDefaultCache.getShared().set(lockedUsers.encryptedValue, forKey: CoderKey.usersInfo)
        userDefaultCache.getShared().synchronize()
        keychain.remove(forKey: CoderKey.authKeychainStore)

        var mailSettingsList: [String: MailSettings] = [:]
        users.forEach { user in
            mailSettingsList[user.userID.rawValue] = user.mailSettings
        }
        if !mailSettingsList.isEmpty,
           let lockedMailSettings = try? Locked<[String: MailSettings]>(clearValue: mailSettingsList, with: mainKey) {
            userDefaultCache.getShared().set(lockedMailSettings.encryptedValue,
                                             forKey: CoderKey.mailSettingsStore)
        } else {
            userDefaultCache.getShared().remove(forKey: CoderKey.mailSettingsStore)
        }
    }
}

extension UsersManager: UserManagerSave {
    func onSave() {
        DispatchQueue.main.async {
            self.save()
        }
    }
}

/// cache login check
extension UsersManager {
    func launchCleanUpIfNeeded() {}

    func logout(user: UserManager,
                shouldShowAccountSwitchAlert: Bool = false,
                completion: (() -> Void)?) {
        var isPrimaryAccountLogout = false
        loggingOutUserIDs.insert(user.userID)
        user.cleanUp().ensure {
            defer {
                self.loggingOutUserIDs.remove(user.userID)
            }
            guard let userToDelete = self.users.first(where: { $0.userID == user.userID }) else {
                self.addDisconnectedUserIfNeeded(user: user)
                completion?()
                return
            }

            if let primary = self.users.first, primary.isMatch(sessionID: userToDelete.authCredential.sessionID) {
                self.remove(user: userToDelete)
                isPrimaryAccountLogout = true
            } else {
                self.remove(user: userToDelete)
            }

            if self.users.isEmpty {
                _ = self.clean().cauterize()
            } else if shouldShowAccountSwitchAlert {
                String(format: LocalString._signout_account_switched_when_token_revoked,
                       arguments: [userToDelete.defaultEmail,
                                   self.users.first?.defaultEmail ?? ""]).alertToast()
            }

            if isPrimaryAccountLogout && user.userInfo.delinquentParsed.isAvailable {
                NotificationCenter.default.post(name: Notification.Name.didPrimaryAccountLogout, object: nil)
            }
            #if !APP_EXTENSION
            ImageProxyCache.shared.purge()
            SenderImageCache.shared.purge()
            #endif
            completion?()
        }.cauterize()
    }

    @discardableResult
    func addDisconnectedUserIfNeeded(user: UserManager) -> Bool {
        if !self.disconnectedUsers.contains(where: { $0.userID == user.userInfo.userId }) {
            let logoutUser = DisconnectedUserHandle(defaultDisplayName: user.defaultDisplayName,
                                                    defaultEmail: user.defaultEmail,
                                                    userID: user.userInfo.userId)
            self.disconnectedUsers.insert(logoutUser, at: 0)
            self.save()
            return true
        }
        return false
    }

    func remove(user: UserManager) {
        if let nextFirst = self.users.first(where: { !$0.isMatch(sessionID: user.authCredential.sessionID) }) {
            self.active(by: nextFirst.authCredential.sessionID)
        }
        if !disconnectedUsers.contains(where: { $0.userID == user.userInfo.userId }) {
            let logoutUser = DisconnectedUserHandle(defaultDisplayName: user.defaultDisplayName,
                                                    defaultEmail: user.defaultEmail,
                                                    userID: user.userInfo.userId)
            self.disconnectedUsers.insert(logoutUser, at: 0)
        }
        self.users.removeAll(where: { $0.isMatch(sessionID: user.authCredential.sessionID) })
        self.save()
    }

    func logoutAfterAccountDeletion(user: UserManager) {
        logout(user: user, shouldShowAccountSwitchAlert: true, completion: {
            guard let user = self.disconnectedUsers.first(where: { $0.userID == user.userInfo.userId }) else { return }
            self.removeDisconnectedUser(user)
        })
    }

    func clean() -> Promise<Void> {
        return UserManager.cleanUpAll().ensure {
            try? sharedServices.get(by: CoreDataService.self).rollbackAllContexts()

            self.users = []
            self.save()

            self.userDefaultCache.getShared().remove(forKey: CoderKey.usersInfo)
            self.userDefaultCache.getShared().remove(forKey: CoderKey.authKeychainStore)
            self.keychain.remove(forKey: CoderKey.keychainStore)
            self.keychain.remove(forKey: CoderKey.authKeychainStore)
            self.keychain.remove(forKey: CoderKey.atLeastOneLoggedIn)
            self.keychain.remove(forKey: CoderKey.disconnectedUsers)

            self.currentVersion = self.latestVersion

            userCachedStatus.signOut()
            userCachedStatus.cleanGlobal()

            #if !APP_EXTENSION
            self.encryptedSearchCache.cleanGlobal()
            #endif

            if !ProcessInfo.isRunningUnitTests {
                keymaker.wipeMainKey()
            }
            // good opportunity to remove all temp folders
            FileManager.default.cleanTemporaryDirectory()
            // some tests are messed up without tmp folder, so let's keep it for consistency
            #if targetEnvironment(simulator)
            try? FileManager.default
                .createDirectory(at: FileManager.default.temporaryDirectory,
                                 withIntermediateDirectories: true,
                                 attributes:
                                    nil)
            #endif

            if !ProcessInfo.isRunningUnitTests {
                NotificationCenter.default.post(name: Notification.Name.didSignOut, object: self)
            }
        }
    }

    func hasUsers() -> Bool {
        // Have this value after 1.12.0
        let hasUsersInfo = userDefaultCache.getShared().value(forKey: CoderKey.usersInfo) != nil

        // Workaround to fix MAILIOS-150
        // Method that checks signin or not before 1.11.17
        let isMailboxPasswordStored = keychain.data(forKey: CoderKey.mailboxPassword) != nil
        let isSignIn = hasUserName() && isMailboxPasswordStored

        let authKeychainStore = keychain.data(forKey: CoderKey.authKeychainStore)
        let authUserDefaultStore = userDefaultCache.getShared().data(forKey: CoderKey.authKeychainStore)

        let hasUsers = (authKeychainStore != nil || authUserDefaultStore != nil) && (hasUsersInfo || isSignIn)

        let message = """
        UsersManager.hasUsers \(hasUsers) - \
        authKeychainStore: \(authKeychainStore != nil); authUserDefaultStore: \(authUserDefaultStore != nil); \
        hasUsersInfo: \(hasUsersInfo); isSignIn: \(isSignIn)
        """
        Breadcrumbs.shared.add(message: message, to: .randomLogout)

        return hasUsers
    }

    var isPasswordStored: Bool {
        return keychain.data(forKey: CoderKey.mailboxPassword) != nil ||
            keychain.string(forKey: CoderKey.atLeastOneLoggedIn) != nil
    }

    var isMailboxPasswordStored: Bool {
        return keychain.string(forKey: CoderKey.atLeastOneLoggedIn) != nil
    }

    func loggedIn() {
        keychain.set("LoggedIn", forKey: CoderKey.atLeastOneLoggedIn)
    }

    struct CachedUserData {
        let authCredentials: AuthCredential
        let userInfo: UserInfo
        let mailSettings: MailSettings?
    }

    private func loadUserDataFromCache() -> [CachedUserData]? {
        guard let mainKey = keymaker.mainKey(by: RandomPinProtection.randomPin) else {
            return nil
        }
        let authDataInUserDefault = userDefaultCache.getShared().data(forKey: CoderKey.authKeychainStore)
        let authDataInKeyChain = keychain.data(forKey: CoderKey.authKeychainStore)
        guard let encryptedAuthData = authDataInUserDefault ?? authDataInKeyChain else {
            return nil
        }
        let lockedAuthData = Locked<[AuthCredential]>(encryptedValue: encryptedAuthData)
        guard let authCredentials: [AuthCredential] = try? lockedAuthData.unlock(with: mainKey) else {
            userDefaultCache.getShared().remove(forKey: CoderKey.authKeychainStore)
            keychain.remove(forKey: CoderKey.authKeychainStore)
            return nil
        }

        guard let encryptedUserData = userDefaultCache.getShared().data(forKey: CoderKey.usersInfo) else {
            return nil
        }
        let lockedUserInfos = Locked<[UserInfo]>(encryptedValue: encryptedUserData)
        guard let userInfos = try? lockedUserInfos.unlock(with: mainKey) else {
            return nil
        }
        guard userInfos.count == authCredentials.count else {
            return nil
        }

        var mailSettings: [String: MailSettings] = [:]
        if let encryptedMailSettings = userDefaultCache.getShared().data(forKey: CoderKey.mailSettingsStore) {
            let lockedMailSettings = Locked<[String: MailSettings]>(encryptedValue: encryptedMailSettings)
            mailSettings = (try? lockedMailSettings.unlock(with: mainKey)) ?? [:]
        }

        // Check if the existing users is the same as the users stored on the device
        let userIDs = userInfos.map { $0.userId }
        let existingUserIDs = users.map { $0.userID.rawValue }
        if !existingUserIDs.isEmpty,
           existingUserIDs.count == userIDs.count,
           !existingUserIDs.map({ userIDs.contains($0) }).contains(false) {
               // restore is not needed.
               return nil
           }

        var result: [CachedUserData] = []

        // Take the order of the authCredentials as a reference, reorder the data of userInfos and mailSettings.
        for authCredential in authCredentials {
            if let userInfo = userInfos
                .first(where: { $0.userId == authCredential.userID }) {
                let mailSetting = mailSettings[authCredential.userID]
                result.append(.init(authCredentials: authCredential,
                                    userInfo: userInfo,
                                    mailSettings: mailSetting))
            }
        }

        return result
    }
}

// MARK: Disconnect user functions
extension UsersManager {
    struct DisconnectedUserHandle: Codable, Equatable {
        var defaultDisplayName: String
        var defaultEmail: String
        var userID: String

        static func == (lhv: DisconnectedUserHandle, rhv: DisconnectedUserHandle) -> Bool {
            return lhv.userID == rhv.userID
        }
    }

    func removeDisconnectedUser(_ handle: DisconnectedUserHandle) {
        self.disconnectedUsers.removeAll(where: { $0 == handle })
    }

    /* logged out users that should be visible in the Account Manager screen for faster log in.
     Persisted until logout of last user, protected with MainKey. */
    var disconnectedUsers: [DisconnectedUserHandle] {
        get {
            userDataCache.fetchDisconnectedUsers()
        }
        set {
            userDataCache.set(disconnectedUsers: newValue)
        }
    }

    var numberOfFreeAccounts: Int {
        self.users.filter { !$0.isPaid }.count
    }
}

// MARK: - Legacy format user data
extension UsersManager {
    private func createUserFromLegacyData(auth: AuthCredential, userInfo: UserInfo) -> UserManager {
        let sessionID = auth.sessionID
        let apiService = PMAPIService.createAPIService(
            doh: doh,
            sessionUID: sessionID,
            challengeParametersProvider: .forAPIService(clientApp: .mail, challenge: PMChallenge())
        )
        apiService.serviceDelegate = self
#if !APP_EXTENSION
        apiService.humanDelegate = HumanVerificationManager.shared.humanCheckHelper(apiService: apiService)
        apiService.forceUpgradeDelegate = ForceUpgradeManager.shared.forceUpgradeHelper
#endif
        if let oldMailBoxPassword = oldMailboxPassword() {
            auth.udpate(password: oldMailBoxPassword)
        }
        userInfo.twoFactor = userDefaultCache.getShared().integer(forKey: CoderKey.twoFAStatus)
        userInfo.passwordMode = userDefaultCache.getShared().integer(forKey: CoderKey.userPasswordMode)
        let user = UserManager(
            api: apiService,
            userInfo: userInfo,
            authCredential: auth,
            mailSettings: nil,
            parent: self
        )
        user.delegate = self
        return user
    }

    /// Load user data in the format of legacy app like the version without multi-user support.
    /// - Returns: tuple that contains auth and user info.
    private func loadUserDataInLegacyFormatFromCache() -> (auth: AuthCredential, userInfo: UserInfo)? {
        guard let auth = oldAuthFetch(), let userInfo = oldUserInfo() else {
            return nil
        }
        return (auth, userInfo)
    }

    func clearLegacyData() {
        userDefaultCache.getShared().remove(forKey: CoderKey.twoFAStatus)
        userDefaultCache.getShared().remove(forKey: CoderKey.userPasswordMode)
        userDefaultCache.getShared().remove(forKey: CoderKey.username)
        userDefaultCache.getShared().remove(forKey: CoderKey.userInfo)
        keychain.remove(forKey: CoderKey.keychainStore)
    }

    private func oldUserInfo() -> UserInfo? {
        guard let mainKey = keymaker.mainKey(by: RandomPinProtection.randomPin),
              let cypherData = userDefaultCache.getShared().data(forKey: CoderKey.userInfo)
        else {
            return nil
        }

        let locked = Locked<UserInfo>(encryptedValue: cypherData)
        return try? locked.unlock(with: mainKey)
    }

    private func oldAuthFetch() -> AuthCredential? {
        guard let mainKey = keymaker.mainKey(by: RandomPinProtection.randomPin),
              let encryptedData = keychain.data(forKey: CoderKey.keychainStore),
              case let locked = Locked<Data>(encryptedValue: encryptedData),
              let data = try? locked.unlock(with: mainKey),
              let authCredential = AuthCredential.unarchive(data: data as NSData)
        else {
            return nil
        }
        return authCredential
    }

    private func oldMailboxPassword() -> String? {
        guard let cypherBits = keychain.data(forKey: CoderKey.mailboxPassword),
              let key = keymaker.mainKey(by: RandomPinProtection.randomPin)
        else {
            return nil
        }
        let locked = Locked<String>(encryptedValue: cypherBits)
        return try? locked.unlock(with: key)
    }
}

// MARK: - Legacy crypto functions
extension UsersManager {
    // swiftlint:disable cyclomatic_complexity function_body_length
    func migrate_0_1() -> Bool {
        guard let mainKey = keymaker.mainKey(by: RandomPinProtection.randomPin) else {
            return false
        }

        if let legacyPwd = self.oldMailboxPasswordLegacy(),
           let locked = try? Locked(clearValue: legacyPwd, with: mainKey) {
            keychain.set(locked.encryptedValue, forKey: CoderKey.mailboxPassword)
        }
        if let legacyName = oldUserNameLegacy(), let locked = try? Locked(clearValue: legacyName, with: mainKey) {
            keychain.set(locked.encryptedValue, forKey: CoderKey.username)
        }
        userCachedStatus.migrateLegacy()

        // check the older auth and older user format first
        if let oldAuth = oldAuthFetchLegacy(), let user = oldUserInfoLegacy() {
            let session = oldAuth.sessionID
            let apiService = PMAPIService.createAPIService(
                doh: self.doh, sessionUID: session, challengeParametersProvider: .forAPIService(clientApp: .mail, challenge: PMChallenge())
            )
            apiService.serviceDelegate = self
            #if !APP_EXTENSION
            apiService.humanDelegate = HumanVerificationManager.shared.humanCheckHelper(apiService: apiService)
            apiService.forceUpgradeDelegate = ForceUpgradeManager.shared.forceUpgradeHelper
            #endif
            let newUser = UserManager(
                api: apiService,
                userInfo: user,
                authCredential: oldAuth,
                mailSettings: nil,
                parent: self
            )
            newUser.delegate = self
            if let pwd = oldMailboxPassword() {
                oldAuth.udpate(password: pwd)
            }
            user.twoFactor = userDefaultCache.getShared().integer(forKey: CoderKey.twoFAStatus)
            user.passwordMode = userDefaultCache.getShared().integer(forKey: CoderKey.userPasswordMode)
            self.users.append(newUser)
            self.save()
            // Then clear lagcy
            userDefaultCache.getShared().remove(forKey: CoderKey.username)
            keychain.remove(forKey: CoderKey.keychainStore)
            // save to newer version.
            return true
        } else {
            guard let encryptedAuthData = keychain.data(forKey: CoderKey.authKeychainStore) else {
                return false
            }
            let authlocked = Locked<[AuthCredential]>(encryptedValue: encryptedAuthData)
            guard let auths = try? authlocked.lagcyUnlock(with: mainKey) else {
                return false
            }

            guard let encryptedUsersData = userDefaultCache.getShared().data(forKey: CoderKey.usersInfo) else {
                return false
            }

            let userslocked = Locked<[UserInfo]>(encryptedValue: encryptedUsersData)
            guard let userinfos = try? userslocked.lagcyUnlock(with: mainKey) else {
                return false
            }

            guard userinfos.count == auths.count else {
                return false
            }

            if !self.users.isEmpty {
                return false
            }

            for (auth, user) in zip(auths, userinfos) {
                let session = auth.sessionID
                let apiService = PMAPIService.createAPIService(
                    doh: self.doh,
                    sessionUID: session,
                    challengeParametersProvider: .forAPIService(clientApp: .mail, challenge: PMChallenge())
                )
                apiService.serviceDelegate = self
                #if !APP_EXTENSION
                apiService.humanDelegate = HumanVerificationManager.shared.humanCheckHelper(apiService: apiService)
                apiService.forceUpgradeDelegate = ForceUpgradeManager.shared.forceUpgradeHelper
                #endif
                let newUser = UserManager(
                    api: apiService,
                    userInfo: user,
                    authCredential: auth,
                    mailSettings: nil,
                    parent: self
                )
                newUser.delegate = self
                self.users.append(newUser)
            }

            // save to the newer version
            self.save()

            let disconnectedUsers = self.disconnectedUsersLegacy()
            if let data = try? JSONEncoder().encode(disconnectedUsers),
               let locked = try? Locked(clearValue: data, with: mainKey)
            {
                keychain.set(locked.encryptedValue, forKey: CoderKey.disconnectedUsers)
            }
            return true
        }
    }

    func oldAuthFetchLegacy() -> AuthCredential? {
        guard let mainKey = keymaker.mainKey(by: RandomPinProtection.randomPin),
              let encryptedData = keychain.data(forKey: CoderKey.keychainStore),
              case let locked = Locked<Data>(encryptedValue: encryptedData),
              let data = try? locked.lagcyUnlock(with: mainKey),
              let authCredential = AuthCredential.unarchive(data: data as NSData)
        else {
            return nil
        }
        return authCredential
    }

    private func oldUserInfoLegacy() -> UserInfo? {
        guard let mainKey = keymaker.mainKey(by: RandomPinProtection.randomPin),
              let cypherData = userDefaultCache.getShared().data(forKey: CoderKey.userInfo)
        else {
            return nil
        }
        let locked = Locked<UserInfo>(encryptedValue: cypherData)
        return try? locked.lagcyUnlock(with: mainKey)
    }

    private func oldMailboxPasswordLegacy() -> String? {
        guard let cypherBits = keychain.data(forKey: CoderKey.mailboxPassword),
              let key = keymaker.mainKey(by: RandomPinProtection.randomPin)
        else {
            return nil
        }
        let locked = Locked<String>(encryptedValue: cypherBits)
        return try? locked.lagcyUnlock(with: key)
    }

    private func oldUserNameLegacy() -> String? {
        guard let mainKey = keymaker.mainKey(by: RandomPinProtection.randomPin),
              let cypherData = userDefaultCache.getShared().data(forKey: CoderKey.username)
        else {
            return nil
        }

        let locked = Locked<String>(encryptedValue: cypherData)
        return try? locked.lagcyUnlock(with: mainKey)
    }

    func disconnectedUsersLegacy() -> [DisconnectedUserHandle] {
        // this locking/unlocking can be refactored to be @propertyWrapper on Swift 5.1
        guard let mainKey = keymaker.mainKey(by: RandomPinProtection.randomPin),
              let encryptedData = keychain.data(forKey: CoderKey.disconnectedUsers),
              case let locked = Locked<Data>(encryptedValue: encryptedData),
              let data = try? locked.lagcyUnlock(with: mainKey),
              let loggedOutUserHandles = try? JSONDecoder().decode([DisconnectedUserHandle].self, from: data)
        else {
            return []
        }
        return loggedOutUserHandles
    }

    func cleanRandomKeyIfNeeded() {
        // Random key status is in the key chain
        // That means if the users delete the app
        // The key chain could keep the old data
        // If there is not user data, remove the random protection
        let dataInUserDefault = userDefaultCache.getShared().data(forKey: CoderKey.authKeychainStore)
        let dataInKeyChain = keychain.data(forKey: CoderKey.authKeychainStore)
        guard dataInUserDefault != nil || dataInKeyChain != nil,
              !self.users.isEmpty
        else {
            if let randomProtection = RandomPinProtection.randomPin {
                keymaker.deactivate(randomProtection)
            }
            userCachedStatus.keymakerRandomkey = nil
            RandomPinProtection.removeCyphertext(from: keychain)
            return
        }
    }
}

// MARK: - APIServiceDelegate
extension UsersManager: APIServiceDelegate {
    var additionalHeaders: [String: String]? { nil }

    var locale: String {
        if let local = LanguageManager().currentLanguageCode() {
            return local
        } else {
            return Constants.defaultLocale
        }
    }

    func isReachable() -> Bool {
        return internetConnectionStatusProvider.currentStatus != .notConnected
    }

    func onUpdate(serverTime: Int64) {
        #if !APP_EXTENSION
        let processInfo = userCachedStatus
        #else
        let processInfo = userCachedStatus as? SystemUpTimeProtocol
        #endif
        MailCrypto.updateTime(serverTime, processInfo: processInfo)
    }

    var appVersion: String {
        Constants.App.appVersion
    }

    var userAgent: String? {
        UserAgent.default.ua
    }

    func onDohTroubleshot() {}
}

#if !APP_EXTENSION
extension UsersManager: LifetimeTrackable {
    static var lifetimeConfiguration: LifetimeConfiguration {
        .init(maxCount: 1)
    }
}
#endif
