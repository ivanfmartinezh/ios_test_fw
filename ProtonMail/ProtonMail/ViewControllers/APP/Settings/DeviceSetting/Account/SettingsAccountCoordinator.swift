//
//  SettingsAccountCoordinator.swift
//  Proton Mail - Created on 12/12/18.
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

import ProtonCore_AccountDeletion
import ProtonCore_Log
import ProtonCore_Networking
import UIKit

// sourcery: mock
protocol SettingsAccountCoordinatorProtocol: AnyObject {
    func go(to dest: SettingsAccountCoordinator.Destination)
}

class SettingsAccountCoordinator: SettingsAccountCoordinatorProtocol {
    private let viewModel: SettingsAccountViewModel
    private let users: UsersManager

    private var user: UserManager {
        users.firstUser!
    }

    private weak var navigationController: UINavigationController?

    enum Destination: String {
        case recoveryEmail = "setting_notification"
        case loginPwd      = "setting_login_pwd"
        case mailboxPwd    = "setting_mailbox_pwd"
        case singlePwd     = "setting_single_password_segue"
        case displayName   = "setting_displayname"
        case signature     = "setting_signature"
        case mobileSignature = "setting_mobile_signature"
        case privacy = "setting_privacy"
        case labels = "labels_management"
        case folders = "folders_management"
        case conversation = "conversation_mode"
        case undoSend
        case searchContent
        case localStorage
        case deleteAccount
        case nextMsgAfterMove
        case blockList
    }

    init(navigationController: UINavigationController?, services: ServiceFactory) {
        self.navigationController = navigationController
        users = services.get()
        viewModel = SettingsAccountViewModelImpl(user: users.firstUser!)
    }

    func start(animated: Bool = false) {
        let viewController = SettingsAccountViewController(viewModel: self.viewModel, coordinator: self)
        self.navigationController?.pushViewController(viewController, animated: animated)
    }

    func go(to dest: Destination) {
        switch dest {
        case .blockList:
            openBlockList()
        case .singlePwd:
            openChangePassword(ofType: ChangeSinglePasswordViewModel.self)
        case .loginPwd:
            openChangePassword(ofType: ChangeLoginPWDViewModel.self)
        case .mailboxPwd:
            openChangePassword(ofType: ChangeMailboxPWDViewModel.self)
        case .recoveryEmail:
            openSettingDetail(ofType: ChangeNotificationEmailViewModel.self)
        case .displayName:
            openSettingDetail(ofType: ChangeDisplayNameViewModel.self)
        case .signature:
            openSettingDetail(ofType: ChangeSignatureViewModel.self)
        case .mobileSignature:
            openSettingDetail(ofType: ChangeMobileSignatureViewModel.self)
        case .privacy:
            openPrivacy()
        case .labels:
            openFolderManagement(type: .label)
        case .folders:
            openFolderManagement(type: .folder)
        case .conversation:
            openConversationSettings()
        case .undoSend:
            openUndoSendSettings()
        case .searchContent:
            openSearchContent()
        case .localStorage:
            openLocalStorage()
        case .deleteAccount:
            openAccountDeletion()
        case .nextMsgAfterMove:
            openNextMessageAfterMove()
        }
    }

    func follow(deepLink: DeepLink?) {
        guard let node = deepLink?.popFirst else {
            return
        }
        guard let destination = Destination(rawValue: node.name) else {
            return
        }
        go(to: destination)
    }

    private func openBlockList() {
        let incomingDefaultService = user.incomingDefaultService

        let unblockSender = UnblockSender(
            dependencies: .init(
                incomingDefaultService: incomingDefaultService,
                queueManager: sharedServices.get(by: QueueManager.self),
                userInfo: user.userInfo
            )
        )

        let viewModel = BlockedSendersViewModel(
            dependencies: .init(
                cacheUpdater: user.blockedSenderCacheUpdater,
                incomingDefaultService: incomingDefaultService,
                unblockSender: unblockSender
            )
        )
        let viewController = BlockedSendersViewController(viewModel: viewModel)
        navigationController?.show(viewController, sender: nil)
    }

    private func openChangePassword<T: ChangePasswordViewModel>(ofType viewModelType: T.Type) {
        let viewModel = T(user: user)
        let cpvc = ChangePasswordViewController(viewModel: viewModel)
        self.navigationController?.pushViewController(cpvc, animated: true)
    }

