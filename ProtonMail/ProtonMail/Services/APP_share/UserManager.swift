//
//  UserManager.swift
//  Proton Mail - Created on 8/15/19.
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
import PromiseKit
import ProtonCore_Authentication
import ProtonCore_Crypto
import ProtonCore_DataModel
import ProtonCore_Networking
#if !APP_EXTENSION
import ProtonCore_Payments
#endif
import ProtonCore_Services

/// TODO:: this is temp
protocol UserDataSource: AnyObject {
    var mailboxPassword: Passphrase { get }
    var addressKeys: [Key] { get }
    var userPrivateKeys: [ArmoredKey] { get }
    var userInfo: UserInfo { get }
    var authCredential: AuthCredential { get }
    var userID: UserID { get }

    func getAddressKey(address_id: String) -> Key?
    func getAllAddressKey(address_id: String) -> [Key]?
    func getAddressPrivKey(address_id: String) -> String
}

protocol UserManagerSave: AnyObject {
    func onSave()
}

// protocol created to be able to decouple UserManager from other entities
protocol UserManagerSaveAction: AnyObject {
    func save()
}

class UserManager: Service {
    private let authCredentialAccessQueue = DispatchQueue(label: "com.protonmail.user_manager.auth_access_queue", qos: .userInitiated)

    var userID: UserID {
        return UserID(rawValue: self.userInfo.userId)
    }

    func cleanUp() -> Promise<Void> {
        return Promise { [weak self] seal in
            guard let self = self else { return }
            self.eventsService.stop()
            self.localNotificationService.cleanUp()

            var wait = Promise<Void>()
            let promises = [
                self.messageService.cleanUp(),
                self.labelService.cleanUp(),
                self.contactService.cleanUp(),
                self.contactGroupService.cleanUp(),
                lastUpdatedStore.cleanUp(userId: self.userID),
                self.incomingDefaultService.cleanUp()
            ]
            self.deactivatePayments()
            #if !APP_EXTENSION
            self.payments.planService.currentSubscription = nil
            self.encryptedSearchCache.logout(of: userID)
            #endif
            for p in promises {
                wait = wait.then({ (_) -> Promise<Void> in
                    return p
                })
            }
            wait.done {
                userCachedStatus.removeMobileSignature(uid: self.userID.rawValue)
                userCachedStatus.removeMobileSignatureSwitchStatus(uid: self.userID.rawValue)
                userCachedStatus.removeDefaultSignatureSwitchStatus(uid: self.userID.rawValue)
                userCachedStatus.removeIsCheckSpaceDisabledStatus(uid: self.userID.rawValue)
                self.authCredentialAccessQueue.sync { [weak self] in
                    self?.isLoggedOut = true
                }
                seal.fulfill_()
            }.catch { (_) in
                seal.fulfill_()
            }
        }
    }

    static func cleanUpAll() -> Promise<Void> {
        IncomingDefaultService.cleanUpAll()
        LocalNotificationService.cleanUpAll()

        var wait = Promise<Void>()
        let promises = [
            MessageDataService.cleanUpAll(),
            LabelsDataService.cleanUpAll(),
            ContactDataService.cleanUpAll(),
            ContactGroupsDataService.cleanUpAll(),
            LastUpdatedStore.cleanUpAll()
        ]
        for p in promises {
            wait = wait.then({ (_) -> Promise<Void> in
                return p
            })
        }
        return wait
    }

    var delegate: UserManagerSave?

    private(set) var apiService: APIService
    private(set) var userInfo: UserInfo {
        didSet {
            updateTelemetry()
        }
    }
    let authHelper: AuthHelper
    private(set) var authCredential: AuthCredential
    private(set) var isLoggedOut = false

    var isUserSelectedUnreadFilterInInbox = false

    private var coreDataService: CoreDataService {
        sharedServices.get(by: CoreDataService.self)
    }

