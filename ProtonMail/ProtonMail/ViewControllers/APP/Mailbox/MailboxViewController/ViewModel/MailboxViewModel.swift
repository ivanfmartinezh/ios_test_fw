//
//  MailboxViewModel.swift
//  Proton Mail - Created on 8/15/15.
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
import CoreData
import ProtonCore_DataModel
import ProtonCore_Services
import ProtonMailAnalytics

struct LabelInfo {
    let name: String

    init(name: String) {
        self.name = name
    }
}

class MailboxViewModel: StorageLimit, UpdateMailboxSourceProtocol {
    let labelID: LabelID
    let labelType: PMLabelType
    /// This field saves the label object of custom folder/label
    let label: LabelInfo?
    var messageLocation: Message.Location? {
        return Message.Location(rawValue: labelID.rawValue)
    }
    /// message service
    internal let user: UserManager
    internal let messageService: MessageDataService
    internal let eventsService: EventsFetching
    private let pushService: PushNotificationServiceProtocol
    /// fetch controller
    private(set) var fetchedResultsController: NSFetchedResultsController<NSFetchRequestResult>?
    private(set) var unreadFetchedResult: NSFetchedResultsController<NSFetchRequestResult>?

    private(set) var selectedIDs: Set<String> = Set()

    var selectedMoveToFolder: MenuLabel?
    var selectedLabelAsLabels: Set<LabelLocation> = Set()

    private let lastUpdatedStore: LastUpdatedStoreProtocol
    private let humanCheckStatusProvider: HumanCheckStatusProviderProtocol
    let coreDataContextProvider: CoreDataContextProviderProtocol
    private let conversationStateProvider: ConversationStateProviderProtocol
    private let contactGroupProvider: ContactGroupsProviderProtocol
    let labelProvider: LabelProviderProtocol
    private let contactProvider: ContactProviderProtocol
    let conversationProvider: ConversationProvider
    private let welcomeCarrouselCache: WelcomeCarrouselCacheProtocol

    var viewModeIsChanged: (() -> Void)?
    var sendHapticFeedback:(() -> Void)?
    let totalUserCountClosure: () -> Int
    var isHavingUser: Bool {
        return totalUserCountClosure() > 0
    }
    var isFetchingMessage: Bool { self.dependencies.updateMailbox.isFetching }
    private(set) var isFirstFetch: Bool = true

    private let dependencies: Dependencies

    /// `swipyCellDidSwipe` will be setting this value repeatedly during a swipe gesture.
    /// We only want to send a haptic signal one a state change.
    private var swipingTriggerActivated = false {
        didSet {
            if swipingTriggerActivated != oldValue {
                sendHapticFeedback?()
            }
        }
    }

    let toolbarActionProvider: ToolbarActionProvider
    let saveToolbarActionUseCase: SaveToolbarActionSettingsForUsersUseCase
    private let senderImageService: SenderImageService

    init(labelID: LabelID,
         label: LabelInfo?,
         labelType: PMLabelType,
         userManager: UserManager,
         pushService: PushNotificationServiceProtocol,
         coreDataContextProvider: CoreDataContextProviderProtocol,
         lastUpdatedStore: LastUpdatedStoreProtocol,
         humanCheckStatusProvider: HumanCheckStatusProviderProtocol,
         conversationStateProvider: ConversationStateProviderProtocol,
         contactGroupProvider: ContactGroupsProviderProtocol,
         labelProvider: LabelProviderProtocol,
         contactProvider: ContactProviderProtocol,
         conversationProvider: ConversationProvider,
         eventsService: EventsFetching,
         dependencies: Dependencies,
         welcomeCarrouselCache: WelcomeCarrouselCacheProtocol = userCachedStatus,
         toolbarActionProvider: ToolbarActionProvider,
         saveToolbarActionUseCase: SaveToolbarActionSettingsForUsersUseCase,
         senderImageService: SenderImageService,
         totalUserCountClosure: @escaping () -> Int
    ) {
        self.labelID = labelID
        self.label = label
        self.labelType = labelType
        self.user = userManager
        self.messageService = userManager.messageService
        self.eventsService = eventsService
        self.coreDataContextProvider = coreDataContextProvider
        self.pushService = pushService
        self.lastUpdatedStore = lastUpdatedStore
        self.humanCheckStatusProvider = humanCheckStatusProvider
        self.conversationStateProvider = conversationStateProvider
        self.contactGroupProvider = contactGroupProvider
        self.contactProvider = contactProvider
        self.totalUserCountClosure = totalUserCountClosure
        self.labelProvider = labelProvider
        self.conversationProvider = conversationProvider
        self.dependencies = dependencies
        self.welcomeCarrouselCache = welcomeCarrouselCache
        self.toolbarActionProvider = toolbarActionProvider
        self.saveToolbarActionUseCase = saveToolbarActionUseCase
        self.senderImageService = senderImageService
        self.conversationStateProvider.add(delegate: self)
        self.dependencies.updateMailbox.setup(source: self)
    }

