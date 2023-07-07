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

import XCTest
import CoreData
import Groot
@testable import ProtonMail
import ProtonCore_TestingToolkit
import ProtonCore_DataModel
import ProtonCore_Networking
import ProtonCore_UIFoundations

class MailboxViewModelTests: XCTestCase {

    var sut: MailboxViewModel!
    var apiServiceMock: APIServiceMock!
    var coreDataService: CoreDataService!
    var humanCheckStatusProviderMock: HumanCheckStatusProviderProtocol!
    var userManagerMock: UserManager!
    var conversationStateProviderMock: MockConversationStateProviderProtocol!
    var contactGroupProviderMock: MockContactGroupsProviderProtocol!
    var labelProviderMock: MockLabelProviderProtocol!
    var contactProviderMock: MockContactProvider!
    var conversationProviderMock: MockConversationProvider!
    var eventsServiceMock: EventsServiceMock!
    var mockFetchLatestEventId: MockFetchLatestEventId!
    var welcomeCarrouselCache: WelcomeCarrouselCacheMock!
    var toolbarActionProviderMock: MockToolbarActionProvider!
    var saveToolbarActionUseCaseMock: MockSaveToolbarActionSettingsForUsersUseCase!
    var mockSenderImageStatusProvider: MockSenderImageStatusProvider!
    var imageTempUrl: URL!
    var mockFetchMessageDetail: MockFetchMessageDetail!