    lazy var conversationStateService: ConversationStateService = { [unowned self] in
        return ConversationStateService(
            viewMode: self.userInfo.viewMode
        )
    }()

    lazy var reportService: BugDataService = { [unowned self] in
        let service = BugDataService(api: self.apiService)
        return service
    }()

    lazy var contactService: ContactDataService = { [unowned self] in
        let service = ContactDataService(api: self.apiService,
                                         labelDataService: self.labelService,
                                         userInfo: self.userInfo,
                                         coreDataService: coreDataService,
                                         contactCacheStatus: userCachedStatus,
                                         cacheService: self.cacheService,
                                         queueManager: sharedServices.get(by: QueueManager.self))
        return service
    }()

    lazy var contactGroupService: ContactGroupsDataService = { [unowned self] in
        let service = ContactGroupsDataService(api: self.apiService,
                                               labelDataService: self.labelService,
                                               coreDataService: coreDataService,
                                               queueManager: sharedServices.get(by: QueueManager.self),
                                               userID: self.userID)
        return service
    }()

    lazy var appRatingService: AppRatingService = { [unowned self] in
        let service = AppRatingService(
            dependencies: .init(
                featureFlagService: featureFlagsDownloadService,
                appRating: AppRatingManager()
            )
        )
        return service
    }()

    weak var parentManager: UsersManager?

    private let appTelemetry: AppTelemetry

    lazy var messageService: MessageDataService = { [unowned self] in
        let service = MessageDataService(
            api: self.apiService,
            userID: self.userID,
            labelDataService: self.labelService,
            contactDataService: self.contactService,
            localNotificationService: self.localNotificationService,
            queueManager: sharedServices.get(by: QueueManager.self),
            contextProvider: coreDataService,
            lastUpdatedStore: sharedServices.get(by: LastUpdatedStore.self),
            user: self,
            cacheService: self.cacheService,
            undoActionManager: self.undoActionManager,
            contactCacheStatus: userCachedStatus)
        service.viewModeDataSource = self
        service.userDataSource = self
        return service
    }()

    lazy var conversationService: ConversationDataServiceProxy = { [unowned self] in
        let service = ConversationDataServiceProxy(api: apiService,
                                                   userID: userID,
                                                   contextProvider: coreDataService,
                                                   lastUpdatedStore: sharedServices.get(by: LastUpdatedStore.self),
                                                   messageDataService: messageService,
                                                   eventsService: eventsService,
                                                   undoActionManager: undoActionManager,
                                                   queueManager: sharedServices.get(by: QueueManager.self),
                                                   contactCacheStatus: userCachedStatus)
        return service
    }()

    lazy var labelService: LabelsDataService = { [unowned self] in
        let service = LabelsDataService(
            api: self.apiService,
            userID: self.userID,
            contextProvider: coreDataService,
            lastUpdatedStore: sharedServices.get(by: LastUpdatedStore.self),
            cacheService: self.cacheService
        )
        service.viewModeDataSource = self
        return service
    }()

    lazy var userService: UserDataService = { [unowned self] in
        let service = UserDataService(check: false, api: self.apiService)
        return service
    }()

    lazy var localNotificationService: LocalNotificationService = { [unowned self] in
        let service = LocalNotificationService(userID: self.userID)
        return service
    }()

    lazy var cacheService: CacheService = { [unowned self] in
        let service = CacheService(userID: self.userID)
        return service
    }()

    lazy var incomingDefaultService: IncomingDefaultService = { [unowned self] in
        return IncomingDefaultService(
            dependencies: .init(
                apiService: apiService,
                contextProvider: coreDataService,
                userInfo: userInfo
            )
        )
    }()

    lazy var eventsService: EventsFetching = { [unowned self] in
        let useCase = FetchMessageMetaData(
            params: .init(userID: userInfo.userId),
            dependencies: .init(messageDataService: messageService, contextProvider: coreDataService)
        )
        let service = EventsService(
            userManager: self,
            dependencies: .init(fetchMessageMetaData: useCase, contactCacheStatus: userCachedStatus, incomingDefaultService: incomingDefaultService)
        )
        return service
    }()