    /// localized navigation title. overrride it or return label name
    var localizedNavigationTitle: String {
        guard let location = Message.Location(labelID) else {
            return label?.name ?? ""
        }
        return location.localizedTitle
    }

    var currentViewMode: ViewMode {
        conversationStateProvider.viewMode
    }

    var locationViewMode: ViewMode {
        let singleMessageOnlyLabels: [Message.Location] = [.draft, .sent, .scheduled]
        if let location = Message.Location(labelID),
           singleMessageOnlyLabels.contains(location),
           self.conversationStateProvider.viewMode == .conversation {
            return .singleMessage
        }
        return self.conversationStateProvider.viewMode
    }

    var isTrashOrSpam: Bool {
        let ids = [
            LabelLocation.trash.labelID,
            LabelLocation.spam.labelID
        ]
        return ids.contains(self.labelID)
    }

    var isRequiredHumanCheck: Bool {
        get { return self.humanCheckStatusProvider.isRequiredHumanCheck }
        set { self.humanCheckStatusProvider.isRequiredHumanCheck = newValue }
    }

    var isCurrentUserSelectedUnreadFilterInInbox: Bool {
        get {
            return self.user.isUserSelectedUnreadFilterInInbox
        }
        set {
            self.user.isUserSelectedUnreadFilterInInbox = newValue
        }
    }

    var actionSheetViewModel: MailListActionSheetViewModel {
        return .init(labelId: labelId.rawValue,
                     title: .actionSheetTitle(selectedCount: selectedIDs.count, viewMode: locationViewMode))
    }

    // Needs refactor to test

    var isInDraftFolder: Bool {
        return labelID.rawValue == Message.Location.draft.rawValue
    }

    var countOfFetchedObjects: Int {
        return fetchedResultsController?.fetchedObjects?.count ?? 0
    }

    var selectedMessages: [MessageEntity] {
        fetchedResultsController?.fetchedObjects?
            .compactMap { $0 as? Message }
            .filter { selectedIDs.contains($0.messageID) }
            .map(MessageEntity.init) ?? []
    }

    var selectedConversations: [ConversationEntity] {
        fetchedResultsController?.fetchedObjects?
            .compactMap { $0 as? ContextLabel }
            .compactMap(\.conversation)
            .filter { selectedIDs.contains($0.conversationID) }
            .map(ConversationEntity.init) ?? []
    }

    var selectedItems: [MailboxItem] {
        switch locationViewMode {
        case .conversation:
            return selectedConversations.map(MailboxItem.conversation)
        case .singleMessage:
            return selectedMessages.map(MailboxItem.message)
        }
    }

    // Fetched by each cell in the view, use lazy to avoid fetching too much times
    lazy private(set) var customFolders: [LabelEntity] = {
        labelProvider.getCustomFolders()
    }()

    var allEmails: [Email] {
        return contactProvider.getAllEmails()
    }

    func contactGroups() -> [ContactGroupVO] {
        contactGroupProvider.getAllContactGroupVOs()
    }

    func fetchContacts() {
        contactProvider.fetchContacts(completion: nil)
    }

    /// create a fetch controller with labelID
    ///
    /// - Returns: fetched result controller
    private func makeFetchController(isUnread: Bool) -> NSFetchedResultsController<NSFetchRequestResult>? {
        let isAscending = self.labelID == Message.Location.scheduled.labelID ? true : false
        let fetchedResultsController = messageService.fetchedResults(by: self.labelID,
                                                                     viewMode: self.locationViewMode,
                                                                     isUnread: isUnread,
                                                                     isAscending: isAscending)
        if let fetchedResultsController = fetchedResultsController {
            do {
                try fetchedResultsController.performFetch()
            } catch { }
        }
        return fetchedResultsController
    }