    private func openSettingDetail<T: SettingDetailsViewModel>(ofType viewModelType: T.Type) {
        let sdvc = SettingDetailViewController(nibName: nil, bundle: nil)
        sdvc.setViewModel(viewModelType.init(user: user))
        self.navigationController?.show(sdvc, sender: nil)
    }

    private func openPrivacy() {
        let viewModel = PrivacySettingViewModel(user: user, metaStrippingProvider: userCachedStatus)
        let viewController = SwitchToggleViewController(viewModel: viewModel)
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openFolderManagement(type: PMLabelType) {
        guard let navigationController = navigationController else { return }
        let router = LabelManagerRouter(navigationController: navigationController)
        let dependencies = LabelManagerViewModel.Dependencies(userManager: user)
        let viewModel = LabelManagerViewModel(router: router, type: type, dependencies: dependencies)
        let vc = LabelManagerViewController(viewModel: viewModel)
        navigationController.pushViewController(vc, animated: true)
    }

    private func openConversationSettings() {
        let viewModel = ConversationSettingViewModel(
            updateViewModeService: UpdateViewModeService(apiService: user.apiService),
            conversationStateService: user.conversationStateService,
            eventService: user.eventsService
        )
        let viewController = SwitchToggleViewController(viewModel: viewModel)
        navigationController?.show(viewController, sender: nil)
    }

    private func openUndoSendSettings() {
        let viewModel = UndoSendSettingViewModel(user: user, delaySeconds: user.userInfo.delaySendSeconds)
        let settingVC = SettingsSingleCheckMarkViewController(viewModel: viewModel)
        viewModel.set(uiDelegate: settingVC)
        self.navigationController?.pushViewController(settingVC, animated: true)
    }

    func openSearchContent() {
        guard let navController = navigationController else { return }
        let router = SettingsEncryptedSearchRouter(navigationController: navController)
        let viewModel = SettingsEncryptedSearchViewModel(router: router, dependencies: .init())
        let viewController = SettingsEncryptedSearchViewController(viewModel: viewModel)
        navController.pushViewController(viewController, animated: true)
    }

    func openLocalStorage() {
        guard let navController = navigationController else { return }
        let router = SettingsLocalStorageRouter(navigationController: navController)
        let viewModel = SettingsLocalStorageViewModel(router: router, dependencies: .init())
        let viewController = SettingsLocalStorageViewController(viewModel: viewModel)
        navController.pushViewController(viewController, animated: true)
    }
    
    private func openAccountDeletion() {
        guard let viewController = navigationController?.topViewController as? SettingsAccountViewController else {
            return
        }

        viewController.isAccountDeletionPending = true
        let accountDeletion = AccountDeletionService(api: user.apiService)
        accountDeletion.initiateAccountDeletionProcess(over: viewController) { [weak viewController] in
            viewController?.isAccountDeletionPending = false
        } completion: { [weak self] result in
            switch result {
            case .success:
                self?.processSuccessfulAccountDeletion()
            case .failure(let error):
                viewController.isAccountDeletionPending = false
                self?.presentAccountDeletionError(error)
            }
        }
    }
    
    private func processSuccessfulAccountDeletion() {
        users.logoutAfterAccountDeletion(user: user)
    }
    
    private func presentAccountDeletionError(_ error: AccountDeletionError) {
        let message: String?
        switch error {
        case let .apiMightBeBlocked(errorMessage, originalError):
            PMLog.error(originalError)
            message = errorMessage
        case .sessionForkingError(let errorMessage):
            message = errorMessage
        case .cannotDeleteYourself(let reason):
            message = reason.networkResponseMessageForTheUser
        case .deletionFailure(let errorMessage):
            message = errorMessage
        case .closedByUser:
            message = nil
        }
        
        guard let message = message else { return }
        
        // TODO: better error presentation
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addCloseAction()
        navigationController?.topViewController?.present(alert, animated: true, completion: nil)
    }

    private func openNextMessageAfterMove() {
        let viewModel = NextMessageAfterMoveViewModel(user, apiService: user.apiService)
        let viewController = SwitchToggleViewController(viewModel: viewModel)
        navigationController?.show(viewController, sender: nil)
    }
}