    lazy var undoActionManager: UndoActionManagerProtocol = { [unowned self] in
        let manager = UndoActionManager(
            apiService: self.apiService,
            internetStatusProvider: sharedServices.get(),
            contextProvider: coreDataService,
            getEventFetching: { [weak self] in
                self?.eventsService
            },
            getUserManager: { [weak self] in
                self
            }
        )
        return manager
    }()

	lazy var featureFlagsDownloadService: FeatureFlagsDownloadService = { [unowned self] in
        let service = FeatureFlagsDownloadService(
            userID: userID,
            apiService: self.apiService,
            sessionID: self.authCredential.sessionID,
            appRatingStatusProvider: userCachedStatus,
            scheduleSendEnableStatusProvider: userCachedStatus,
            userIntroductionProgressProvider: userCachedStatus,
            senderImageEnableStatusProvider: userCachedStatus
        )
        service.register(newSubscriber: inAppFeedbackStateService)
        return service
    }()

    private var lastUpdatedStore: LastUpdatedStoreProtocol {
        return sharedServices.get(by: LastUpdatedStore.self)
    }

    lazy var inAppFeedbackStateService: InAppFeedbackStateServiceProtocol = {
        let service = InAppFeedbackStateService()
        return service
    }()

    #if !APP_EXTENSION
    lazy var blockedSenderCacheUpdater: BlockedSenderCacheUpdater = { [unowned self] in
        let refetchAllBlockedSenders = RefetchAllBlockedSenders(
            dependencies: .init(incomingDefaultService: incomingDefaultService)
        )

        return BlockedSenderCacheUpdater(
            dependencies: .init(
                fetchStatusProvider: userCachedStatus,
                internetConnectionStatusProvider: InternetConnectionStatusProvider(),
                refetchAllBlockedSenders: refetchAllBlockedSenders,
                userInfo: userInfo
            )
        )
    }()

    lazy var payments = Payments(inAppPurchaseIdentifiers: Constants.mailPlanIDs,
                                 apiService: self.apiService,
                                 localStorage: userCachedStatus,
                                 canExtendSubscription: true,
                                 reportBugAlertHandler: { _ in
                                     let link = DeepLink("toBugPop", sender: nil)
                                     NotificationCenter.default.post(name: .switchView, object: link)
                                 })

    private var encryptedSearchCache: EncryptedSearchUserCache {
        return sharedServices.get(by: EncryptedSearchUserDefaultCache.self)
    }
    #endif

    var hasTelemetryEnabled: Bool {
        #if DEBUG
        if !ProcessInfo.isRunningUnitTests {
            return true
        }
        #endif
        return userInfo.telemetry == 1
    }

    var mailSettings: MailSettings

    init(
        api: APIService,
        userInfo: UserInfo,
        authCredential: AuthCredential,
        mailSettings: MailSettings?,
        parent: UsersManager?,
        appTelemetry: AppTelemetry = MailAppTelemetry()
    ) {
        self.userInfo = userInfo
        self.apiService = api
        self.authCredential = authCredential
        self.mailSettings = mailSettings ?? .init()
        self.appTelemetry = appTelemetry
        self.authHelper = AuthHelper(authCredential: authCredential)
        self.authHelper.setUpDelegate(self, callingItOn: .asyncExecutor(dispatchQueue: authCredentialAccessQueue))
        self.apiService.authDelegate = authHelper
        acquireSessionIfNeeded()
        self.parentManager = parent
        let handler = self.makeQueueHandler()
        let queueManager = sharedServices.get(by: QueueManager.self)
        queueManager.registerHandler(handler)
        self.messageService.signin()
    }