    private func makeUnreadFetchController() -> NSFetchedResultsController<NSFetchRequestResult> {
        let fetchController: NSFetchedResultsController<NSFetchRequestResult>

        switch locationViewMode {
        case .singleMessage:
            let moc = coreDataContextProvider.mainContext
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: LabelUpdate.Attributes.entityName)
            fetchRequest.predicate = NSPredicate(format: "(%K == %@) AND (%K == %@)",
                                                 LabelUpdate.Attributes.labelID,
                                                 self.labelID.rawValue,
                                                 LabelUpdate.Attributes.userID,
                                                 self.user.userInfo.userId)
            let strComp = NSSortDescriptor(key: LabelUpdate.Attributes.labelID,
                                           ascending: true,
                                           selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
            fetchRequest.sortDescriptors = [strComp]
            fetchController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: moc, sectionNameKeyPath: nil, cacheName: nil)
        case .conversation:
            let moc = coreDataContextProvider.mainContext
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: ConversationCount.Attributes.entityName)
            fetchRequest.predicate = NSPredicate(format: "(%K == %@) AND (%K == %@)",
                                                 ConversationCount.Attributes.userID,
                                                 self.user.userInfo.userId,
                                                 ConversationCount.Attributes.labelID,
                                                 self.labelID.rawValue)
            let strComp = NSSortDescriptor(key: ConversationCount.Attributes.labelID,
                                           ascending: true,
                                           selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
            fetchRequest.sortDescriptors = [strComp]
            fetchController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: moc, sectionNameKeyPath: nil, cacheName: nil)
        }

        do {
            try fetchController.performFetch()
        } catch {
        }

        return fetchController
    }

    /// Setup fetch controller to fetch message of specific labelID
    ///
    /// - Parameter delegate: delegate from viewcontroller
    /// - Parameter isUnread: the flag used to filter the unread message or not
    func setupFetchController(_ delegate: NSFetchedResultsControllerDelegate?, isUnread: Bool = false) {
        self.fetchedResultsController = self.makeFetchController(isUnread: isUnread)
        self.fetchedResultsController?.delegate = delegate

        self.unreadFetchedResult = self.makeUnreadFetchController()
        self.unreadFetchedResult?.delegate = delegate
    }

    /// reset delegate if fetch controller is valid
    func resetFetchedController() {
        if let controller = self.fetchedResultsController {
            controller.delegate = nil
            self.fetchedResultsController = nil
        }
    }

    // MARK: - table view usesage

    /// get section cound
    ///
    /// - Returns:
    func sectionCount() -> Int {
        return fetchedResultsController?.numberOfSections() ?? 0
    }

    /// get row count of a section
    ///
    /// - Parameter section: section index
    /// - Returns: row count
    func rowCount(section: Int) -> Int {
        return fetchedResultsController?.numberOfRows(in: section) ?? 0
    }

    /// get message item from a indexpath
    ///
    /// - Parameter index: table cell indexpath
    /// - Returns: message (nil)
    func item(index: IndexPath) -> MessageEntity? {
        guard !index.isEmpty, let sections = self.fetchedResultsController?.numberOfSections() else {
            return nil
        }
        guard sections > index.section else {
            return nil
        }

        guard let rows = self.fetchedResultsController?.numberOfRows(in: index.section) else {
            return nil
        }

        guard rows > index.row else {
            return nil
        }

        guard let msg = fetchedResultsController?.object(at: index) as? Message else {
            return nil
        }

        return MessageEntity(msg)
    }

    func itemOfConversation(index: IndexPath, collectBreadcrumbs: Bool = false) -> ConversationEntity? {
        guard let conversation = itemOfRawConversation(indexPath: index, collectBreadcrumbs: collectBreadcrumbs) else {
            return nil
        }
        return ConversationEntity(conversation)
    }

    func mailboxItem(at indexPath: IndexPath) -> MailboxItem? {
        if let message = item(index: indexPath) {
            return .message(message)
        } else if let conversation = itemOfConversation(index: indexPath) {
            return .conversation(conversation)
        } else {
            return nil
        }
    }

    private func itemOfRawConversation(indexPath: IndexPath, collectBreadcrumbs: Bool) -> Conversation? {
        guard !indexPath.isEmpty else { return nil }

        guard let frc = fetchedResultsController else { return nil }


        let sections = frc.numberOfSections()

        guard sections > indexPath.section else { return nil }

        let rows = frc.numberOfRows(in: indexPath.section)

        guard rows > indexPath.row else { return nil }

        let managedObject = frc.object(at: indexPath)

        guard let contextLabel = managedObject as? ContextLabel else { return nil }

        return contextLabel.conversation
    }

    func isObjectUpdated(objectID: ObjectID) -> Bool {
        guard let obj = try? self.fetchedResultsController?.managedObjectContext.existingObject(with: objectID.rawValue) else {
            return false
        }
        return obj.isUpdated
    }

    // MARK: - operations

    /// clean up the rate/review items
    func cleanReviewItems() {
        self.user.cacheService.cleanReviewItems()
    }

    /// check if need to load more older messages
    ///
    /// - Parameter index: the current table index
    /// - Returns: yes or no
    func loadMore(index: IndexPath) -> Bool {
        guard let number = self.fetchedResultsController?.numberOfSections() else {
            return false
        }
        guard number > index.section else {
            return false
        }
        guard let total = self.fetchedResultsController?.numberOfRows(in: index.section) else {
            return false
        }
        if total - index.row <= 2 {
            return true
        }
        return false
    }

    /// the latest cache time of current location
    ///
    /// - Returns: location cache info
    func lastUpdateTime() -> LabelCountEntity? {
        lastUpdatedStore.lastUpdate(by: labelID, userID: user.userID, type: locationViewMode)
    }

    func getLastUpdateTimeText() -> String {
        var result = LocalString._mailblox_last_update_time_more_than_1_hour

        if let updateTime = lastUpdatedStore.lastEventUpdateTime(userID: self.user.userID) {
            let time = updateTime.timeIntervalSinceReferenceDate
            let differenceFromNow = Int(Date().timeIntervalSinceReferenceDate - time)

            guard differenceFromNow >= 0 else {
                return ""
            }

            let hour = differenceFromNow / 3600
            let minute = differenceFromNow / 60

            if hour >= 1 {
                result = LocalString._mailblox_last_update_time_more_than_1_hour
            } else if minute < 60 && minute >= 1 {
                result = String.localizedStringWithFormat(LocalString._mailblox_last_update_time, minute)
            } else if minute < 1 && differenceFromNow < 60 {
                result = LocalString._mailblox_last_update_time_just_now
            }
        }
        return result
    }

    func updateListAndCounter(complete: @escaping (LabelCountEntity?) -> Void) {
        let group = DispatchGroup()
        group.enter()
        self.messageService.updateMessageCount {
            group.leave()
        }

        group.enter()
        self.fetchMessages(time: 0, forceClean: false, isUnread: false) { _ in
            group.leave()
        }

        group.notify(queue: DispatchQueue.main) {
            delay(0.2) {
                // For operation context sync with main context
                let count = self.user.labelService.lastUpdate(by: self.labelID, userID: self.user.userID)
                complete(count)
            }

        }
    }

    func getEmptyFolderCheckMessage(count: Int) -> String {
        let format = self.currentViewMode == .conversation ? LocalString._clean_conversation_warning: LocalString._clean_message_warning
        let message = String(format: format, count)
        return message
    }

    func emptyFolder() {
        let isTrashFolder = self.labelID == LabelLocation.trash.labelID
        let location: Message.Location = isTrashFolder ? .trash: .spam
        self.messageService.empty(location: location)
    }

    /// process push
    func processCachedPush() {
        self.pushService.processCachedLaunchOptions()
    }

    func object(by object: NSManagedObjectID) -> Message? {
        if let obj = self.fetchedResultsController?.managedObjectContext.object(with: object) as? Message {
            return obj
        }
        return nil
    }

    func fetchConversationDetail(conversationID: ConversationID, completion: @escaping () -> Void) {
        conversationProvider.fetchConversation(with: conversationID, includeBodyOf: nil, callOrigin: "MailboxViewModel") { result in
            assert(result.error == nil)

            DispatchQueue.main.async {
                completion()
            }
        }
    }

    final func resetNotificationMessage() {
        messageService.pushNotificationMessageID = nil
    }

    /// this is a workaground for draft. somehow back from the background the fetch controller can't get the latest data. remove this when fix this issue
    ///
    /// - Returns: bool
    func reloadTable() -> Bool {
        return labelID.rawValue == Message.Location.draft.rawValue
    }

    func mark(messages: [MessageEntity], unread: Bool = true) {
        messageService.mark(messageObjectIDs: messages.map(\.objectID.rawValue), labelID: self.labelID, unRead: unread)
    }

    func label(msg message: MessageEntity, with labelID: LabelID, apply: Bool = true) {
        messageService.label(messages: [message], label: labelID, apply: apply, shouldFetchEvent: false)
    }

    func deleteSelectedIDs() {
        switch locationViewMode {
        case .conversation:
            deletePermanently(conversationIDs: selectedConversations.map(\.conversationID))
        case .singleMessage:
            messageService.delete(messages: selectedMessages, label: self.labelID)
        }
    }

    private func deletePermanently(conversationIDs: [ConversationID]) {
        conversationProvider.deleteConversations(with: conversationIDs, labelID: self.labelID) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.eventsService.fetchEvents(labelID: self.labelId)
            case .failure(let error):
                assertionFailure("\(error)")
            }
        }
    }

    func checkStorageIsCloseLimit() {
        let usedStorageSpace = user.userInfo.usedSpace
        let maxStorageSpace = user.userInfo.maxSpace
        checkSpace(usedStorageSpace,
                   maxSpace: maxStorageSpace,
                   userID: user.userInfo.userId)
    }

    func handleActionSheetAction(_ action: MessageViewActionSheetAction) {
        switch action {
        case .unstar:
            handleUnstarAction(on: selectedItems)
        case .star:
            handleStarAction(on: selectedItems)
        case .markRead:
            handleMarkReadAction(on: selectedItems)
        case .markUnread:
            handleMarkUnreadAction(on: selectedItems)
        case .trash:
            handleRemoveAction(on: selectedItems)
        case .archive:
            handleMoveToArchiveAction(on: selectedItems)
        case .spam:
            handleMoveToSpamAction(on: selectedItems)
        case .labelAs, .moveTo:
            // TODO: add action
            break
        case .inbox:
            handleMoveToInboxAction(on: selectedItems)
        case .delete, .dismiss, .toolbarCustomization, .reply, .replyAll, .forward, .print, .viewHeaders, .viewHTML, .reportPhishing, .spamMoveToInbox, .viewInDarkMode, .viewInLightMode, .more, .replyOrReplyAll, .saveAsPDF, .replyInConversation, .forwardInConversation, .replyOrReplyAllInConversation, .replyAllInConversation:
            break
        }
    }

    func getTimeOfItem(at indexPath: IndexPath) -> Date? {
        mailboxItem(at: indexPath)?.time(labelID: labelID)
    }

    func getOnboardingDestination() -> MailboxCoordinator.Destination? {
        guard let tourVersion = self.welcomeCarrouselCache.lastTourVersion else {
            return .onboardingForNew
        }
        if tourVersion == Constants.App.TourVersion {
            return nil
        } else {
            return .onboardingForUpdate
        }
    }

    private func handleMoveToInboxAction(on items: [MailboxItem]) {
        move(items: items, from: labelID, to: Message.Location.inbox.labelID)
    }

    private func handleMoveToArchiveAction(on items: [MailboxItem]) {
        move(items: items, from: labelID, to: Message.Location.archive.labelID)
    }

    private func handleMoveToSpamAction(on items: [MailboxItem]) {
        move(items: items, from: labelID, to: Message.Location.spam.labelID)
    }

    private func handleUnstarAction(on items: [MailboxItem]) {
        let starredItemIDs = items
            .filter(\.isStarred)
            .map(\.itemID)

        label(IDs: Set<String>(starredItemIDs), with: Message.Location.starred.labelID, apply: false)
    }

    private func handleStarAction(on items: [MailboxItem]) {
        let unstarredItemIDs = items
            .filter { !$0.isStarred }
            .map(\.itemID)

        label(IDs: Set<String>(unstarredItemIDs), with: Message.Location.starred.labelID, apply: true)
    }

    private func handleMarkReadAction(on items: [MailboxItem]) {
        let unreadItemsIDs = items
            .filter { $0.isUnread(labelID: labelID) }
            .map(\.itemID)

        mark(IDs: Set(unreadItemsIDs), unread: false)
    }

    private func handleMarkUnreadAction(on items: [MailboxItem]) {
        let readItemsIDs = items
            .filter { !$0.isUnread(labelID: labelID) }
            .map(\.itemID)

        mark(IDs: Set(readItemsIDs), unread: true)
    }

    private func handleRemoveAction(on items: [MailboxItem]) {
        move(items: items, from: labelID, to: Message.Location.trash.labelID)
    }

    func searchForScheduled(swipeSelectedID: [String],
                            displayAlert: @escaping (Int) -> Void,
                            continueAction: @escaping () -> Void) {
        swipeSelectedID.forEach { selectedIDs.insert($0) }
        let selectedNum: Int
        switch locationViewMode {
        case .conversation:
            selectedNum = selectedConversations.filter { $0.contains(of: .scheduled) }.count
        case .singleMessage:
            selectedNum = selectedMessages.filter { $0.contains(location: .scheduled) }.count
        }
        if selectedNum == 0 {
            continueAction()
        } else {
            displayAlert(selectedNum)
        }
    }

    func fetchSenderImageIfNeeded(
        item: MailboxItem,
        isDarkMode: Bool,
        scale: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) {
        let senderImageRequestInfo: SenderImageRequestInfo?
        switch item {
        case .message(let messageEntity):
            senderImageRequestInfo = messageEntity.getSenderImageRequestInfo(isDarkMode: isDarkMode)
        case .conversation(let conversationEntity):
            senderImageRequestInfo = conversationEntity.getSenderImageRequestInfo(isDarkMode: isDarkMode)
        }

        guard let info = senderImageRequestInfo else {
            completion(nil)
            return
        }

        dependencies.fetchSenderImage
            .callbackOn(.main)
            .execute(
                params: .init(
                    senderImageRequestInfo: info,
                    scale: scale,
                    userID: user.userID
                )) { result in
                    switch result {
                    case .success(let image):
                        completion(image)
                    case .failure:
                        completion(nil)
                    }
            }
    }
}

