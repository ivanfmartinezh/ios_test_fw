// Copyright (c) 2021 Proton AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Mail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Mail. If not, see https://www.gnu.org/licenses/.

import Foundation
import ProtonCore_Networking
import ProtonCore_Services
import ProtonCore_UIFoundations

protocol UndoActionManagerProtocol {
    func addUndoToken(_ token: UndoTokenData, undoActionType: UndoAction?)
    func addUndoTokens(_ tokens: [String], undoActionType: UndoAction?)
    func showUndoSendBanner(for messageID: MessageID)
    func register(handler: UndoActionHandlerBase)
    func requestUndoAction(undoTokens: [String], completion: ((Bool) -> Void)?)
    func calculateUndoActionBy(labelID: LabelID) -> UndoAction?
    func addTitleWithAction(title: String, action: UndoAction)
}

enum UndoAction: Equatable {
    case send
    case spam
    case trash
    case archive
    case custom(LabelID)
}

final class UndoActionManager: UndoActionManagerProtocol {
    enum Const {
        // The time we wait for the undo action token arrived.
        // Once the time passed the threshold, we do not show the undo action banner.
        static let delayThreshold: TimeInterval = 4.0
    }

    struct UndoModel {
        let action: UndoAction
        let title: String
        let bannerDisplayTime: Date
    }

    private let apiService: APIService
    private let internetStatusProvider: InternetConnectionStatusProvider
    private let contextProvider: CoreDataContextProviderProtocol
    private var getEventFetching: () -> EventsFetching?
    private var getUserManager: () -> UserManager?
    private(set) weak var handler: UndoActionHandlerBase? {
        didSet {
            undoTitles.removeAll()
        }
    }

    private(set) var undoTitles: [UndoModel] = []

    init(
        apiService: APIService,
        internetStatusProvider: InternetConnectionStatusProvider,
        contextProvider: CoreDataContextProviderProtocol,
        getEventFetching: @escaping () -> EventsFetching?,
        getUserManager: @escaping () -> UserManager?
    ) {
        self.apiService = apiService
        self.internetStatusProvider = internetStatusProvider
        self.contextProvider = contextProvider
        self.getEventFetching = getEventFetching
        self.getUserManager = getUserManager
    }

    /// Trigger the handler to display the undo action banner if it is registered.
    func addUndoToken(_ token: UndoTokenData, undoActionType: UndoAction?) {
        addUndoTokens([token.token], undoActionType: undoActionType)
    }

    func addUndoTokens(_ tokens: [String], undoActionType: UndoAction?) {
        guard let type = undoActionType,
              let index = undoTitles.firstIndex(where: { $0.action == type }),
              let item = undoTitles[safe: index] else {
            return
        }
        if Date().timeIntervalSince1970 - item.bannerDisplayTime.timeIntervalSince1970 < Const.delayThreshold {
            handler?.showUndoAction(undoTokens: tokens, title: item.title)
        }
        undoTitles.remove(at: index)
    }

    /// Trigger the handler to display the undo send banner
    func showUndoSendBanner(for messageID: MessageID) {
        DispatchQueue.main.async {
            guard let targetVC = self.handler else { return }

            typealias Key = PMBanner.UserInfoKey
            PMBanner
                .getBanners(in: targetVC)
                .filter {
                    $0.userInfo?[Key.type.rawValue] as? String == Key.sending.rawValue &&
                    $0.userInfo?[Key.messageID.rawValue] as? String == messageID.rawValue
                }
                .forEach { $0.dismiss(animated: false) }

            let delaySeconds = max(targetVC.delaySendSeconds, 1)
            let banner = PMBanner(message: LocalString._message_sent_ok_desc,
                                  style: PMBannerNewStyle.info,
                                  dismissDuration: TimeInterval(delaySeconds),
                                  bannerHandler: PMBanner.dismiss)
            if delaySeconds > 1 {
                let buttonTitle = LocalString._messages_undo_action
                banner.addButton(text: buttonTitle) { [weak self, weak banner] _ in
                    banner?.dismiss(animated: true)
                    self?.requestUndoSendAction(messageID: messageID) { isSuccess in
                        if isSuccess {
                            self?.showComposer(for: messageID)
                        }
                    }
                }
            }
            banner.show(at: .bottom, on: targetVC)
        }
    }

    /// Register the current handler of undo action.
    func register(handler: UndoActionHandlerBase) {
        self.handler = handler
    }

    /// Add the displayed title and action of the banner to the cache in order to match with the undo token.
    func addTitleWithAction(title: String, action: UndoAction) {
        undoTitles.append(UndoModel(action: action, title: title, bannerDisplayTime: Date()))
    }