    /// A mock function only for unit test
    init(
        api: APIService,
        role: UserInfo.OrganizationRole,
        userInfo: UserInfo = UserInfo.getDefault(),
        mailSettings: MailSettings = .init(),
        appTelemetry: AppTelemetry = MailAppTelemetry()
    ) {
        guard ProcessInfo.isRunningUnitTests || ProcessInfo.isRunningUITests else {
            fatalError("This initialization only for test")
        }
        userInfo.role = role.rawValue
        self.userInfo = userInfo
        self.apiService = api
        self.appTelemetry = appTelemetry
        self.authCredential = AuthCredential.none
        self.mailSettings = mailSettings
        self.authHelper = AuthHelper(authCredential: authCredential)
        self.authHelper.setUpDelegate(self, callingItOn: .asyncExecutor(dispatchQueue: authCredentialAccessQueue))
        self.apiService.authDelegate = authHelper
        acquireSessionIfNeeded()
    }

    private func acquireSessionIfNeeded() {
        self.apiService.acquireSessionIfNeeded { result in
            guard case .success(.sessionAlreadyPresent) = result else {
                assertionFailure("Lack of session just after the auth delegate being configured indicates the programmers error")
                return
            }
        }
    }

    func isMatch(sessionID uid: String) -> Bool {
        return authCredential.sessionID == uid
    }

    func fetchUserInfo() {
        featureFlagsDownloadService.getFeatureFlags(completion: nil)
        _ = self.userService.fetchUserInfo(auth: self.authCredential).done { [weak self] tuple in
            guard let info = tuple.0 else { return }
            self?.userInfo = info
            self?.mailSettings = tuple.1
            self?.save()
            #if !APP_EXTENSION
            guard let self = self,
                  let firstUser = self.parentManager?.firstUser,
                  firstUser.userID == self.userID else { return }
            self.activatePayments()
            userCachedStatus.initialSwipeActionIfNeeded(leftToRight: info.swipeRight, rightToLeft: info.swipeLeft)
            // When app launch, the app will show a skeleton view
            // After getting setting data, show inbox
            NotificationCenter.default.post(name: .fetchPrimaryUserSettings, object: nil)
            #endif
        }
    }

    func resignAsActiveUser() {
        deactivatePayments()
    }

    func becomeActiveUser() {
        updateTelemetry()
        refreshFeatureFlags()
        activatePayments()
    }

    func makeQueueHandler() -> QueueHandler {
        MainQueueHandler(
            coreDataService: coreDataService,
            apiService: apiService,
            messageDataService: messageService,
            conversationDataService: conversationService.conversationDataService,
            labelDataService: labelService,
            localNotificationService: localNotificationService,
            undoActionManager: undoActionManager,
            user: self
        )
    }

    private func updateTelemetry() {
        hasTelemetryEnabled ? appTelemetry.enable() : appTelemetry.disable()
    }

    func refreshFeatureFlags() {
        featureFlagsDownloadService.getFeatureFlags(completion: nil)
    }

    func activatePayments() {
        #if !APP_EXTENSION
        self.payments.storeKitManager.delegate = sharedServices.get(by: StoreKitManagerImpl.self)
        self.payments.storeKitManager.subscribeToPaymentQueue()
        self.payments.storeKitManager.updateAvailableProductsList { _ in }
        #endif
    }

    func deactivatePayments() {
        #if !APP_EXTENSION
        self.payments.storeKitManager.unsubscribeFromPaymentQueue()
        // this will ensure no unnecessary screen refresh happens, which was the source of crash previously
        self.payments.storeKitManager.refreshHandler = { _ in }
        // this will ensure no unnecessary communication with proton backend happens
        self.payments.storeKitManager.delegate = nil
        #endif
    }

    func usedSpace(plus size: Int64) {
        self.userInfo.usedSpace += size
        self.save()
    }

    func usedSpace(minus size: Int64) {
        let usedSize = self.userInfo.usedSpace - size
        self.userInfo.usedSpace = max(usedSize, 0)
        self.save()
    }

    func update(userInfo: UserInfo) {
        self.userInfo = userInfo
    }
}