// MARK: - Data fetching methods
extension MailboxViewModel {

    func fetchMessages(time: Int, forceClean: Bool, isUnread: Bool, completion: @escaping (Error?) -> Void) {
        switch self.locationViewMode {
        case .singleMessage:
            dependencies.fetchMessages.execute(
                endTime: time,
                isUnread: isUnread,
                callback: { result in
                    completion(result.error)
                },
                onMessagesRequestSuccess: nil)

        case .conversation:
            conversationProvider.fetchConversations(for: self.labelID, before: time, unreadOnly: isUnread, shouldReset: forceClean) { result in
                switch result {
                case .success:
                    completion(nil)
                case .failure(let error):
                    completion(error)
                }
            }
        }
    }

    func updateMailbox(
        showUnreadOnly: Bool,
        isCleanFetch: Bool,
        time: Int = 0,
        errorHandler: @escaping (Error) -> Void,
        completion: @escaping () -> Void
    ) {
        let isCurrentLocationEmpty = fetchedResultsController?.fetchedObjects?.isEmpty ?? true
        let fetchMessagesAtTheEnd = isCurrentLocationEmpty || isFirstFetch
        isFirstFetch = false

        dependencies.updateMailbox.exec(
            showUnreadOnly: showUnreadOnly,
            isCleanFetch: isCleanFetch,
            time: time,
            fetchMessagesAtTheEnd: fetchMessagesAtTheEnd,
            errorHandler: errorHandler,
            completion: completion
        )
    }

