//
//  WindowsCoordinator.swift
//  Proton Mail - Created on 12/11/2018.
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

import LifetimeTracker
import MBProgressHUD
import ProtonCore_Keymaker
import ProtonCore_Networking
import ProtonCore_DataModel
import ProtonCore_UIFoundations
import ProtonMailAnalytics
import SafariServices

// this view controller is placed into AppWindow only until it is correctly loaded from storyboard or correctly restored with use of MainKey
private class PlaceholderVC: UIViewController {
    var color: UIColor = .blue

    convenience init(color: UIColor) {
        self.init()
        self.color = color
    }

    override func loadView() {
        view = UINib(nibName: "LaunchScreen", bundle: nil).instantiate(withOwner: nil, options: nil).first as? UIView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        self.view.backgroundColor = color
        #else
        Snapshot().show(at: self.view)
        #endif
    }
}

class WindowsCoordinator: LifetimeTrackable {
    class var lifetimeConfiguration: LifetimeConfiguration {
        .init(maxCount: 1)
    }

    private lazy var snapshot = Snapshot()
    private var launchedByNotification = false

    private var deeplink: DeepLink?

    private var appWindow: UIWindow! = UIWindow(root: PlaceholderVC(color: .red), scene: nil) {
        didSet {
            guard appWindow == nil else { return }
            if let oldAppWindow = oldValue {
                oldAppWindow.rootViewController?.dismiss(animated: false)
            }
            menuCoordinator = nil
        }
    }

    private var lockWindow: UIWindow?

    private var services: ServiceFactory
    private var darkModeCache: DarkModeCacheProtocol
    private var menuCoordinator: MenuCoordinator?