extension UserManager: UserManagerSaveAction {

    func save() {
        DispatchQueue.main.async {
            self.conversationStateService.userInfoHasChanged(viewMode: self.userInfo.viewMode)
        }
        self.delegate?.onSave()
    }
}

extension UserManager: UserDataSource {

    var hasPaidMailPlan: Bool {
        userInfo.role > 0 && userInfo.subscribed.contains(.mail)
    }

    func getAddressPrivKey(address_id: String) -> String {
        return ""
    }

    func getAddressKey(address_id: String) -> Key? {
        return self.userInfo.getAddressKey(address_id: address_id)
    }

    func getAllAddressKey(address_id: String) -> [Key]? {
        return self.userInfo.getAllAddressKey(address_id: address_id)
    }

    var userPrivateKeys: [ArmoredKey] {
        userInfo.userPrivateKeys
    }

    var addressKeys: [Key] {
        get {
            return self.userInfo.userAddresses.toKeys()
        }
    }

    var mailboxPassword: Passphrase {
        Passphrase(value: authCredential.mailboxpassword)
    }

    var notificationEmail: String {
        return userInfo.notificationEmail
    }

    var notify: Bool {
        return userInfo.notify == 1
    }

    var isPaid: Bool {
        return self.userInfo.role > 0 ? true : false
    }

    func updateFromEvents(userInfoRes: [String: Any]?) {
        if let userData = userInfoRes {
            let newUserInfo = UserInfo(response: userData)
            userInfo.set(userinfo: newUserInfo)
            self.save()
        }
    }

    func updateFromEvents(userSettingsRes: [String: Any]?) {
        if let settings = userSettingsRes {
            userInfo.parse(userSettings: settings)
            self.save()
        }
    }

    func updateFromEvents(mailSettingsRes: [String: Any]?) {
        if let settings = mailSettingsRes {
            userInfo.parse(mailSettings: settings)
            if let mailSettings = try? MailSettings(dict: settings) {
                self.mailSettings = mailSettings
            }
            self.save()
        }
    }

    func update(usedSpace: Int64) {
        self.userInfo.usedSpace = usedSpace
        self.save()
    }

    func setFromEvents(addressRes address: Address) {
        if let index = self.userInfo.userAddresses.firstIndex(where: { $0.addressID == address.addressID }) {
            self.userInfo.userAddresses.remove(at: index)
        }
        self.userInfo.userAddresses.append(address)
        self.userInfo.userAddresses.sort(by: { (v1, v2) -> Bool in
            return v1.order < v2.order
        })
        self.save()
    }

    func deleteFromEvents(addressIDRes addressID: String) {
        if let index = self.userInfo.userAddresses.firstIndex(where: { $0.addressID == addressID }) {
            self.userInfo.userAddresses.remove(at: index)
            self.save()
        }
    }

    func getUnReadCount(by labelID: String) -> Int {
        return self.labelService.unreadCount(by: LabelID(labelID))
    }
}

/// Get values
extension UserManager {
    var defaultDisplayName: String {
        if let addr = userInfo.userAddresses.defaultAddress() {
            return addr.displayName
        }
        return displayName
    }

    var defaultEmail: String {
        if let addr = userInfo.userAddresses.defaultAddress() {
            return addr.email
        }
        return ""
    }

    var displayName: String {
        return userInfo.displayName.decodeHtml()
    }

    var addresses: [Address] {
        get { userInfo.userAddresses }
        set { userInfo.userAddresses = newValue }
    }

    var userDefaultSignature: String {
        return userInfo.defaultSignature.ln2br()
    }

    var defaultSignatureStatus: Bool {
        get {
            if let status = userCachedStatus.getDefaultSignaureSwitchStatus(uid: userID.rawValue) {
                return status
            } else {
                let oldStatus = userService.defaultSignatureStauts
                userCachedStatus.setDefaultSignatureSwitchStatus(uid: userID.rawValue, value: oldStatus)
                return oldStatus
            }
        }
        set {
            userCachedStatus.setDefaultSignatureSwitchStatus(uid: userID.rawValue, value: newValue)
        }
    }

