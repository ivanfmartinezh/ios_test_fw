//
//  ContactDetailViewController.swift
//  Proton Mail
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
import PromiseKit
import ProtonCore_Foundations
import ProtonCore_PaymentsUI
import ProtonCore_UIFoundations
import UIKit

final class ContactDetailViewController: UIViewController, ComposeSaveHintProtocol, AccessibleView, LifetimeTrackable {
    class var lifetimeConfiguration: LifetimeConfiguration {
        .init(maxCount: 1)
    }

    private let viewModel: ContactDetailsViewModel
    private var paymentsUI: PaymentsUI?

    fileprivate let kContactDetailsHeaderView: String = "ContactSectionHeadView"
    fileprivate let kContactDetailsHeaderID: String = "contact_section_head_view"
    fileprivate let kContactDetailsDisplayCell: String = "contacts_details_display_cell"
    fileprivate let kContactDetailsUpgradeCell: String = "contacts_details_upgrade_cell"
    fileprivate let kContactsDetailsShareCell: String = "contacts_details_share_cell"
    fileprivate let kContactsDetailsWarningCell: String = "contacts_details_warning_cell"
    fileprivate let kContactsDetailsEmailCell: String = "contacts_details_display_email_cell"

    @IBOutlet private var tableView: UITableView!

    // header view
    @IBOutlet private var headerContainerView: UIView!
    @IBOutlet private var profilePictureImageView: UIImageView!
    @IBOutlet private var shortNameLabel: UILabel!
    @IBOutlet private var fullNameLabel: UILabel!
    @IBOutlet private var shareContactImageView: UIImageView!
    @IBOutlet private var callContactImageView: UIImageView!
    @IBOutlet private var emailContactImageView: UIImageView!
    @IBOutlet private var emailContactLabel: UILabel!
    @IBOutlet private var shareContactLabel: UILabel!
    @IBOutlet private var callContactLabel: UILabel!
    @IBOutlet private var callContactButton: UIButton!
    @IBOutlet private var sendToPrimaryEmailButton: UIButton!
    private var doneItem: UIBarButtonItem?
    private var loaded = false

