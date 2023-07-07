// Copyright (c) 2022 Proton AG
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

/// This use case fetches messages from backend and persists those messages locally.
/// It then requests the number of messages in each label/folder and also persists it locally.
protocol FetchMessagesUseCase: UseCase {

    /// Execute should only contain one callback. Having `onMessagesRequestSuccess` is a temporary
    /// trade off to be able to refactor little by little.
    /// - Parameters:
    ///   - endTime: timestamp to get messages earlier than this value.
    ///   - isUnread: whether we want only unread messages or not
    ///   - callback: callback when the use case has finished
    ///   - onMessagesRequestSuccess: callback when the messages have been received from backend successfully
    func execute(
        endTime: Int,
        isUnread: Bool,
        callback: @escaping UseCaseResult<Void>,
        onMessagesRequestSuccess: (() -> Void)?
    )
}

class FetchMessages: FetchMessagesUseCase {
    private let params: Parameters
    private let dependencies: Dependencies

    init(params: Parameters, dependencies: Dependencies) {
        self.params = params
        self.dependencies = dependencies
    }

    func execute(
        endTime: Int,
        isUnread: Bool,
        callback: @escaping UseCaseResult<Void>,
        onMessagesRequestSuccess: (() -> Void)?
    ) {
        requestMessages(
            endTime: endTime, isUnread: isUnread, callback: callback, onFetchSuccess: onMessagesRequestSuccess
        )
    }
}

// MARK: Private methods

extension FetchMessages {

    private func requestMessages(
        endTime: Int,
        isUnread: Bool,
        callback: @escaping UseCaseResult<Void>,
        onFetchSuccess: (() -> Void)?
    ) {
        dependencies
            .messageDataService
            .fetchMessages(
                labelID: params.labelID,
                endTime: endTime,
                fetchUnread: isUnread
            ) { [weak self] _, result in
                do {
                    let response = try result.get()
                    onFetchSuccess?()
                    try self?.persistOnLocalStorageMessages(isUnread: isUnread, messagesData: response)
                    self?.runOnMainThread { callback(.success(())) }
                } catch {
                    self?.runOnMainThread { callback(.failure(error)) }
                }
            }
    }

    private func persistOnLocalStorageMessages(isUnread: Bool, messagesData: [String: Any]) throws {
        try dependencies
            .cacheService
            .parseMessagesResponse(
                labelID: params.labelID,
                isUnread: isUnread,
                response: messagesData,
                idsOfMessagesBeingSent: dependencies.messageDataService.idsOfMessagesBeingSent()
            )

        requestMessagesCount()
    }

    private func requestMessagesCount() {
        dependencies.messageDataService.fetchMessagesCount { [weak self] (response: MessageCountResponse) in
            guard response.error == nil, let counts = response.counts else {
                return
            }
            self?.persistOnLocalStorageMessageCounts(counts: counts)
        }
    }

    private func persistOnLocalStorageMessageCounts(counts: [[String: Any]]) {
        dependencies.eventsService?.processEvents(messageCounts: counts)
    }
}

// MARK: Input structs

extension FetchMessages {

    struct Parameters {
        /// identifier for labels, folders and locations.
        let labelID: LabelID
    }

    struct Dependencies {
        let messageDataService: MessageDataServiceProtocol
        let cacheService: CacheServiceProtocol
        let eventsService: EventsServiceProtocol?

        init(
            messageDataService: MessageDataServiceProtocol,
            cacheService: CacheServiceProtocol,
            eventsService: EventsServiceProtocol?
        ) {
            self.messageDataService = messageDataService
            self.cacheService = cacheService
            self.eventsService = eventsService
        }
    }
}