    func requestUndoAction(undoTokens: [String], completion: ((Bool) -> Void)?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let requests = undoTokens.map(UndoActionRequest.init)

            let group = DispatchGroup()
            var atLeastOneRequestFailed = false
            requests.forEach { [unowned self] request in
                group.enter()
                self.apiService.exec(route: request) { (result: Result<UndoActionResponse, ResponseError>) in
                    if result.error != nil {
                        atLeastOneRequestFailed = true
                    }
                    group.leave()
                }
            }
            group.wait()

            if atLeastOneRequestFailed {
                completion?(false)
            } else {
                let labelID = Message.Location.allmail.labelID
                self.getEventFetching()?.fetchEvents(labelID: labelID)
                completion?(true)
            }
        }
    }

    func calculateUndoActionBy(labelID: LabelID) -> UndoAction? {
        var type: UndoAction?
        switch labelID {
        case Message.Location.trash.labelID:
            type = .trash
        case Message.Location.archive.labelID:
            type = .archive
        case Message.Location.spam.labelID:
            type = .spam
        default:
            if !labelID.rawValue.isEmpty,
               Message.Location(labelID) == nil {
                type = .custom(labelID)
            }
        }
        return type
    }
}

// MARK: Undo send

extension UndoActionManager {
    // Call undo send api to cancel sent message
    // The undo send action is time sensitive, put in queue doesn't make sense
    func requestUndoSendAction(messageID: MessageID, completion: ((Bool) -> Void)?) {
        let request = UndoSendRequest(messageID: messageID)
        apiService.exec(route: request) { [weak self] (result: Result<UndoSendResponse, ResponseError>) in
            switch result {
            case .success:
                let labelID = Message.Location.allmail.labelID
                self?.getEventFetching()?
                    .fetchEvents(byLabel: labelID,
                                 notificationMessageID: nil,
                                 completion: { _ in
                                     completion?(true)
                                 })
            case .failure:
                completion?(false)
            }
        }
    }

    private func showComposer(for messageID: MessageID) {
        #if !APP_EXTENSION
            guard let message = message(id: messageID),
                  let user = getUserManager() else { return }

            let composer = ComposerViewFactory.makeComposer(
                msg: message,
                action: .openDraft,
                user: user,
                contextProvider: contextProvider,
                isEditingScheduleMsg: false,
                userIntroductionProgressProvider: userCachedStatus,
                scheduleSendEnableStatusProvider: userCachedStatus,
                internetStatusProvider: internetStatusProvider
            )

            guard let presentingVC = self.handler?.composerPresentingVC else { return }
            presentingVC.present(composer, animated: true)
        #endif
    }

    private func message(id messageID: MessageID) -> Message? {
        let context = contextProvider.mainContext
        return Message.messageForMessageID(messageID.rawValue, inManagedObjectContext: context)
    }
}

protocol UndoActionHandlerBase: UIViewController {
    var delaySendSeconds: Int { get }
    var composerPresentingVC: UIViewController? { get }
    var undoActionManager: UndoActionManagerProtocol? { get }

    func showUndoAction(undoTokens: [String], title: String)
    func showActionRevertedBanner()
}

extension UndoActionHandlerBase {
    func showActionRevertedBanner() {
        let banner = PMBanner(message: LocalString._inbox_action_reverted_title,
                              style: PMBannerNewStyle.info,
                              dismissDuration: 1,
                              bannerHandler: PMBanner.dismiss)
        banner.show(at: .bottom, on: self)
    }

    func showUndoAction(undoTokens: [String], title: String) {
        DispatchQueue.main.async {
            let banner = PMBanner(message: title, style: PMBannerNewStyle.info, bannerHandler: PMBanner.dismiss)
            banner.addButton(text: LocalString._messages_undo_action) { [weak self] _ in
                self?.undoActionManager?.requestUndoAction(
                    undoTokens: undoTokens
                ) { [weak self] isSuccess in
                    DispatchQueue.main.async {
                        if isSuccess {
                            self?.showActionRevertedBanner()
                        }
                    }
                }
                banner.dismiss(animated: false)
            }
            banner.show(at: .bottom, on: self)
            // Dismiss other banner after the undo banner is shown
            delay(0.25) { [weak self] in
                self?.view.subviews
                    .compactMap { $0 as? PMBanner }
                    .filter { $0 != banner }
                    .forEach { $0.dismiss(animated: false) }
            }
        }
    }
}