    func fetchMessageDetail(message: MessageEntity, callback: @escaping FetchMessageDetailUseCase.Callback) {
        let params: FetchMessageDetail.Params = .init(
            userID: user.userID,
            message: message,
            ignoreDownloaded: message.isDraft
        )
        dependencies.fetchMessageDetail
            .callbackOn(.main)
            .execute(params: params, callback: callback)
    }
}

// MARK: Message Actions
extension MailboxViewModel {
    func containsStarMessages(messageIDs: Set<String>) -> Bool {
        var starCount = 0
        switch self.locationViewMode {
        case .conversation:
            let conversations = self.conversationProvider.fetchLocalConversations(withIDs: NSMutableSet(set: messageIDs), in: coreDataContextProvider.mainContext)
            starCount = conversations.reduce(0) { (result, next) -> Int in
                if next.contains(of: Message.Location.starred.labelID.rawValue) {
                    return result + 1
                } else {
                    return result
                }
            }
        case .singleMessage:
            let messages = self.messageService.fetchMessages(withIDs: NSMutableSet(set: messageIDs), in: coreDataContextProvider.mainContext)
            starCount = messages.reduce(0) { (result, next) -> Int in
                if next.contains(label: .starred) {
                    return result + 1
                } else {
                    return result
                }
            }
        }
        return starCount > 0
    }