    init(viewModel: ContactDetailsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: "ContactDetailViewController", bundle: nil)
        self.viewModel.reloadView = { [weak self] in
            self?.configHeader()
            self?.tableView.reloadData()
        }
        trackLifetime()
    }

    required init?(coder: NSCoder) {
        fatalError("You should not instantiate this view controller by invoking init(coder:).")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ColorProvider.BackgroundNorm

        doneItem = UIBarButtonItem(title: LocalString._general_edit_action,
                                   style: UIBarButtonItem.Style.plain,
                                   target: self, action: #selector(didTapEditButton(sender:)))
        var attributes = FontManager.DefaultStrong
        attributes[.foregroundColor] = ColorProvider.InteractionNorm as UIColor
        doneItem?.setTitleTextAttributes(attributes, for: .normal)
        navigationItem.rightBarButtonItem = doneItem
        configHeaderStyle()
        configureStyle()
        configureTableView()

        viewModel.getDetails {
            self.configHeaderDefault()
            MBProgressHUD.showAdded(to: self.view, animated: true)
        }.done { _ in
            self.configHeader()
            self.tableView.reloadData()
            self.loaded = true
        }.catch { error in
            error.alert(at: self.view)
        }.finally {
            MBProgressHUD.hide(for: self.view, animated: true)
        }

        let nib = UINib(nibName: kContactDetailsHeaderView, bundle: nil)
        tableView.register(nib, forHeaderFooterViewReuseIdentifier: kContactDetailsHeaderID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60.0
        tableView.noSeparatorsBelowFooter()
        tableView.backgroundColor = ColorProvider.BackgroundNorm

        navigationItem.largeTitleDisplayMode = .never
        generateAccessibilityIdentifiers()
        navigationItem.assignNavItemIndentifiers()
    }

    private func configureTableView() {
        tableView.register(UINib(nibName: "ContactDetailsUpgradeCell", bundle: nil), forCellReuseIdentifier: kContactDetailsUpgradeCell)
        tableView.register(UINib(nibName: "ContactEditAddCell", bundle: nil), forCellReuseIdentifier: kContactsDetailsShareCell)
        tableView.register(UINib(nibName: "ContactsDetailsWarningCell", bundle: nil), forCellReuseIdentifier: kContactsDetailsWarningCell)
        tableView.register(UINib(nibName: "ContactDetailDisplayEmailCell", bundle: nil), forCellReuseIdentifier: kContactsDetailsEmailCell)
        tableView.register(UINib(nibName: "ContactDetailsDisplayCell", bundle: nil), forCellReuseIdentifier: kContactDetailsDisplayCell)
    }

    private func configureStyle() {
        headerContainerView.backgroundColor = ColorProvider.BackgroundNorm
    }

    /// config header style only need once
    private func configHeaderStyle() {
        // setup profile image
        profilePictureImageView.layer.cornerRadius = profilePictureImageView.frame.size.width / 2
        profilePictureImageView.layer.masksToBounds = true

        // setup short label
        shortNameLabel.layer.cornerRadius = shortNameLabel.frame.size.width / 2
        shortNameLabel.textAlignment = .center
        shortNameLabel.textColor = ContactGroupEditViewCellColor.deselected.text
        shortNameLabel.backgroundColor = UIColor.lightGray

        // email contact
        emailContactLabel.text = LocalString._contacts_email_contact_title
        emailContactImageView.image = IconProvider.envelope
        emailContactImageView.setupImage(scale: 0.5,
                                         tintColor: UIColor.white,
                                         backgroundColor: ColorProvider.BrandNorm)
        sendToPrimaryEmailButton.isUserInteractionEnabled = false
        emailContactImageView.backgroundColor = UIColor.lightGray
        // call contact
        callContactLabel.text = LocalString._contacts_call_contact_title
        callContactImageView.image = IconProvider.phone
        callContactImageView.setupImage(scale: 0.5,
                                        tintColor: UIColor.white,
                                        backgroundColor: ColorProvider.BrandNorm)
        callContactButton.isUserInteractionEnabled = false
        callContactImageView.backgroundColor = UIColor.lightGray

        // share contact
        shareContactLabel.text = LocalString._contacts_share_contact_action
        shareContactImageView.image = IconProvider.arrowUpFromSquare
        shareContactImageView.setupImage(scale: 0.5,
                                         tintColor: UIColor.white,
                                         backgroundColor: ColorProvider.BrandNorm)
        shareContactImageView.isUserInteractionEnabled = false
        shareContactImageView.backgroundColor = UIColor.lightGray
    }

    /// config header default when loading details
    private func configHeaderDefault() {
        shortNameLabel.isHidden = false
        profilePictureImageView.isHidden = true

        let name = viewModel.getProfile().newDisplayName
        shortNameLabel.text = name.initials()

        let attributes = FontManager
            .Headline
            .alignment(.center)
            .addTruncatingTail()
        fullNameLabel.attributedText = name.apply(style: attributes)
    }

    /// config header after got contact details
    private func configHeader() {
        // shortname / image
        if let profilePicture = viewModel.getProfilePicture() {
            // show profile picture
            shortNameLabel.isHidden = true
            profilePictureImageView.isHidden = false
            profilePictureImageView.image = profilePicture
        } else {
            shortNameLabel.isHidden = false
            profilePictureImageView.isHidden = true

            // show short name
            let name = viewModel.getProfile().newDisplayName
            shortNameLabel.text = name.initials()
        }

        // full name
        let attributes = FontManager
            .Headline
            .alignment(.center)
            .addTruncatingTail()
        fullNameLabel.attributedText = viewModel.getProfile().newDisplayName.apply(style: attributes)

        // email contact
        if viewModel.getEmails().count == 0 {
            // no email in contact, disable sending button
            sendToPrimaryEmailButton.isUserInteractionEnabled = false
            emailContactImageView.backgroundColor = UIColor.lightGray // TODO: fix gray
        } else {
            sendToPrimaryEmailButton.isUserInteractionEnabled = true
            emailContactImageView.backgroundColor = ColorProvider.BrandNorm
        }

        // call contact
        if viewModel.getPhones().count == 0 {
            // no tel in contact, disable
            callContactButton.isUserInteractionEnabled = false
            callContactImageView.backgroundColor = UIColor.lightGray // TODO: fix gray
        } else {
            callContactButton.isUserInteractionEnabled = true
            callContactImageView.backgroundColor = ColorProvider.BrandNorm
        }
        shareContactImageView.backgroundColor = ColorProvider.BrandNorm
    }

    private func systemPhoneCall(phone: ContactEditPhone) {
        var allowedCharactersSet = NSCharacterSet.decimalDigits
        allowedCharactersSet.insert("+")
        allowedCharactersSet.insert(",")
        allowedCharactersSet.insert("*")
        allowedCharactersSet.insert("#")
        let formatedNumber = phone.newPhone.components(separatedBy: allowedCharactersSet.inverted).joined(separator: "")
        let phoneUrl = "tel://\(formatedNumber)"
        if let phoneCallURL = URL(string: phoneUrl) {
            let application = UIApplication.shared
            if application.canOpenURL(phoneCallURL) {
                if #available(iOS 10.0, *) {
                    application.open(phoneCallURL, options: [:], completionHandler: nil)
                } else {
                    application.openURL(phoneCallURL)
                }
            }
        }
    }

    @IBAction func didTapSendToPrimaryEmailButton(_ sender: UIButton) {
        guard !viewModel.user.isStorageExceeded else {
            LocalString._storage_exceeded.alertToastBottom()
            return
        }
        let emails = viewModel.getEmails()
        let email = emails[0]
        let contact = viewModel.contact
        let contactVO = ContactVO(name: contact.name,
                                  email: email.newEmail,
                                  isProtonMailContact: false)
        presentComposer(contact: contactVO)
    }

    @IBAction func didTapCallContactButton(_ sender: UIButton) {
        if let phone = viewModel.getPhones().first {
            systemPhoneCall(phone: phone)
        }
    }

    @IBAction func didTapShareContact(_ sender: UIButton) {
        shareVcard(sender)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if loaded, viewModel.rebuild() {
            configHeader()
            tableView.reloadData()
        }
        self.viewModel.user.undoActionManager.register(handler: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.zeroMargin()
        var insets = tableView.contentInset
        insets.bottom = 100
        tableView.contentInset = insets
    }

    private func presentComposer(contact: ContactVO) {
        let user = self.viewModel.user
        let composer = ComposerViewFactory.makeComposer(
            msg: nil,
            action: .newDraft,
            user: user,
            contextProvider: viewModel.coreDataService,
            isEditingScheduleMsg: false,
            userIntroductionProgressProvider: userCachedStatus,
            scheduleSendEnableStatusProvider: userCachedStatus,
            internetStatusProvider: sharedServices.get(by: InternetConnectionStatusProvider.self),
            toContact: contact
        )
        guard let nav = navigationController else {
            return
        }
        nav.present(composer, animated: true)
    }

    @objc func didTapEditButton(sender: UIBarButtonItem) {
        let viewModel = ContactEditViewModelImpl(contactEntity: viewModel.getContact(),
                                                 user: viewModel.user,
                                                 coreDataService: sharedServices.get(by: CoreDataService.self))
        let newView = ContactEditViewController(viewModel: viewModel)
        newView.delegate = self
        let nav = UINavigationController(rootViewController: newView)
        present(nav, animated: true, completion: nil)
    }
}

extension ContactDetailViewController: ContactEditViewControllerDelegate {
    func deleted() {
        navigationController?.popViewController(animated: true)
    }

    func updated() {
        // nono full screen persent vc in ios 13. viewWillAppear will not be called. hack here
        if #available(iOS 13.0, *) {
            self.viewModel.rebuild()
        }
        configHeader()
        tableView.reloadData()
    }
}