    var showMobileSignature: Bool {
        get {
            #if Enterprise
            let isEnterprise = true
            #else
            let isEnterprise = false
            #endif
            let role = userInfo.role
            if role > 0 || isEnterprise {
                if let status = userCachedStatus.getMobileSignatureSwitchStatus(by: userID.rawValue) {
                    return status
                } else {
                    // Migrate from local cache
                    let status = self.userService.switchCacheOff == false
                    userCachedStatus.setMobileSignatureSwitchStatus(uid: userID.rawValue, value: status)
                    return status
                }
            } else {
                userCachedStatus.setMobileSignatureSwitchStatus(uid: userID.rawValue, value: true)
                return true
            } }
        set {
            userCachedStatus.setMobileSignatureSwitchStatus(uid: userID.rawValue, value: newValue)
        }
    }

    var mobileSignature: String {
        get {
            #if Enterprise
            let isEnterprise = true
            #else
            let isEnterprise = false
            #endif
            let role = userInfo.role
            if role > 0 || isEnterprise {
                return userCachedStatus.getMobileSignature(by: userID.rawValue)
            } else {
                userCachedStatus.removeMobileSignature(uid: userID.rawValue)
                return userCachedStatus.getMobileSignature(by: userID.rawValue)
            }
        }
        set {
            userCachedStatus.setMobileSignature(uid: userID.rawValue, signature: newValue)
        }
    }

    var isEnableFolderColor: Bool {
        return userInfo.enableFolderColor == 1
    }

    var isInheritParentFolderColor: Bool {
        return userInfo.inheritParentFolderColor == 1
    }

    var isStorageExceeded: Bool {
        let maxSpace = self.userInfo.maxSpace
        let usedSpace = self.userInfo.usedSpace
        return usedSpace >= maxSpace
    }

    var hasAtLeastOneNonStandardToolbarAction: Bool {
        guard let users = parentManager else {
            return false
        }
        return users.users.contains(where: { user in
            user.userInfo.messageToolbarActions.isCustom ||
            user.userInfo.listToolbarActions.isCustom ||
            user.userInfo.conversationToolbarActions.isCustom
        })
    }

    var toolbarActionsIsStandard: Bool {
        return !userInfo.messageToolbarActions.isCustom &&
            !userInfo.listToolbarActions.isCustom &&
            !userInfo.conversationToolbarActions.isCustom
    }
}

extension UserManager: ViewModeDataSource {
    func getCurrentViewMode() -> ViewMode {
        return conversationStateService.viewMode
    }
}

extension UserManager: UserAddressUpdaterProtocol {
    func updateUserAddresses(completion: (() -> Void)?) {
        userService.fetchUserAddresses { [weak self] result in
            switch result {
            case .failure:
                completion?()
            case .success(let addressResponse):
                self?.userInfo.set(addresses: addressResponse.addresses)
                self?.save()
                completion?()
            }
        }
    }
}

extension UserManager: AuthHelperDelegate {
    func credentialsWereUpdated(authCredential: AuthCredential, credential: Credential, for sessionUID: String) {
        if authCredential.isForUnauthenticatedSession {
            assertionFailure("This should never happen — the UserManager should always operate within the authenticated session. Please investigate!")
        }
        self.authCredential = authCredential
        isLoggedOut = false
        self.save()
    }

    func sessionWasInvalidated(for sessionUID: String, isAuthenticatedSession: Bool) {
        if !isAuthenticatedSession {
            assertionFailure("This should never happen — the UserManager should always operate within the authenticated session. Please investigate!")
        }
        isLoggedOut = true
        self.eventsService.stop()
        NotificationCenter.default.post(name: .didRevoke, object: nil, userInfo: ["uid": sessionUID])
    }
}