    func selectionContainsReadItems() -> Bool {
        selectedItems.contains { !$0.isUnread(labelID: labelID) }
    }

    func label(IDs messageIDs: Set<String>,
               with labelID: LabelID,
               apply: Bool,
               completion: (() -> Void)? = nil) {
        switch self.locationViewMode {
        case .singleMessage:
            let messages = selectedMessages.filter { messageIDs.contains($0.messageID.rawValue) }
            messageService.label(messages: messages, label: labelID, apply: apply)
        case .conversation:
            if apply {
                conversationProvider.label(conversationIDs: Array(messageIDs.map{ ConversationID($0) }), as: labelID, isSwipeAction: false) { [weak self] result in
                    defer {
                        completion?()
                    }
                    guard let self = self else { return }
                    if let _ = try? result.get() {
                        self.eventsService.fetchEvents(labelID: self.labelId)
                    }
                }
            } else {
                conversationProvider.unlabel(conversationIDs: Array(messageIDs.map{ ConversationID($0) }), as: labelID, isSwipeAction: false) { [weak self] result in
                    defer {
                        completion?()
                    }
                    guard let self = self else { return }
                    if let _ = try? result.get() {
                        self.eventsService.fetchEvents(labelID: self.labelId)
                    }
                }
            }
        }
    }

