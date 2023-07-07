//
//  LockCoordinator.swift
//  Proton Mail
//
//  Created by Krzysztof Siejkowski on 23/04/2021.
//  Copyright © 2021 Proton Mail. All rights reserved.
//

import LifetimeTracker
import PromiseKit
import ProtonMailAnalytics

final class LockCoordinator: LifetimeTrackable {
    enum FlowResult {
        case signIn(reason: String)
        case mailboxPassword
        case mailbox
    }

    typealias VC = CoordinatorKeepingViewController<LockCoordinator>

    class var lifetimeConfiguration: LifetimeConfiguration {
        .init(maxCount: 1)
    }

    let unlockManager: UnlockManager
    let usersManager: UsersManager
    var startedOrSheduledForAStart: Bool = false

    weak var viewController: VC?

    var actualViewController: VC { viewController ?? makeViewController() }

    let finishLockFlow: (FlowResult) -> Void

    init(services: ServiceFactory, finishLockFlow: @escaping (FlowResult) -> Void) {
        self.unlockManager = services.get(by: UnlockManager.self)
        self.usersManager = services.get(by: UsersManager.self)

        // explanation: boxing stopClosure to avoid referencing self before initialization is finished
        var stopClosure = { }
        self.finishLockFlow = { result in
            stopClosure()
            finishLockFlow(result)
        }
        stopClosure = { [weak self] in self?.stop() }
        trackLifetime()
    }

    private func makeViewController() -> VC {
        let vc = VC(coordinator: self, backgroundColor: .white)
        vc.view = UINib(nibName: "LaunchScreen", bundle: nil).instantiate(withOwner: nil, options: nil).first as? UIView
        vc.restorationIdentifier = "Lock"
        viewController = vc
        return vc
    }

    func start() {
        Breadcrumbs.shared.add(message: "LockCoordinator.start", to: .randomLogout)
        startedOrSheduledForAStart = true
        self.actualViewController.presentedViewController?.dismiss(animated: true)
        let unlockFlow = unlockManager.getUnlockFlow()
        switch unlockFlow {
        case .requirePin:
            goToPin()
        case .requireTouchID:
            goToTouchId()
        case .restore:
            finishLockFlow(.signIn(reason: "unlockFlow: \(unlockFlow)"))
        }
    }

    private func stop() {
        startedOrSheduledForAStart = false
    }

    private func goToPin() {
        if actualViewController.presentedViewController is PinCodeViewController { return }
        let pinVC = PinCodeViewController(unlockManager: UnlockManager.shared,
                                          viewModel: UnlockPinCodeModelImpl(),
                                          delegate: self)
        pinVC.modalPresentationStyle = .fullScreen
        actualViewController.present(pinVC, animated: true, completion: nil)
    }

    private func goToTouchId() {
        if (actualViewController.presentedViewController as? UINavigationController)?.viewControllers.first is BioCodeViewController { return }
        let bioCodeVC = BioCodeViewController(unlockManager: UnlockManager.shared,
                                              delegate: self)
        let navigationVC = UINavigationController(rootViewController: bioCodeVC)
        navigationVC.modalPresentationStyle = .fullScreen
        actualViewController.present(navigationVC, animated: true, completion: nil)
    }
}

// copied from old implementation of SignInViewController to keep the pin logic untact
extension LockCoordinator: PinCodeViewControllerDelegate {

    func next() {
        unlockManager.unlockIfRememberedCredentials(requestMailboxPassword: { [weak self] in
            self?.finishLockFlow(.mailboxPassword)
        }, unlockFailed: { [weak self] in
            self?.finishLockFlow(.signIn(reason: "unlock failed"))
        }, unlocked: { [weak self] in
            self?.finishLockFlow(.mailbox)
            self?.actualViewController.presentedViewController?.dismiss(animated: true)
        })
    }

    func cancel(completion: @escaping () -> Void) {
        /*
         If the user logs out from the unlock screen before unlocking the app, Core Data will not be set up when `clean()` is called, and the app will crash.

         Therefore we need to set up Core Data now.

         Note: calling `setupCoreData` before the main key is available might break the migration process, but it doesn't matter in this particular case, because we're going to clean the DB anyway.
         */
        unlockManager.delegate.setupCoreData()

        _ = self.usersManager.clean().done { [weak self] in
            completion()
            self?.finishLockFlow(.signIn(reason: "PinCodeViewControllerDelegate.cancel"))
        }
    }
}