    var currentWindow: UIWindow? {
        didSet {
            if #available(iOS 13, *) {
                switch darkModeCache.darkModeStatus {

                case .followSystem:
                    self.currentWindow?.overrideUserInterfaceStyle = .unspecified
                case .forceOn:
                    self.currentWindow?.overrideUserInterfaceStyle = .dark
                case .forceOff:
                    self.currentWindow?.overrideUserInterfaceStyle = .light
                }
            } else if #available(iOS 13, *) {
                self.currentWindow?.overrideUserInterfaceStyle = .light
            }
            self.currentWindow?.makeKeyAndVisible()
        }
    }

    private var arePrimaryUserSettingsFetched = false

    enum Destination {
        enum SignInDestination: String { case form, mailboxPassword }
        case lockWindow, appWindow, signInWindow(SignInDestination)
    }

    internal var scene: AnyObject? {
        didSet {
            // UIWindowScene class is available on iOS 13 and newer, older platforms should not use this property
            if #available(iOS 13.0, *) {
                assert(scene is UIWindowScene, "Scene should be of type UIWindowScene")
            } else {
                assert(false, "Scenes are unavailable on iOS 12 and older")
            }
        }
    }

    init(services: ServiceFactory,
         darkModeCache: DarkModeCacheProtocol
    ) {
        defer {
            NotificationCenter.default.addObserver(self, selector: #selector(requestMainKey), name: Keymaker.Const.requestMainKey, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(unlock), name: .didUnlock, object: nil)
            NotificationCenter.default.addObserver(forName: .didRevoke, object: nil, queue: .main) { [weak self] (noti) in
                if let uid = noti.userInfo?["uid"] as? String {
                    self?.didReceiveTokenRevoke(uid: uid)
                }
            }

            NotificationCenter.default.addObserver(forName: .fetchPrimaryUserSettings, object: nil, queue: .main) { [weak self] _ in
                if self?.arePrimaryUserSettingsFetched == false {
                    self?.arePrimaryUserSettingsFetched = true
                    self?.restoreAppStates()
                }
            }

            NotificationCenter.default.addObserver(forName: .switchView, object: nil, queue: .main) { [weak self] notification in
                self?.arePrimaryUserSettingsFetched = true
                // trigger the menu to follow the deeplink or show inbox
                self?.handleSwitchViewDeepLinkIfNeeded((notification.object as? DeepLink))
            }

            NotificationCenter.default.addObserver(forName: .scheduledMessageSucceed, object: nil, queue: .main) { [weak self] notification in
                guard let tuple = notification.object as? (MessageID, Date, UserID) else { return }
                self?.showScheduledSendSucceedBanner(
                    messageID: tuple.0,
                    deliveryTime: tuple.1,
                    userID: tuple.2
                )
            }

            NotificationCenter.default.addObserver(forName: .showScheduleSendUnavailable, object: nil, queue: .main) { [weak self] _ in
                self?.showScheduledSendUnavailableAlert()
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(messageSendFailAddressValidationIncorrect),
                name: .messageSendFailAddressValidationIncorrect,
                object: nil
            )

            if #available(iOS 13.0, *) {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(updateUserInterfaceStyle),
                    name: .shouldUpdateUserInterfaceStyle,
                    object: nil
                )
                // this is done by UISceneDelegate
            } else {
                NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground),
                                                       name: UIApplication.willEnterForegroundNotification,
                                                       object: nil)
                NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                                       name: UIApplication.didEnterBackgroundNotification,
                                                       object: nil)
            }
        }
        self.services = services
        self.darkModeCache = darkModeCache
        trackLifetime()
    }

    func start(launchedByNotification: Bool = false) {
        self.launchedByNotification = launchedByNotification
        let placeholder = UIWindow(root: PlaceholderVC(color: .white), scene: self.scene)
        self.currentWindow = placeholder

        // some cache may need user to unlock first. so this need to move to after windows showup
        let usersManager: UsersManager = self.services.get()
        usersManager.launchCleanUpIfNeeded()

        if ProcessInfo.isRunningUnitTests {
            // While running the unit test, call this to generate the main key.
            keymaker.mainKeyExists()
            return
        }

        // we should not trigger the touch id here. because it also doing in the sign vc. so when need lock. we just go to lock screen first
        // clean this up later.

        let unlockManager: UnlockManager = self.services.get()
        let flow = unlockManager.getUnlockFlow()
        Breadcrumbs.shared.add(message: "WindowsCoordinator.start unlockFlow = \(flow)", to: .randomLogout)
        if userCachedStatus.isAppLockedAndAppKeyEnabled {
            self.lock()
        } else {
            DispatchQueue.main.async {
                // initiate unlock process which will send .didUnlock or .requestMainKey eventually
                unlockManager.initiateUnlock(flow: flow,
                                             requestPin: self.lock,
                                             requestMailboxPassword: self.lock)
            }
        }
    }

    @objc func willEnterForeground() {
        self.snapshot.remove()
    }

    @objc func didEnterBackground() {
        if let vc = self.currentWindow?.topmostViewController(),
           !(vc is ComposeContainerViewController) {
            vc.view.endEditing(true)
        }
        if let window = self.currentWindow {
            self.snapshot.show(at: window)
        }
    }

    @objc private func requestMainKey() {
        Breadcrumbs.shared.add(message: "WindowsCoordinator requestMainKey received", to: .randomLogout)
        lock()
    }

    @objc func lock() {
        Breadcrumbs.shared.add(message: "WindowsCoordinator.lock called", to: .randomLogout)
        guard sharedServices.get(by: UsersManager.self).hasUsers() else {
            Breadcrumbs.shared.add(message: "WindowsCoordinator.lock no users found", to: .randomLogout)
            keymaker.wipeMainKey()
            navigateToSignInFormAndReport(reason: .noUsersFoundInUsersManager(action: #function))
            return
        }
        self.go(dest: .lockWindow)
    }

    @objc func unlock() {
        self.lockWindow = nil
        let usersManager: UsersManager = self.services.get()

        guard usersManager.hasUsers() else {
            navigateToSignInFormAndReport(reason: .noUsersFoundInUsersManager(action: "\(#function) \(#line)"))
            return
        }
        if usersManager.count <= 0 {
            _ = usersManager.clean()
            navigateToSignInFormAndReport(reason: .noUsersFoundInUsersManager(action: "\(#function) \(#line)"))
        } else {
            // To register again in case the registration on app launch didn't go through because the app was locked
            let pushService: PushNotificationService = sharedServices.get()
            UNUserNotificationCenter.current().delegate = pushService
            pushService.registerForRemoteNotifications()
            self.go(dest: .appWindow)
        }
    }

    @objc func didReceiveTokenRevoke(uid: String) {
        let usersManager: UsersManager = services.get()
        let queueManager: QueueManager = services.get()

        if let user = usersManager.getUser(by: uid),
           !usersManager.loggingOutUserIDs.contains(user.userID) {
            let shouldShowBadTokenAlert = usersManager.count == 1

            Analytics.shared.sendEvent(.userKickedOut(reason: .apiAccessTokenInvalid))

            queueManager.unregisterHandler(for: user.userID)
            usersManager.logout(user: user, shouldShowAccountSwitchAlert: true) { [weak self] in
                guard let self = self else { return }
                guard let appWindow = self.appWindow else {return}

                if usersManager.hasUsers() {
                    appWindow.enumerateViewControllerHierarchy { controller, stop in
                        if let menu = controller as? MenuViewController {
                            // Work Around: trigger viewDidLoad of menu view controller
                            _ = menu.view
                            menu.navigateTo(label: MenuLabel(location: .inbox))
                        }
                    }
                }
                if shouldShowBadTokenAlert {
                    NSError.alertBadToken()
                }

                let handler = LocalNotificationService(userID: user.userID)
                handler.showSessionRevokeNotification(email: user.defaultEmail)
            }
        }
    }

    private func navigateToSignInFormAndReport(reason: UserKickedOutReason) {
        Analytics.shared.sendEvent(.userKickedOut(reason: reason), trace: Breadcrumbs.shared.trace(for: .randomLogout))
        go(dest: .signInWindow(.form))
    }

    func go(dest: Destination) {
        DispatchQueue.main.async { // cuz
            switch dest {
            case .signInWindow(let signInDestination):
                // do not restart coordinator in case it's already displayed with right configuration
                if let signInVC = self.currentWindow?.rootViewController as? SignInCoordinator.VC,
                   signInVC.coordinator.startingPoint == signInDestination {
                    return
                }
                self.lockWindow = nil
                self.appWindow = nil
                let signInEnvironment = SignInCoordinatorEnvironment.live(
                    services: sharedServices, forceUpgradeDelegate: ForceUpgradeManager.shared.forceUpgradeHelper
                )
                let coordinator: SignInCoordinator = .loginFlowForFirstAccount(
                    startingPoint: signInDestination, environment: signInEnvironment
                ) { [weak self] flowResult in
                    switch flowResult {
                    case .succeeded:
                        self?.go(dest: .appWindow)
                        delay(1) {
                            // Waiting for init of Menu coordinate to receive the notification
                            NotificationCenter.default.post(name: .switchView, object: nil)
                        }
                    case .userWantsToGoToTroubleshooting:
                        let troubleshootingVC = NetworkTroubleShootViewController(viewModel: NetworkTroubleShootViewModel())
                        troubleshootingVC.onDismiss = { [weak self] in
                            // restart the process after user returns from troubleshooting
                            self?.go(dest: .signInWindow(signInDestination))
                        }
                        let navigationVC = UINavigationController(rootViewController: troubleshootingVC)
                        navigationVC.modalPresentationStyle = .fullScreen
                        self?.currentWindow?.rootViewController?.present(navigationVC, animated: true, completion: nil)
                    case .alreadyLoggedIn, .loggedInFreeAccountsLimitReached, .errored:
                        // not sure what else I can do here instead of restarting the process
                        self?.navigateToSignInFormAndReport(reason: .unexpected(description: "\(flowResult)"))
                    case .dismissed:
                        assertionFailure("this should never happen as the loginFlowForFirstAccount is not dismissable")
                        self?.navigateToSignInFormAndReport(reason: .unexpected(description: "\(flowResult)"))
                    }
                }
                let newWindow = UIWindow(root: coordinator.actualViewController, scene: self.scene)
                self.navigate(from: self.currentWindow, to: newWindow, animated: false) {
                    coordinator.start()
                }

            case .lockWindow:
                if let topVC = self.appWindow?.topmostViewController() {
                    topVC.view.becomeFirstResponder()
                    topVC.view.endEditing(true)
                }
                guard self.lockWindow == nil else {
                    guard let lockVC = self.currentWindow?.rootViewController as? LockCoordinator.VC,
                          lockVC.coordinator.startedOrSheduledForAStart == false
                    else {
                        return
                    }
                    lockVC.coordinator.start()
                    return
                }
                let coordinator = LockCoordinator(services: sharedServices) { [weak self] flowResult in
                    switch flowResult {
                    case .mailbox:
                        self?.go(dest: .appWindow)
                    case .mailboxPassword:
                        self?.go(dest: .signInWindow(.mailboxPassword))
                    case .signIn(let reason):
                        self?.navigateToSignInFormAndReport(reason: .afterLockScreen(description: reason))
                    }
                }
                let lock = UIWindow(root: coordinator.actualViewController, scene: self.scene)
                self.lockWindow?.rootViewController?.presentedViewController?.dismiss(animated: false)
                self.lockWindow = lock
                coordinator.startedOrSheduledForAStart = true
                self.navigate(from: self.currentWindow, to: lock, animated: false) { [weak coordinator] in
                    if UIApplication.shared.applicationState != .background {
                        coordinator?.start()
                    } else {
                        coordinator?.startedOrSheduledForAStart = false
                    }
                }

            case .appWindow:
                self.lockWindow = nil
                if self.appWindow == nil || self.appWindow.rootViewController is PlaceholderVC {
                    let root = PMSideMenuController()
                    let coordinator = WindowsCoordinator.makeMenuCoordinator(sideMenu: root)
                    self.menuCoordinator = coordinator
                    coordinator.start(launchedByNotification: self.launchedByNotification)
                    self.appWindow = UIWindow(root: root, scene: self.scene)
                    self.launchedByNotification = false
                }
                if #available(iOS 13.0, *), self.appWindow.windowScene == nil {
                    self.appWindow.windowScene = self.scene as? UIWindowScene
                }
                if self.navigate(from: self.currentWindow, to: self.appWindow, animated: true), let deeplink = self.deeplink {
                    self.handleDeepLinkIfNeeded(deeplink)
                }
            }
        }
    }

    private func restoreAppStates() {
        guard appWindow != nil else { return }
        self.appWindow.enumerateViewControllerHierarchy { controller, stop in
            if let _ = controller as? MenuViewController,
               let coordinator = self.menuCoordinator {
                coordinator.handleSwitchView(deepLink: self.deeplink)
                stop = true
            }
        }
    }

    @discardableResult
    private func navigate(from source: UIWindow?, to destination: UIWindow, animated: Bool, completion: (() -> Void)? = nil) -> Bool {
        guard source != destination else {
            return false
        }

        let effectView = UIVisualEffectView(frame: UIScreen.main.bounds)
        source?.addSubview(effectView)
        destination.alpha = 0.0

        UIView.animate(withDuration: animated ? 0.5 : 0.0, animations: {
            effectView.effect = UIBlurEffect(style: .dark)
            destination.alpha = 1.0
        }, completion: { _ in
            _ = source
            _ = destination
            effectView.removeFromSuperview()

            // ensure proper view(Will|Did)(Appear|Disappear) callbacks are called
            let topSource = source?.topmostViewController()
            let topDestination = destination.topmostViewController()

            topSource?.beginAppearanceTransition(false, animated: false)
            topDestination?.loadViewIfNeeded()
            topDestination?.beginAppearanceTransition(true, animated: false)

            topSource?.endAppearanceTransition()
            topDestination?.endAppearanceTransition()

            completion?()
        })
        self.currentWindow = destination
        return true
    }

    internal func followDeeplink(_ deeplink: DeepLink) {
        self.deeplink = deeplink
        _ = deeplink.popFirst
        self.start()
    }

    func followDeepDeeplinkIfNeeded(_ deeplink: DeepLink) {
        self.deeplink = deeplink
        _ = deeplink.popFirst

        if arePrimaryUserSettingsFetched {
            start()
        }
    }

    private func handleDeepLinkIfNeeded(_ deeplink: DeepLink) {
        guard arePrimaryUserSettingsFetched else { return }
        self.appWindow.enumerateViewControllerHierarchy { controller, stop in
            if let _ = controller as? MenuViewController,
                let coordinator = self.menuCoordinator {
                coordinator.follow(deeplink)
                stop = true
            }
        }
    }

    private func shouldOpenURL(deepLink: DeepLink?) -> URL? {
        guard let headNode = deepLink?.head else { return nil }

        if headNode.name == .toWebSupportForm {
            return URL(string: .webSupportFormLink)
        }
        if headNode.name == .toWebBrowser {
            guard let urlString = headNode.value else {
                return nil
            }
            return URL(string: urlString)
        }
        return nil
    }

    private func handleWebUrl(url: URL) {
        let linkOpener: LinkOpener = userCachedStatus.browser
        guard let url = linkOpener.deeplink(to: url) else {
            openUrl(url)
            return
        }
        if linkOpener == .inAppSafari {
            presentInAppSafari(url: url)
        } else {
            openUrl(url)
        }
    }

    private func openUrl(_ url: URL) {
        guard UIApplication.shared.canOpenURL(url) else {
            SystemLogger.log(message: "url can't be opened by the system", redactedInfo: url.absoluteString, isError: true)
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    private func presentInAppSafari(url: URL) {
        let safari = SFSafariViewController(url: url)
        DispatchQueue.main.async { [weak self] in
            self?.appWindow.topmostViewController()?.present(safari, animated: true)
        }
    }

    private func handleSwitchViewDeepLinkIfNeeded(_ deepLink: DeepLink?) {
        self.deeplink = deepLink
        if let url = shouldOpenURL(deepLink: deepLink) {
            self.deeplink = nil
            handleWebUrl(url: url)
            return
        }
        guard arePrimaryUserSettingsFetched && appWindow != nil else {
            return
        }
        self.appWindow.enumerateViewControllerHierarchy { controller, stop in
            if let _ = controller as? MenuViewController,
               let coordinator = self.menuCoordinator {
                coordinator.handleSwitchView(deepLink: deepLink)
                stop = true
            }
        }
    }

	@objc
    private func updateUserInterfaceStyle() {
        guard #available(iOS 13, *) else { return }
        switch darkModeCache.darkModeStatus {
        case .followSystem:
            currentWindow?.overrideUserInterfaceStyle = .unspecified
        case .forceOff:
            currentWindow?.overrideUserInterfaceStyle = .light
        case .forceOn:
            currentWindow?.overrideUserInterfaceStyle = .dark
        }
    }

    static func makeMenuCoordinator(sideMenu: PMSideMenuController) -> MenuCoordinator {
        let usersManager = sharedServices.get(by: UsersManager.self)
        let pushService = sharedServices.get(by: PushNotificationService.self)
        let coreDataService = sharedServices.get(by: CoreDataService.self)
        let lateUpdatedStore = sharedServices.get(by: LastUpdatedStore.self)
        let queueManager = sharedServices.get(by: QueueManager.self)
        let menuWidth = MenuViewController.calcProperMenuWidth()
        let coordinator = MenuCoordinator(services: sharedServices,
                                          pushService: pushService,
                                          coreDataService: coreDataService,
                                          lastUpdatedStore: lateUpdatedStore,
                                          usersManager: usersManager,
                                          queueManager: queueManager,
                                          sideMenu: sideMenu,
                                          menuWidth: menuWidth)
        return coordinator
    }
}

// MARK: Schedule message
extension WindowsCoordinator {

    private func showScheduledSendSucceedBanner(
        messageID: MessageID,
        deliveryTime: Date,
        userID: UserID
    ) {
        let topVC = self.currentWindow?.topmostViewController() ?? UIViewController()

        typealias Key = PMBanner.UserInfoKey
        PMBanner
            .getBanners(in: topVC)
            .filter {
                $0.userInfo?[Key.type.rawValue] as? String == Key.sending.rawValue &&
                $0.userInfo?[Key.messageID.rawValue] as? String == messageID.rawValue
            }
            .forEach { $0.dismiss(animated: false) }

        let timeTuple = PMDateFormatter.shared.titleForScheduledBanner(from: deliveryTime)
        let message = String(format: LocalString._edit_scheduled_button_message,
                             timeTuple.0,
                             timeTuple.1)
        let banner = PMBanner(message: message, style: PMBannerNewStyle.info)
        banner.addButton(text: LocalString._messages_undo_action) { banner in
            self.handleEditScheduleMessage(
                messageID: messageID,
                userID: userID
            ) {
                let deepLink = DeepLink(
                    String(describing: MailboxViewController.self),
                    sender: Message.Location.draft.rawValue
                )
                deepLink.append(
                    .init(name: MailboxCoordinator.Destination.composeScheduledMessage.rawValue,
                          value: messageID.rawValue,
                          states: ["originalScheduledTime": deliveryTime])
                )
                NotificationCenter.default.post(name: .switchView, object: deepLink)
            }
            banner.dismiss()
        }
        banner.show(at: .bottom, on: topVC)
    }

    private func showScheduledSendUnavailableAlert() {
        let title = LocalString._message_saved_to_draft
        let message = LocalString._schedule_send_unavailable_message
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addOKAction()

        let topVC = self.currentWindow?.topmostViewController() ?? UIViewController()
        topVC.present(alert, animated: true, completion: nil)
    }

    @objc private func messageSendFailAddressValidationIncorrect() {
        let title = LocalString._address_invalid_error_to_draft_action_title
        let toDraftAction = UIAlertAction(title: title, style: .default) { (_) in
            NotificationCenter.default.post(
                name: .switchView,
                object: DeepLink(
                    String(describing: MailboxViewController.self),
                    sender: Message.Location.draft.rawValue
                )
            )
        }
        UIAlertController.showOnTopmostVC(
            title: LocalString._address_invalid_error_sending_title,
            message: LocalString._address_invalid_error_sending,
            action: toDraftAction
        )
    }

    private func handleEditScheduleMessage(
        messageID: MessageID,
        userID: UserID,
        completion: @escaping () -> Void
    ) {
        let users = sharedServices.get(by: UsersManager.self)
        let user = users.getUser(by: userID)
        user?.messageService.undoSend(
            of: messageID,
            completion: { result in
                guard result.error == nil else {
                    return
                }
                user?.eventsService.fetchEvents(
                    byLabel: Message.Location.allmail.labelID,
                    notificationMessageID: nil,
                    completion: { _ in
                        completion()
                    })
            }
        )
    }
}