    func mark(IDs messageIDs: Set<String>,
              unread: Bool,
              completion: (() -> Void)? = nil) {
        switch self.locationViewMode {
        case .singleMessage:
            let messages = selectedMessages.filter { messageIDs.contains($0.messageID.rawValue) }
            messageService.mark(messageObjectIDs: messages.map(\.objectID.rawValue), labelID: self.labelID, unRead: unread)
            completion?()
        case .conversation:
            if unread {
                conversationProvider.markAsUnread(conversationIDs: Array(messageIDs.map{ ConversationID($0) }), labelID: self.labelID) { [weak self] result in
                    defer {
                        completion?()
                    }
                    guard let self = self else { return }
                    if let _ = try? result.get() {
                        self.eventsService.fetchEvents(labelID: self.labelId)
                    }
                }
            } else {
                conversationProvider.markAsRead(conversationIDs: Array(messageIDs.map{ ConversationID($0) }), labelID: self.labelId) { [weak self] result in
                    defer {
                        completion?()
                    }
                    guard let self = self else { return }
                    if let _ = try? result.get() {
                        self.eventsService.fetchEvents(labelID: self.labelId)
                    }
                }
            }
        }
    }

    func moveSelectedIDs(from fLabel: LabelID, to tLabel: LabelID) {
        move(items: selectedItems, from: fLabel, to: tLabel)
    }

    func move(items: [MailboxItem], from fLabel: LabelID, to tLabel: LabelID) {
        move(items: MailboxItemGroup(mailboxItems: items), from: fLabel, to: tLabel)
    }

    private func move(items: MailboxItemGroup, from fLabel: LabelID, to tLabel: LabelID) {
        switch items {
        case .messages(let messages):
            var fLabels: [LabelID] = []

            for msg in messages {
                // the label that is not draft, sent, starred, allmail
                fLabels.append(msg.firstValidFolder() ?? fLabel)
            }

            messageService.move(messages: messages, from: fLabels, to: tLabel)
        case .conversations(let conversations):
            conversationProvider.move(
                conversationIDs: conversations.map(\.conversationID),
                from: fLabel,
                to: tLabel,
                isSwipeAction: false,
                callOrigin: "MailboxViewModel - move"
            ) { [weak self] result in
                guard let self = self else { return }
                if let _ = try? result.get() {
                    self.eventsService.fetchEvents(labelID: self.labelId)
                }
            }
        case .empty:
            break
        }
    }
}