    var testContext: NSManagedObjectContext {
        coreDataService.mainContext
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        coreDataService = CoreDataService(container: MockCoreDataStore.testPersistentContainer)
        sharedServices.add(CoreDataService.self, for: coreDataService)

        apiServiceMock = APIServiceMock()
        apiServiceMock.sessionUIDStub.fixture = String.randomString(10)
        apiServiceMock.dohInterfaceStub.fixture = DohMock()
        let fakeAuth = AuthCredential(sessionID: "",
                                      accessToken: "",
                                      refreshToken: "",
                                      userName: "",
                                      userID: "1",
                                      privateKey: nil,
                                      passwordKeySalt: nil)
        let stubUserInfo = UserInfo(maxSpace: nil,
                                    usedSpace: nil,
                                    language: nil,
                                    maxUpload: nil,
                                    role: nil,
                                    delinquent: nil,
                                    keys: nil,
                                    userId: "1",
                                    linkConfirmation: nil,
                                    credit: nil,
                                    currency: nil,
                                    subscribed: nil)
        userManagerMock = UserManager(api: apiServiceMock,
                                      userInfo: stubUserInfo,
                                      authCredential: fakeAuth,
                                      mailSettings: nil,
                                      parent: nil)
        userManagerMock.conversationStateService.userInfoHasChanged(viewMode: .singleMessage)
        humanCheckStatusProviderMock = MockHumanCheckStatusProvider()
        conversationStateProviderMock = MockConversationStateProviderProtocol()
        contactGroupProviderMock = MockContactGroupsProviderProtocol()
        labelProviderMock = MockLabelProviderProtocol()
        contactProviderMock = MockContactProvider(coreDataContextProvider: coreDataService)
        conversationProviderMock = MockConversationProvider()
        eventsServiceMock = EventsServiceMock()
        mockFetchLatestEventId = MockFetchLatestEventId()
        welcomeCarrouselCache = WelcomeCarrouselCacheMock()
        toolbarActionProviderMock = MockToolbarActionProvider()
        saveToolbarActionUseCaseMock = MockSaveToolbarActionSettingsForUsersUseCase()
        mockSenderImageStatusProvider = .init()
        try loadTestMessage() // one message
        createSut(labelID: Message.Location.inbox.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)

        conversationProviderMock.fetchConversationStub.bodyIs { [unowned self] _, _, _, _, completion in
            completion(.success(Conversation(context: self.testContext)))
        }

        conversationProviderMock.fetchConversationCountsStub.bodyIs { _, _, completion in
            completion?(.success(()))
        }

        conversationProviderMock.fetchConversationsStub.bodyIs { _, _, _, _, _, completion in
            completion?(.success(()))
        }

        conversationProviderMock.labelStub.bodyIs { _, _, _, _, completion in
            completion?(.success(()))
        }

        conversationProviderMock.markAsReadStub.bodyIs { _, _, _, completion in
            completion?(.success(()))
        }

        conversationProviderMock.markAsUnreadStub.bodyIs { _, _, _, completion in
            completion?(.success(()))
        }

        conversationProviderMock.moveStub.bodyIs { _, _, _, _, _, _, completion in
            completion?(.success(()))
        }

        conversationProviderMock.unlabelStub.bodyIs { _, _, _, _, completion in
            completion?(.success(()))
        }

        // Prepare for api mock to write image data to disk
        imageTempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("senderImage", isDirectory: true)
        try FileManager.default.createDirectory(at: imageTempUrl, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        sut = nil
        contactGroupProviderMock = nil
        contactProviderMock = nil
        coreDataService = nil
        eventsServiceMock = nil
        humanCheckStatusProviderMock = nil
        userManagerMock = nil
        mockFetchLatestEventId = nil
        toolbarActionProviderMock = nil
        saveToolbarActionUseCaseMock = nil
        mockSenderImageStatusProvider = nil
        apiServiceMock = nil

        try FileManager.default.removeItem(at: imageTempUrl)
    }

    func testMessageItemOfIndexPath() {
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage
        createSut(labelID: Message.Location.inbox.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        sut.setupFetchController(nil)
        XCTAssertNotNil(sut.item(index:IndexPath(row: 0, section: 0)))
        XCTAssertNil(sut.item(index:IndexPath(row: 1, section: 0)))
        XCTAssertNil(sut.item(index:IndexPath(row: 0, section: 1)))
    }

    func testSelectByID() {
        XCTAssertTrue(sut.selectedIDs.isEmpty)
        sut.select(id: "1")
        XCTAssertTrue(sut.selectedIDs.contains("1"))
    }

    func testRemoveSelectByID() {
        sut.select(id: "1")
        sut.select(id: "2")
        XCTAssertTrue(sut.selectedIDs.contains("1"))
        XCTAssertTrue(sut.selectedIDs.contains("2"))
        XCTAssertEqual(sut.selectedIDs.count, 2)
        sut.removeSelected(id: "1")
        XCTAssertFalse(sut.selectedIDs.contains("1"))
        XCTAssertTrue(sut.selectedIDs.contains("2"))
        XCTAssertEqual(sut.selectedIDs.count, 1)
    }

    func testRemoveAllSelectID() {
        XCTAssertTrue(sut.selectedIDs.isEmpty)
        sut.select(id: "1")
        sut.select(id: "2")
        XCTAssertEqual(sut.selectedIDs.count, 2)
        sut.removeAllSelectedIDs()
        XCTAssertTrue(sut.selectedIDs.isEmpty)
    }

    func testSelectionContains() {
        XCTAssertTrue(sut.selectedIDs.isEmpty)
        sut.select(id: "1")
        XCTAssertTrue(sut.selectionContains(id: "1"))
        XCTAssertFalse(sut.selectionContains(id: "2"))
        XCTAssertFalse(sut.selectionContains(id: "3"))
    }

    func testLocalizedNavigationTitle() {
        createSut(labelID: Message.Location.inbox.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertEqual(sut.localizedNavigationTitle, Message.Location.inbox.localizedTitle)

        createSut(labelID: Message.Location.archive.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertEqual(sut.localizedNavigationTitle, Message.Location.archive.localizedTitle)

        createSut(labelID: "customID",
                  labelType: .folder,
                  isCustom: true,
                  labelName: "custom")
        XCTAssertEqual(sut.localizedNavigationTitle, "custom")

        createSut(labelID: "customID2",
                  labelType: .label,
                  isCustom: true,
                  labelName: "custom2")
        XCTAssertEqual(sut.localizedNavigationTitle, "custom2")

        createSut(labelID: "customID2",
                  labelType: .label,
                  isCustom: true,
                  labelName: nil)
        XCTAssertEqual(sut.localizedNavigationTitle, "")
    }

    func testGetCurrentViewMode() {
        XCTAssertEqual(sut.currentViewMode, conversationStateProviderMock.viewMode)
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        XCTAssertEqual(sut.currentViewMode, .conversation)
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage
        XCTAssertEqual(sut.currentViewMode, .singleMessage)
    }

    func testGetLocationViewMode_inDraftAndSent_getSingleMessageOnly() {
        createSut(labelID: Message.Location.draft.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage
        XCTAssertEqual(sut.locationViewMode, .singleMessage)
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        XCTAssertEqual(sut.locationViewMode, .singleMessage)

        createSut(labelID: Message.Location.sent.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage
        XCTAssertEqual(sut.locationViewMode, .singleMessage)
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        XCTAssertEqual(sut.locationViewMode, .singleMessage)
    }

    func testGetLocationViewMode_notInDraftOrSent_getViewModeFromConversationStateProvider() {
        createSut(labelID: Message.Location.inbox.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage
        XCTAssertEqual(sut.locationViewMode, .singleMessage)
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        XCTAssertEqual(sut.locationViewMode, .conversation)

        createSut(labelID: "custom",
                  labelType: .folder,
                  isCustom: true,
                  labelName: "1")
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage
        XCTAssertEqual(sut.locationViewMode, .singleMessage)
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        XCTAssertEqual(sut.locationViewMode, .conversation)

        createSut(labelID: "custom1",
                  labelType: .label,
                  isCustom: true,
                  labelName: "2")
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage
        XCTAssertEqual(sut.locationViewMode, .singleMessage)
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        XCTAssertEqual(sut.locationViewMode, .conversation)
    }

    func testGetIsRequiredHumanCheck() {
        humanCheckStatusProviderMock.isRequiredHumanCheck = false
        XCTAssertFalse(sut.isRequiredHumanCheck)

        humanCheckStatusProviderMock.isRequiredHumanCheck = true
        XCTAssertTrue(sut.isRequiredHumanCheck)
    }

    func testSetIsRequiredHumanCheck() {
        humanCheckStatusProviderMock.isRequiredHumanCheck = false
        sut.isRequiredHumanCheck = true
        XCTAssertTrue(humanCheckStatusProviderMock.isRequiredHumanCheck)

        sut.isRequiredHumanCheck = false
        XCTAssertFalse(humanCheckStatusProviderMock.isRequiredHumanCheck)
    }

    func testGetIsCurrentUserSelectedUnreadFilterInInbox() {
        userManagerMock.isUserSelectedUnreadFilterInInbox = false
        XCTAssertFalse(sut.isCurrentUserSelectedUnreadFilterInInbox)

        userManagerMock.isUserSelectedUnreadFilterInInbox = true
        XCTAssertTrue(sut.isCurrentUserSelectedUnreadFilterInInbox)
    }

    func testSetIsCurrentUserSelectedUnreadFilterInInbox() {
        sut.isCurrentUserSelectedUnreadFilterInInbox = false
        XCTAssertFalse(userManagerMock.isUserSelectedUnreadFilterInInbox)

        sut.isCurrentUserSelectedUnreadFilterInInbox = true
        XCTAssertTrue(userManagerMock.isUserSelectedUnreadFilterInInbox)
    }

    func testConvertSwipeActionTypeToMessageSwipeAction() {
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.none,
                                                                    isStarred: false,
                                                                    isUnread: false), .none)
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.trash,
                                                                    isStarred: false,
                                                                    isUnread: false), .trash)
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.spam,
                                                                    isStarred: false,
                                                                    isUnread: false), .spam)
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.starAndUnstar,
                                                                    isStarred: true,
                                                                    isUnread: false), .unstar)
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.starAndUnstar,
                                                                    isStarred: false,
                                                                    isUnread: false), .star)
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.archive,
                                                                    isStarred: false,
                                                                    isUnread: false), .archive)
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.readAndUnread,
                                                                    isStarred: false,
                                                                    isUnread: true), .read)
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.readAndUnread,
                                                                    isStarred: false,
                                                                    isUnread: false), .unread)
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.labelAs,
                                                                    isStarred: false,
                                                                    isUnread: false), .labelAs)
        XCTAssertEqual(sut
                        .convertSwipeActionTypeToMessageSwipeAction(.moveTo,
                                                                    isStarred: false,
                                                                    isUnread: false), .moveTo)
    }

    func testCalculateSpaceUsedPercentage() {
        XCTAssertEqual(sut.calculateSpaceUsedPercentage(usedSpace: 50, maxSpace: 100), 0.5, accuracy: 0.001)

        XCTAssertEqual(sut.calculateSpaceUsedPercentage(usedSpace: 33, maxSpace: 100), 0.33, accuracy: 0.001)
    }

    func testCalculateIsUsedSpaceExceedThreshold() {
        XCTAssertTrue(sut.calculateIsUsedSpaceExceedThreshold(usedPercentage: 0.6, threshold: 50))

        XCTAssertFalse(sut.calculateIsUsedSpaceExceedThreshold(usedPercentage: -0.6, threshold: 50))
    }

    func testCalculateFormattedMaxSpace() {
        XCTAssertEqual(sut.calculateFormattedMaxSpace(maxSpace: 500000), "488 KB")

        XCTAssertEqual(sut.calculateFormattedMaxSpace(maxSpace: -10), "-10 bytes")
    }

    func testCalculateSpaceMessage() {
        let msg = sut.calculateSpaceMessage(usedSpace: 600000,
                                            maxSpace: 500000,
                                            formattedMaxSpace: "488 KB",
                                            usedSpacePercentage: 1.2)
        XCTAssertEqual(msg, String(format: LocalString._space_all_used_warning, "488 KB"))

        let msg1 = sut.calculateSpaceMessage(usedSpace: 400000,
                                            maxSpace: 500000,
                                            formattedMaxSpace: "488 KB",
                                             usedSpacePercentage: 0.8)
        XCTAssertEqual(msg1,String(format: LocalString._space_partial_used_warning, 80, "488 KB"))
    }

    func testIsInDraftFolder() {
        createSut(labelID: Message.Location.draft.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertTrue(sut.isInDraftFolder)

        createSut(labelID: Message.Location.trash.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertFalse(sut.isInDraftFolder)
    }

    func testIsHavingUser() {
        createSut(labelID: Message.Location.draft.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil,
                  totalUserCount: 3)
        XCTAssertTrue(sut.isHavingUser)

        createSut(labelID: Message.Location.draft.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil,
                  totalUserCount: 0)
        XCTAssertFalse(sut.isHavingUser)
    }

    func testMessageLocation() {
        createSut(labelID: Message.Location.trash.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertEqual(sut.messageLocation, .trash)

        createSut(labelID: "labelID",
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertNil(sut.messageLocation)
    }

    func testIsTrashOrSpam() {
        createSut(labelID: Message.Location.trash.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertTrue(sut.isTrashOrSpam)

        createSut(labelID: Message.Location.spam.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertTrue(sut.isTrashOrSpam)

        createSut(labelID: Message.Location.inbox.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertFalse(sut.isTrashOrSpam)

        createSut(labelID: "1234",
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertFalse(sut.isTrashOrSpam)
    }

    func testGetActionSheetViewModel() {
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage
        createSut(labelID: Message.Location.inbox.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertEqual(sut.selectedIDs.count, 0)
        let model = sut.actionSheetViewModel
        XCTAssertEqual(model.title, .localizedStringWithFormat(LocalString._general_message, 0))

        conversationStateProviderMock.viewModeStub.fixture = .conversation
        createSut(labelID: Message.Location.inbox.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        sut.select(id: "id")
        XCTAssertEqual(sut.selectedIDs.count, 1)
        let model2 = sut.actionSheetViewModel
        XCTAssertEqual(model2.title, .localizedStringWithFormat(LocalString._general_conversation, 1))
    }

    func testGetEmptyFolderCheckMessage() {
        conversationStateProviderMock.viewModeStub.fixture = .singleMessage
        createSut(labelID: Message.Location.inbox.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertEqual(sut.getEmptyFolderCheckMessage(count: 1),
                       String(format: LocalString._clean_message_warning, 1))

        conversationStateProviderMock.viewModeStub.fixture = .conversation
        createSut(labelID: Message.Location.inbox.rawValue,
                  labelType: .folder,
                  isCustom: false,
                  labelName: nil)
        XCTAssertEqual(sut.getEmptyFolderCheckMessage(count: 10),
                       String(format: LocalString._clean_conversation_warning, 10))
    }

    func testGetGroupContacts() {
        let testData = ContactGroupVO(ID: "1", name: "name1")
        contactGroupProviderMock.getAllContactGroupVOsStub.bodyIs { _ in
            [testData]
        }
        createSut(labelID: "1", labelType: .folder, isCustom: false, labelName: nil)

        XCTAssertEqual(sut.contactGroups(), [testData])
    }

    func testGetCustomFolders() {
        let testData = Label(context: testContext)
        testData.labelID = "1"
        testData.name = "name1"
        labelProviderMock.getCustomFoldersStub.bodyIs { _ in
            [testData].map(LabelEntity.init(label:))
        }
        createSut(labelID: "1", labelType: .folder, isCustom: false, labelName: nil)

        XCTAssertEqual(sut.customFolders, [LabelEntity(label: testData)])
    }

    func testFetchContacts() {
        sut.fetchContacts()
        XCTAssertTrue(self.contactProviderMock.isFetchContactsCalled)
    }

    func testGetAllEmails() {
        let testData = Email(context: testContext)
        testData.emailID = "1"
        testData.email = "test@pm.me"
        contactProviderMock.allEmailsToReturn = [testData]
        createSut(labelID: "1", labelType: .folder, isCustom: false, labelName: nil)

        XCTAssertEqual(sut.allEmails, [testData])
    }

    func testTrashFromActionSheet_trashedSelectedConversations() {
        conversationStateProviderMock.viewModeStub.fixture = .conversation

        let conversationIDs = setupConversations(labelID: sut.labelID.rawValue, count: 3)
        sut.setupFetchController(nil)

        for id in conversationIDs {
            sut.select(id: id)
        }

        sut.handleActionSheetAction(.trash)

        XCTAssertTrue(self.conversationProviderMock.moveStub.wasCalledExactlyOnce)
        let argument = self.conversationProviderMock.moveStub.lastArguments!
        XCTAssertEqual(Set(argument.first.map(\.rawValue)), Set(conversationIDs))

        XCTAssertEqual(self.eventsServiceMock.callFetchEventsByLabelID.lastArguments?.value, self.sut.labelID)
        XCTAssertTrue(self.eventsServiceMock.callFetchEventsByLabelID.wasCalledExactlyOnce)
    }

    func testMarkConversationAsRead() {
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        createSut(labelID: "1245", labelType: .folder, isCustom: false, labelName: nil)

        let expectation1 = expectation(description: "Closure called")
        let ids = Set<String>(["1", "2"])
        sut.mark(IDs: ids, unread: false) {
            XCTAssertTrue(self.conversationProviderMock.markAsReadStub.wasCalledExactlyOnce)
            let argument = self.conversationProviderMock.markAsReadStub.lastArguments
            XCTAssertNotNil(argument)
            XCTAssertTrue(argument?.first.contains("1") ?? false)
            XCTAssertTrue(argument?.first.contains("2") ?? false)
            XCTAssertEqual(argument?.a2, "1245")

            XCTAssertEqual(self.eventsServiceMock.callFetchEventsByLabelID.lastArguments?.value, self.sut.labelID)
            XCTAssertTrue(self.eventsServiceMock.callFetchEventsByLabelID.wasCalledExactlyOnce)
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testMarkConversationAsUnread() {
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        createSut(labelID: "1245", labelType: .folder, isCustom: false, labelName: nil)

        let expectation1 = expectation(description: "Closure called")
        let ids = Set<String>(["1", "2"])
        sut.mark(IDs: ids, unread: true) {
            XCTAssertTrue(self.conversationProviderMock.markAsUnreadStub.wasCalledExactlyOnce)
            let argument = self.conversationProviderMock.markAsUnreadStub.lastArguments
            XCTAssertNotNil(argument)
            XCTAssertTrue(argument?.first.contains("1") ?? false)
            XCTAssertTrue(argument?.first.contains("2") ?? false)
            XCTAssertEqual(argument?.a2, "1245")

            XCTAssertEqual(self.eventsServiceMock.callFetchEventsByLabelID.lastArguments?.value, self.sut.labelID)
            XCTAssertTrue(self.eventsServiceMock.callFetchEventsByLabelID.wasCalledExactlyOnce)
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testLabelConversation_applyLabel() {
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        createSut(labelID: "1245", labelType: .folder, isCustom: false, labelName: nil)

        let expectation1 = expectation(description: "Closure called")
        let ids = Set<String>(["1", "2"])
        sut.label(IDs: ids, with: "labelID", apply: true) {
            XCTAssertTrue(self.conversationProviderMock.labelStub.wasCalledExactlyOnce)
            let argument = self.conversationProviderMock.labelStub.lastArguments
            XCTAssertNotNil(argument)
            XCTAssertTrue(argument?.first.contains("1") ?? false)
            XCTAssertTrue(argument?.first.contains("2") ?? false)
            XCTAssertEqual(argument?.a2, "labelID")
            XCTAssertFalse(argument?.a3 ?? true)

            XCTAssertEqual(self.eventsServiceMock.callFetchEventsByLabelID.lastArguments?.value, self.sut.labelID)
            XCTAssertTrue(self.eventsServiceMock.callFetchEventsByLabelID.wasCalledExactlyOnce)
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testLabelConversation_removeLabel() {
        conversationStateProviderMock.viewModeStub.fixture = .conversation
        createSut(labelID: "1245", labelType: .folder, isCustom: false, labelName: nil)

        let expectation1 = expectation(description: "Closure called")
        let ids = Set<String>(["1", "2"])
        sut.label(IDs: ids, with: "labelID", apply: false) {
            XCTAssertTrue(self.conversationProviderMock.unlabelStub.wasCalledExactlyOnce)
            let argument = self.conversationProviderMock.unlabelStub.lastArguments
            XCTAssertNotNil(argument)
            XCTAssertTrue(argument?.first.contains("1") ?? false)
            XCTAssertTrue(argument?.first.contains("2") ?? false)
            XCTAssertEqual(argument?.a2, "labelID")
            XCTAssertFalse(argument?.a3 ?? true)

            XCTAssertEqual(self.eventsServiceMock.callFetchEventsByLabelID.lastArguments?.value, self.sut.labelID)
            XCTAssertTrue(self.eventsServiceMock.callFetchEventsByLabelID.wasCalledExactlyOnce)
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testFetchConversationDetailIsCalled() {
        let expectation1 = expectation(description: "Closure called")

        sut.fetchConversationDetail(conversationID: "conversationID1") {
            XCTAssertTrue(self.conversationProviderMock.fetchConversationStub.wasCalledExactlyOnce)
            let argument = self.conversationProviderMock.fetchConversationStub.lastArguments
            XCTAssertNotNil(argument)
            XCTAssertEqual(argument?.first, "conversationID1")
            XCTAssertNil(argument?.a2)
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testDeleteConversationPermanently() throws {
        conversationStateProviderMock.viewModeStub.fixture = .conversation

        let conversationIDs = setupConversations(labelID: sut.labelID.rawValue, count: 3)
        sut.setupFetchController(nil)

        for id in conversationIDs {
            sut.select(id: id)
        }

        sut.deleteSelectedIDs()

        XCTAssertTrue(self.conversationProviderMock.deleteConversationsStub.wasCalledExactlyOnce)
        let argument = try XCTUnwrap(self.conversationProviderMock.deleteConversationsStub.lastArguments)
        XCTAssertEqual(Set(argument.first.map(\.rawValue)), Set(conversationIDs))
        XCTAssertEqual(argument.a2, self.sut.labelID)
    }

    func testHandleConversationMoveToAction() {
        let labelToMoveTo = MenuLabel(id: "0",
                                      name: "name",
                                      parentID: nil,
                                      path: "",
                                      textColor: "",
                                      iconColor: "",
                                      type: 0,
                                      order: 0,
                                      notify: false)
        // select the folder to move
        sut.updateSelectedMoveToDestination(menuLabel: labelToMoveTo, isOn: true)
        let conversationObject = Conversation(context: testContext)
        conversationObject.conversationID = "1"
        let expectation1 = expectation(description: "Closure called")
        let conversationToMove = ConversationEntity(conversationObject)

        sut.handleMoveToAction(conversations: [conversationToMove], isFromSwipeAction: false) {
            XCTAssertTrue(self.conversationProviderMock.moveStub.wasCalledExactlyOnce)
            do {
                let argument = try XCTUnwrap(self.conversationProviderMock.moveStub.lastArguments)
                XCTAssertTrue(argument.first.contains("1"))
                XCTAssertEqual(argument.a2, "")
                XCTAssertEqual(argument.a3, labelToMoveTo.location.labelID)
                XCTAssertFalse(argument.a4)

                XCTAssertEqual(self.eventsServiceMock.callFetchEventsByLabelID.lastArguments?.a1, self.sut.labelID)
                XCTAssertTrue(self.eventsServiceMock.callFetchEventsByLabelID.wasCalledExactlyOnce)
            } catch {
                XCTFail("Should not reach here")
            }
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertNil(self.sut.selectedMoveToFolder)
    }

    func testHandleConversationMoveToAction_withNoDestination() {
        let conversationObject = Conversation(context: testContext)
        conversationObject.conversationID = "1"
        let expectation1 = expectation(description: "Closure called")
        let conversationToMove = ConversationEntity(conversationObject)

        XCTAssertNil(self.sut.selectedMoveToFolder)
        sut.handleMoveToAction(conversations: [conversationToMove], isFromSwipeAction: false) {
            XCTAssertFalse(self.conversationProviderMock.moveStub.wasCalledExactlyOnce)
            XCTAssertFalse(self.eventsServiceMock.callFetchEventsByLabelID.wasCalledExactlyOnce)
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }

    func testHandleLabelAsActionForConversation_applyLabel_andApplyArchive() {
        let selectedLabel = MenuLabel(id: "label1",
                                      name: "label1",
                                      parentID: nil,
                                      path: "",
                                      textColor: "",
                                      iconColor: "",
                                      type: 0,
                                      order: 0,
                                      notify: false)
        let currentOption = [selectedLabel: PMActionSheetPlainItem.MarkType.none]
        let conversationObject = Conversation(context: testContext)
        conversationObject.conversationID = "1234"
        let label = LabelLocation(id: "label1", name: nil)
        // select label1
        sut.selectedLabelAsLabels.insert(label)
        let expectation1 = expectation(description: "Closure called")
        let conversationToAddLabel = ConversationEntity(conversationObject)

        sut.handleLabelAsAction(conversations: [conversationToAddLabel],
                                shouldArchive: true,
                                currentOptionsStatus: currentOption) {
            XCTAssertTrue(self.conversationProviderMock.labelStub.wasCalledExactlyOnce)
            XCTAssertTrue(self.conversationProviderMock.moveStub.wasCalledExactlyOnce)
            XCTAssertTrue(self.eventsServiceMock.callFetchEventsByLabelID.wasCalled)
            do {
                let argument = try XCTUnwrap(self.conversationProviderMock.labelStub.lastArguments)
                XCTAssertTrue(argument.first.contains(conversationToAddLabel.conversationID))
                XCTAssertEqual(argument.a2, label.labelID)
                XCTAssertFalse(argument.a3)

                // Check is move function called
                let argument2 = try XCTUnwrap(self.conversationProviderMock.moveStub.lastArguments)
                XCTAssertTrue(argument2.first.contains(conversationToAddLabel.conversationID))
                XCTAssertEqual(argument2.a2, "")
                XCTAssertEqual(argument2.a3, Message.Location.archive.labelID)
                XCTAssertFalse(argument2.a4)

                // Check event api is called
                let argument3 = try XCTUnwrap(self.eventsServiceMock.callFetchEventsByLabelID.lastArguments)
                XCTAssertEqual(argument3.a1, self.sut.labelId)
            } catch {
                XCTFail("Should not reach here")
            }
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertTrue(sut.selectedLabelAsLabels.isEmpty)
    }

    func testHandleLabelAsActionForConversation_removeLabel_withoutApplyArchive() {
        let selectedLabel = MenuLabel(id: "label1",
                                      name: "label1",
                                      parentID: nil,
                                      path: "",
                                      textColor: "",
                                      iconColor: "",
                                      type: 0,
                                      order: 0,
                                      notify: false)
        let currentOption = [selectedLabel: PMActionSheetPlainItem.MarkType.none]
        let label = LabelLocation(id: "label1", name: nil)

        let conversationObject = Conversation(context: testContext)
        conversationObject.conversationID = "1234"
        // Add label to be removed
        conversationObject.applyLabelChanges(labelID: label.labelID.rawValue, apply: true)

        let expectation1 = expectation(description: "Closure called")
        let conversationToRemoveLabel = ConversationEntity(conversationObject)

        sut.handleLabelAsAction(conversations: [conversationToRemoveLabel],
                                shouldArchive: false,
                                currentOptionsStatus: currentOption) {
            XCTAssertTrue(self.conversationProviderMock.unlabelStub.wasCalledExactlyOnce)
            XCTAssertFalse(self.conversationProviderMock.moveStub.wasCalledExactlyOnce)
            XCTAssertTrue(self.eventsServiceMock.callFetchEventsByLabelID.wasCalled)
            do {
                let argument = try XCTUnwrap(self.conversationProviderMock.unlabelStub.lastArguments)
                XCTAssertTrue(argument.first.contains(conversationToRemoveLabel.conversationID))
                XCTAssertEqual(argument.a2, label.labelID)
                XCTAssertFalse(argument.a3)

                // Check event api is called
                let argument2 = try XCTUnwrap(self.eventsServiceMock.callFetchEventsByLabelID.lastArguments)
                XCTAssertEqual(argument2.a1, self.sut.labelId)
            } catch {
                XCTFail("Should not reach here")
            }
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
        XCTAssertTrue(sut.selectedLabelAsLabels.isEmpty)
    }

    func testGetActionBarActions_inInbox() {
        createSut(labelID: Message.Location.inbox.rawValue, labelType: .folder, isCustom: false, labelName: nil)
        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .trash, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_inStar() {
        createSut(labelID: Message.Location.starred.rawValue, labelType: .folder, isCustom: false, labelName: nil)
        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .trash, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_inArchive() {
        createSut(labelID: Message.Location.archive.rawValue, labelType: .folder, isCustom: false, labelName: nil)
        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .trash, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_inAllMail() {
        createSut(labelID: Message.Location.allmail.rawValue, labelType: .folder, isCustom: false, labelName: nil)
        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .trash, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_inAllSent() {
        createSut(labelID: Message.Location.sent.rawValue, labelType: .folder, isCustom: false, labelName: nil)
        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .trash, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_inDraft() {
        createSut(labelID: Message.Location.draft.rawValue, labelType: .folder, isCustom: false, labelName: nil)
        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .trash, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_inTrash() {
        createSut(labelID: Message.Location.trash.rawValue, labelType: .folder, isCustom: false, labelName: nil)
        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .delete, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_inSpam() {
        createSut(labelID: Message.Location.spam.rawValue, labelType: .folder, isCustom: false, labelName: nil)
        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .delete, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_inCustomFolder() {
        createSut(labelID: "qweqwe", labelType: .folder, isCustom: false, labelName: nil)

        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .trash, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_inCustomLabel() {
        createSut(labelID: "qweqwe", labelType: .label, isCustom: false, labelName: nil)

        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .trash, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_withNonExistLabel() {
        createSut(labelID: "qweasd", labelType: .folder, isCustom: false, labelName: nil)
        let result = sut.toolbarActionTypes()
        XCTAssertEqual(result, [.markRead, .trash, .moveTo, .labelAs, .more])
    }

    func testGetActionBarActions_withCustomToolbarActions() {
        createSut(labelID: "qweasd", labelType: .folder, isCustom: false, labelName: nil)
        toolbarActionProviderMock.listViewToolbarActions = [.star, .saveAsPDF]

        let result = sut.toolbarActionTypes()

        XCTAssertEqual(result, [.star, .saveAsPDF, .more])
    }

    func testGetOnboardingDestination() {
        // Fresh install
        self.welcomeCarrouselCache.lastTourVersion = nil
        var destination = self.sut.getOnboardingDestination()
        XCTAssertEqual(destination, .onboardingForNew)

        // The last tour version is the same as defined TOUR_VERSION
        // Shouldn't show welcome carrousel
        self.welcomeCarrouselCache.lastTourVersion = Constants.App.TourVersion
        destination = self.sut.getOnboardingDestination()
        XCTAssertNil(destination)

        // Update the app
        self.welcomeCarrouselCache.lastTourVersion = 1
        destination = self.sut.getOnboardingDestination()
        XCTAssertEqual(destination, .onboardingForUpdate)
    }

    func testSendsHapticFeedbackOnceWhenSwipeActionIsActivatedAndOnceItIsDeactivated() {
        var signalsSent = 0

        sut.sendHapticFeedback = {
            signalsSent += 1
        }

        for _ in (1...3) {
            sut.swipyCellDidSwipe(triggerActivated: false)
        }

        for _ in (1...3) {
            sut.swipyCellDidSwipe(triggerActivated: true)
        }

        XCTAssert(signalsSent == 1)

        for _ in (1...3) {
            sut.swipyCellDidSwipe(triggerActivated: true)
        }

        for _ in (1...3) {
            sut.swipyCellDidSwipe(triggerActivated: false)
        }

        XCTAssert(signalsSent == 2)
    }

    func testUpdateToolbarActions_updateActionWithoutMoreAction() {
        saveToolbarActionUseCaseMock.callExecute.bodyIs { _, _, completion  in
            completion(.success(Void()))
        }
        let e = expectation(description: "Closure is called")
        sut.updateToolbarActions(actions: [.unstar, .markRead]) { _ in
            e.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(saveToolbarActionUseCaseMock.callExecute.wasCalledExactlyOnce)
        XCTAssertEqual(saveToolbarActionUseCaseMock.callExecute.lastArguments?.first.preference.listViewActions, [.unstar, .markRead])
    }

    func testUpdateToolbarActions_updateActionWithMoreAction() {
        saveToolbarActionUseCaseMock.callExecute.bodyIs { _, _, completion  in
            completion(.success(Void()))
        }
        let e = expectation(description: "Closure is called")
        sut.updateToolbarActions(actions: [.unstar, .markRead, .more]) { _ in
            e.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(saveToolbarActionUseCaseMock.callExecute.wasCalledExactlyOnce)
        XCTAssertEqual(saveToolbarActionUseCaseMock.callExecute.lastArguments?.first.preference.listViewActions, [.unstar, .markRead])

        let e1 = expectation(description: "Closure is called")
        sut.updateToolbarActions(actions: [.more, .unstar, .markRead]) { _ in
            e1.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(saveToolbarActionUseCaseMock.callExecute.wasCalled)
        XCTAssertEqual(saveToolbarActionUseCaseMock.callExecute.lastArguments?.first.preference.listViewActions, [.unstar, .markRead])
    }

    func testSwipeGesturesIgnoreSelection() throws {
        let selectedConversationIDs = ["foo", "bar"]

        for conversationID in selectedConversationIDs {
            sut.select(id: conversationID)
        }

        sut.handleSwipeAction(.trash, on: .conversation(.make(conversationID: ConversationID("xyz"))))

        XCTAssertEqual(conversationProviderMock.moveStub.callCounter, 1)
        let lastMoveArguments = try XCTUnwrap(conversationProviderMock.moveStub.lastArguments)
        XCTAssertEqual(lastMoveArguments.a1, ["xyz"])
        XCTAssertEqual(lastMoveArguments.a3, Message.Location.trash.labelID)

    }

    func testFetchSenderImageIfNeeded_featureFlagIsOff_getNil() {
        userManagerMock.mailSettings = .init(hideSenderImages: false)
        mockSenderImageStatusProvider.isSenderImageEnabledStub.bodyIs { _, _ in
            return false
        }
        let e = expectation(description: "Closure is called")

        sut.fetchSenderImageIfNeeded(item: .message(MessageEntity.make()),
                                     isDarkMode: Bool.random(),
                                     scale: 1.0) { result in
            XCTAssertNil(result)
            e.fulfill()
        }

        waitForExpectations(timeout: 1)

        XCTAssertTrue(apiServiceMock.requestJSONStub.wasNotCalled)
    }

    func testFetchSenderImageIfNeeded_hideSenderImageInMailSettingTrue_getNil() {
        userManagerMock.mailSettings = .init(hideSenderImages: true)
        mockSenderImageStatusProvider.isSenderImageEnabledStub.bodyIs { _, _ in
            return true
        }
        let e = expectation(description: "Closure is called")

        sut.fetchSenderImageIfNeeded(item: .message(MessageEntity.make()),
                                     isDarkMode: Bool.random(),
                                     scale: 1.0) { result in
            XCTAssertNil(result)
            e.fulfill()
        }

        waitForExpectations(timeout: 1)

        XCTAssertTrue(apiServiceMock.requestJSONStub.wasNotCalled)
    }

    func testFetchSenderImageIfNeeded_msgHasNoSenderThatIsEligible_getNil() {
        userManagerMock.mailSettings = .init(hideSenderImages: false)
        mockSenderImageStatusProvider.isSenderImageEnabledStub.bodyIs { _, _ in
            return true
        }
        let e = expectation(description: "Closure is called")
        let e2 = expectation(description: "Closure is called")

        sut.fetchSenderImageIfNeeded(item: .message(MessageEntity.make()),
                                     isDarkMode: Bool.random(),
                                     scale: 1.0) { result in
            XCTAssertNil(result)
            e.fulfill()
        }

        sut.fetchSenderImageIfNeeded(item: .conversation(ConversationEntity.make()),
                                     isDarkMode: Bool.random(),
                                     scale: 1.0) { result in
            XCTAssertNil(result)
            e2.fulfill()
        }

        waitForExpectations(timeout: 1)

        XCTAssertTrue(apiServiceMock.requestJSONStub.wasNotCalled)
    }

    func testFetchSenderImageIfNeeded_msgHasEligibleSender_getImageData() {
        userManagerMock.mailSettings = .init(hideSenderImages: false)
        mockSenderImageStatusProvider.isSenderImageEnabledStub.bodyIs { _, _ in
            return true
        }
        let e = expectation(description: "Closure is called")
        let msg = MessageEntity.createSenderImageEligibleMessage()
        let imageData = UIImage(named: "mail_attachment_audio")?.pngData()
        apiServiceMock.downloadStub.bodyIs { _, _, fileUrl, _, _, _, _, _, _, completion in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                try? imageData?.write(to: fileUrl)
                let response = HTTPURLResponse(statusCode: 200)
                completion(response, nil, nil)
            }
        }

        sut.fetchSenderImageIfNeeded(item: .message(msg),
                                     isDarkMode: Bool.random(),
                                     scale: 1.0) { result in
            XCTAssertNotNil(result)
            e.fulfill()
        }

        waitForExpectations(timeout: 1)

        XCTAssertTrue(apiServiceMock.downloadStub.wasCalledExactlyOnce)
    }

    func testFetchMessageDetail_forDraft_ignoreDownloadedIsTrue() throws {
        let fakeMsg = MessageEntity.make(
            labels: [LabelEntity.make(labelID: Message.Location.draft.labelID)]
        )
        let e = expectation(description: "Closure is called")
        mockFetchMessageDetail.result = .success(fakeMsg)

        sut.fetchMessageDetail(
            message: fakeMsg) { _ in
                e.fulfill()
            }

        waitForExpectations(timeout: 1)

        let params = try XCTUnwrap(mockFetchMessageDetail.params)
        XCTAssertTrue(params.ignoreDownloaded)
    }

    func testFetchMessageDetail_msgIsNotDraft_ignoreDownloadedIsFalse() throws {
        let fakeMsg = MessageEntity.make(
            labels: [LabelEntity.make(labelID: Message.Location.inbox.labelID)]
        )
        let e = expectation(description: "Closure is called")
        mockFetchMessageDetail.result = .success(fakeMsg)

        sut.fetchMessageDetail(
            message: fakeMsg) { _ in
                e.fulfill()
            }

        waitForExpectations(timeout: 1)

        let params = try XCTUnwrap(mockFetchMessageDetail.params)
        XCTAssertFalse(params.ignoreDownloaded)
    }
}

extension MailboxViewModelTests {
    func loadTestMessage() throws {
        let parsedObject = testMessageMetaData.parseObjectAny()!
        let testMessage = try GRTJSONSerialization
            .object(withEntityName: "Message",
                    fromJSONDictionary: parsedObject,
                    in: testContext) as? Message
        testMessage?.userID = "1"
        testMessage?.messageStatus = 1
        try testContext.save()
    }

    func createSut(labelID: String,
                   labelType: PMLabelType,
                   isCustom: Bool,
                   labelName: String?,
                   totalUserCount: Int = 1) {
        let fetchMessage = MockFetchMessages()
        let updateMailbox = UpdateMailbox(dependencies: .init(
            eventService: eventsServiceMock,
            messageDataService: userManagerMock.messageService,
            conversationProvider: conversationProviderMock,
            purgeOldMessages: MockPurgeOldMessages(),
            fetchMessageWithReset: MockFetchMessagesWithReset(),
            fetchMessage: fetchMessage,
            fetchLatestEventID: mockFetchLatestEventId
        ), parameters: .init(labelID: LabelID(labelID)))
        self.mockFetchMessageDetail = MockFetchMessageDetail(stubbedResult: .failure(NSError.badResponse()))

        let dependencies = MailboxViewModel.Dependencies(
            fetchMessages: MockFetchMessages(),
            updateMailbox: updateMailbox,
            fetchMessageDetail: mockFetchMessageDetail,
            fetchSenderImage: FetchSenderImage(
                dependencies: .init(
                    senderImageService: .init(
                        dependencies: .init(
                            apiService: userManagerMock.apiService,
                            internetStatusProvider: MockInternetConnectionStatusProviderProtocol()
                        )
                    ),
                    senderImageStatusProvider: mockSenderImageStatusProvider,
                    mailSettings: userManagerMock.mailSettings
                )
            )
        )
        let label = LabelInfo(name: labelName ?? "")
        sut = MailboxViewModel(labelID: LabelID(labelID),
                               label: isCustom ? label : nil,
                               labelType: labelType,
                               userManager: userManagerMock,
                               pushService: MockPushNotificationService(),
                               coreDataContextProvider: coreDataService,
                               lastUpdatedStore: MockLastUpdatedStore(),
                               humanCheckStatusProvider: humanCheckStatusProviderMock,
                               conversationStateProvider: conversationStateProviderMock,
                               contactGroupProvider: contactGroupProviderMock,
                               labelProvider: labelProviderMock,
                               contactProvider: contactProviderMock,
                               conversationProvider: conversationProviderMock,
                               eventsService: eventsServiceMock,
                               dependencies: dependencies,
                               welcomeCarrouselCache: welcomeCarrouselCache,
                               toolbarActionProvider: toolbarActionProviderMock,
                               saveToolbarActionUseCase: saveToolbarActionUseCaseMock,
                               senderImageService: .init(dependencies: .init(apiService: userManagerMock.apiService, internetStatusProvider: MockInternetConnectionStatusProviderProtocol())),
                               totalUserCountClosure: {
            return totalUserCount
        })
    }

    func setupConversations(labelID: String, count: Int) -> [String] {
        return (0..<count).map { unreadState in
            let conversation = Conversation(context: testContext)
            conversation.conversationID = UUID().uuidString

            let contextLabel = ContextLabel(context: testContext)
            contextLabel.labelID = labelID
            contextLabel.conversation = conversation
            contextLabel.userID = "1"

            return conversation.conversationID
        }
    }
}