extension ContactDetailViewController: ContactUpgradeCellDelegate {
    func upgrade() {
        presentPlanUpgrade()
    }

    private func presentPlanUpgrade() {
        self.paymentsUI = PaymentsUI(payments: self.viewModel.user.payments, clientApp: .mail, shownPlanNames: Constants.shownPlanNames)
        self.paymentsUI?.showUpgradePlan(presentationType: .modal,
                                         backendFetch: true,
                                         completionHandler: { _ in })
    }
}

// MARK: - UITableViewDataSource

extension ContactDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.sections().count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let s = viewModel.sections()[section]
        switch s {
        case .type2_warning:
            return viewModel.statusType2() ? 0 : 1
        case .type3_warning:
            if !viewModel.type3Error() {
                return viewModel.statusType3() ? 0 : 1
            }
            return 0
        case .type3_error:
            return viewModel.type3Error() ? 1 : 0
        case .debuginfo:
            return viewModel.debugging() ? 1 : 0
        case .emails:
            return viewModel.getEmails().count
        case .cellphone:
            return viewModel.getPhones().count
        case .home_address:
            return viewModel.getAddresses().count
        case .information:
            return viewModel.getInformations().count
        case .custom_field:
            return viewModel.getFields().count
        case .notes:
            return viewModel.getNotes().count
        case .url:
            return viewModel.getUrls().count
        case .display_name, .upgrade, .share:
            return 1
        case .email_header, .encrypted_header, .delete:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let cell = tableView.dequeueReusableHeaderFooterView(withIdentifier: kContactDetailsHeaderID) as? ContactSectionHeadView
        let s = viewModel.sections()[section]
        switch s {
        case .email_header:
            let signed = viewModel.statusType2()
            cell?.configHeader(title: LocalString._contacts_email_addresses_title, signed: signed)
        case .encrypted_header:
            let signed = viewModel.statusType3()
            cell?.configHeader(title: LocalString._contacts_encrypted_contact_details_title, signed: signed)
        default:
            cell?.configHeader(title: "", signed: false)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let s = viewModel.sections()[section]
        switch s {
        case .email_header, .share:
            return 38.0
        case .encrypted_header:
            if viewModel.hasEncryptedContacts() {
                return 38.0
            } else {
                return 0
            }
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = indexPath.section
        let row = indexPath.row
        let s = viewModel.sections()[section]

        if s == .upgrade {
            let cell = tableView.dequeueReusableCell(withIdentifier: kContactDetailsUpgradeCell, for: indexPath) as! ContactDetailsUpgradeCell
            cell.configCell(delegate: self)
            cell.selectionStyle = .none
            return cell
        } else if s == .share {
            let cell = tableView.dequeueReusableCell(withIdentifier: kContactsDetailsShareCell, for: indexPath) as! ContactEditAddCell
            cell.configCell(value: LocalString._contacts_share_contact_action)
            cell.selectionStyle = .default
            return cell
        }

        if s == .type2_warning {
            let cell = tableView.dequeueReusableCell(withIdentifier: kContactsDetailsWarningCell, for: indexPath) as! ContactsDetailsWarningCell
            cell.configCell(warning: .signatureWarning)
            cell.selectionStyle = .none
            return cell
        } else if s == .type3_error {
            let cell = tableView.dequeueReusableCell(withIdentifier: kContactsDetailsWarningCell, for: indexPath) as! ContactsDetailsWarningCell
            cell.configCell(warning: .decryptionError)
            cell.selectionStyle = .none
            return cell
        } else if s == .type3_warning {
            let cell = tableView.dequeueReusableCell(withIdentifier: kContactsDetailsWarningCell, for: indexPath) as! ContactsDetailsWarningCell
            cell.configCell(warning: .signatureWarning)
            cell.selectionStyle = .none
            return cell
        } else if s == .debuginfo {
            let cell = tableView.dequeueReusableCell(withIdentifier: kContactsDetailsWarningCell, for: indexPath) as! ContactsDetailsWarningCell
            cell.configCell(forlog: "")
            cell.selectionStyle = .none
            return cell
        } else if s == .emails {
            let cell = tableView.dequeueReusableCell(withIdentifier: kContactsDetailsEmailCell, for: indexPath) as! ContactDetailDisplayEmailCell

            let emails = viewModel.getEmails()
            let email = emails[row]
            let colors = emails[row].getCurrentlySelectedContactGroupColors()
            cell.configCell(title: email.newType.title, value: email.newEmail, contactGroupColors: colors)
            cell.selectionStyle = .default
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: kContactDetailsDisplayCell, for: indexPath) as! ContactDetailsDisplayCell
        cell.selectionStyle = .none
        switch s {
        case .cellphone:
            let cells = viewModel.getPhones()
            let tel = cells[row]
            cell.configCell(title: tel.newType.title, value: tel.newPhone)
            cell.selectionStyle = .default
        case .home_address:
            let addrs = viewModel.getAddresses()
            let addr = addrs[row]
            cell.configCell(title: addr.newType.title, value: addr.fullAddress())
            cell.selectionStyle = .default
        case .information:
            let infos = viewModel.getInformations()
            let info = infos[row]
            cell.configCell(title: info.infoType.title, value: info.newValue)
            cell.selectionStyle = .default
        case .custom_field:
            let fields = viewModel.getFields()
            let field = fields[row]
            cell.configCell(title: field.newType.title, value: field.newField)
            cell.selectionStyle = .default
        case .notes:
            let notes = viewModel.getNotes()
            let note = notes[row]
            cell.configCell(title: LocalString._contacts_info_notes, value: note.newNote)
            cell.value.numberOfLines = 0
            cell.selectionStyle = .default
        case .url:
            let urls = viewModel.getUrls()
            let url = urls[row]
            cell.configCell(title: url.newType.title, value: url.newUrl)
            cell.selectionStyle = .default

        case .email_header, .encrypted_header, .delete, .upgrade, .share,
             .type2_warning, .type3_error, .type3_warning, .debuginfo, .emails, .display_name:
            break
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ContactDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.copy(_:)) {
            return true
        }
        return false
    }

    func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action == #selector(UIResponderStandardEditActions.copy(_:)) {
            var copyString = ""
            let section = indexPath.section
            let row = indexPath.row
            let s = viewModel.sections()[section]
            switch s {
            case .display_name:
                let profile = viewModel.getProfile()
                copyString = profile.newDisplayName
            case .emails:
                let emails = viewModel.getEmails()
                let email = emails[row]
                copyString = email.newEmail
            case .cellphone:
                let cells = viewModel.getPhones()
                let tel = cells[row]
                copyString = tel.newPhone
            case .home_address:
                let addrs = viewModel.getAddresses()
                let addr = addrs[row]
                copyString = addr.fullAddress()
            case .information:
                let infos = viewModel.getInformations()
                let info = infos[row]
                copyString = info.newValue
            case .custom_field:
                let fields = viewModel.getFields()
                let field = fields[row]
                copyString = field.newField
            case .notes:
                let notes = viewModel.getNotes()
                let note = notes[row]
                copyString = note.newNote
            case .url:
                let urls = viewModel.getUrls()
                let url = urls[row]
                copyString = url.newUrl
            default:
                break
            }

            UIPasteboard.general.string = copyString
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let s = viewModel.sections()[indexPath.section]
        switch s {
        case .display_name, .emails, .cellphone, .home_address,
             .information, .custom_field, .notes, .url,
             .type2_warning, .type3_error, .type3_warning, .debuginfo:
            return UITableView.automaticDimension
        case .email_header, .encrypted_header, .delete:
            return 0.0
        case .upgrade:
            return 200 //  280.0
        case .share:
            return 38.0
        }
    }

    func tableView(_ tableView: UITableView, canFocusRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = indexPath.section
        let row = indexPath.row
        let s = viewModel.sections()[section]
        switch s {
        case .emails:
            guard !viewModel.user.isStorageExceeded else {
                LocalString._storage_exceeded.alertToastBottom()
                return
            }
            let emails = viewModel.getEmails()
            let email = emails[row]
            let contact = viewModel.contact
            let contactVO = ContactVO(name: contact.name,
                                      email: email.newEmail,
                                      isProtonMailContact: false)
            presentComposer(contact: contactVO)
        case .encrypted_header:
            break
        case .cellphone:
            let phone = viewModel.getPhones()[row]
            systemPhoneCall(phone: phone)
        case .home_address:
            let addrs = viewModel.getAddresses()
            let addr = addrs[row]
            let fulladdr = addr.fullAddress()
            if !fulladdr.isEmpty {
                let fullUrl = "http://maps.apple.com/?q=\(fulladdr)"
                if let strUrl = fullUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: strUrl)
                {
                    if #available(iOS 10.0, *) {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    } else {
                        UIApplication.shared.openURL(url)
                    }
                }
            }
        case .url:
            let urls = viewModel.getUrls()
            let url = urls[row]
            if let urlURL = URL(string: url.origUrl),
               var comps = URLComponents(url: urlURL, resolvingAgainstBaseURL: false)
            {
                if comps.scheme == nil {
                    comps.scheme = "http"
                }
                if let validUrl = comps.url {
                    let application = UIApplication.shared
                    if application.canOpenURL(validUrl) {
                        if #available(iOS 10.0, *) {
                            application.open(validUrl, options: [:], completionHandler: nil)
                        } else {
                            application.openURL(validUrl)
                        }
                        break
                    }
                }
            }
            LocalString._invalid_url.alertToastBottom()

        case .share:
            let cell = tableView.cellForRow(at: indexPath)
            shareVcard(cell)
        default:
            break
        }
    }

    private func shareVcard(_ sender: UIView?) {
        let exported = viewModel.export()
        if !exported.isEmpty {
            let filename = viewModel.exportName()
            let tempFileUri = FileManager.default.attachmentDirectory.appendingPathComponent(filename)

            try? exported.write(to: tempFileUri, atomically: true, encoding: String.Encoding.utf8)

            // set up activity view controller
            let urlToShare = [tempFileUri]
            let activityViewController = UIActivityViewController(activityItems: urlToShare, applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceView = view
            activityViewController.popoverPresentationController?.sourceRect = (sender == nil ? view.frame : sender!.frame)
            // exclude some activity types from the list (optional)
            activityViewController.excludedActivityTypes = [.postToFacebook,
                                                            .postToTwitter,
                                                            .postToWeibo,
                                                            .copyToPasteboard,
                                                            .saveToCameraRoll,
                                                            .addToReadingList,
                                                            .postToFlickr,
                                                            .postToVimeo,
                                                            .postToTencentWeibo,
                                                            .assignToContact]
            activityViewController.excludedActivityTypes?.append(.markupAsPDF)
            activityViewController.excludedActivityTypes?.append(.openInIBooks)
            present(activityViewController, animated: true, completion: nil)
        }
    }
}

extension ContactDetailViewController: UndoActionHandlerBase {
    var undoActionManager: UndoActionManagerProtocol? {
        nil
    }

    var delaySendSeconds: Int {
        self.viewModel.user.userInfo.delaySendSeconds
    }

    var composerPresentingVC: UIViewController? {
        navigationController
    }

    func showUndoAction(undoTokens: [String], title: String) { }
}