// Message Selection
extension MailboxViewModel {
    func select(id: String) {
        self.selectedIDs.insert(id)
    }

    func removeSelected(id: String) {
        self.selectedIDs.remove(id)
    }

    func removeAllSelectedIDs() {
        self.selectedIDs.removeAll()
    }

    func selectionContains(id: String) -> Bool {
        return self.selectedIDs.contains(id)
    }

}

// MARK: - Swipe actions
extension MailboxViewModel {
    func isSwipeActionValid(_ action: MessageSwipeAction, item: MailboxItem) -> Bool {
        guard let location = messageLocation else {
            return true
        }

        let helper = MailBoxSwipeActionHelper()

        let result: Bool
        if location == .allmail {
            switch item {
            case .message(let message):
                result = helper.checkIsSwipeActionValidOnMessage(
                    isDraft: message.isDraft,
                    isUnread: message.unRead,
                    isStar: message.contains(location: .starred),
                    isInTrash: message.contains(location: .trash),
                    isInArchive: message.contains(location: .archive),
                    isInSent: message.contains(location: .sent),
                    isInSpam: message.contains(location: .spam),
                    action: action
                )
            case .conversation(let conversation):
                result = helper.checkIsSwipeActionValidOnConversation(
                    isUnread: conversation.isUnread(labelID: labelID),
                    isStar: conversation.starred,
                    isInArchive: conversation.contains(of: Message.Location.archive.labelID),
                    isInSpam: conversation.contains(of: Message.Location.spam.labelID),
                    isInSent: conversation.contains(of: Message.Location.sent.labelID),
                    action: action
                )
            }
        } else {
            result = helper.checkIsSwipeActionValidOn(location: location, action: action)
        }
        return result
    }

    func convertSwipeActionTypeToMessageSwipeAction(_ type: SwipeActionSettingType,
                                                    isStarred: Bool,
                                                    isUnread: Bool) -> MessageSwipeAction {
        switch type {
        case .none:
            return .none
        case .trash:
            return .trash
        case .spam:
            return .spam
        case .starAndUnstar:
            return isStarred ? .unstar : .star
        case .archive:
            return .archive
        case .readAndUnread:
            return isUnread ? .read : .unread
        case .labelAs:
            return .labelAs
        case .moveTo:
            return .moveTo
        }
    }

    func handleSwipeAction(_ action: MessageSwipeAction, on item: MailboxItem) {
        switch action {
        case .unstar:
            handleUnstarAction(on: [item])
        case .star:
            handleStarAction(on: [item])
        case .read:
            handleMarkReadAction(on: [item])
        case .unread:
            handleMarkUnreadAction(on: [item])
        case .trash:
            handleRemoveAction(on: [item])
        case .archive:
            handleMoveToArchiveAction(on: [item])
        case .spam:
            handleMoveToSpamAction(on: [item])
        case .labelAs, .moveTo, .none:
            break
        }
    }

    func swipyCellDidSwipe(triggerActivated: Bool) {
        /*
         This method is called continuously during a swipe.
         If the trigger has been activated, the `triggerActivated` value is `true` on every  subsequent call, so it's
         impossible to intercept the exact moment of activation without storing this value to a property and checking
         against `oldValue`.
         */
        swipingTriggerActivated = triggerActivated
    }
}

extension MailboxViewModel: ConversationStateServiceDelegate {
    func viewModeHasChanged(viewMode: ViewMode) {
        viewModeIsChanged?()
    }
}

extension MailboxViewModel {

    struct Dependencies {
        let fetchMessages: FetchMessagesUseCase
        let updateMailbox: UpdateMailboxUseCase
        let fetchMessageDetail: FetchMessageDetailUseCase
        let fetchSenderImage: FetchSenderImageUseCase
    }
}

// MARK: - Misc

extension String {
    static func actionSheetTitle(selectedCount: Int, viewMode: ViewMode) -> String {
        switch viewMode {
        case .singleMessage:
            return .localizedStringWithFormat(LocalString._general_message, selectedCount)
        case .conversation:
            return .localizedStringWithFormat(LocalString._general_conversation, selectedCount)
        }
    }
}
