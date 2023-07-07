//
//  ShareUnlockViewController.swift
//  Share - Created on 7/13/17.
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

import CoreServices
import MBProgressHUD
import PromiseKit
import ProtonCore_Services
import ProtonCore_UIFoundations
import UIKit

var sharedUserDataService: UserDataService!

class ShareUnlockViewController: UIViewController, BioCodeViewDelegate {
    private weak var coordinator: ShareUnlockCoordinator?

    func set(coordinator: ShareUnlockCoordinator) {
        self.coordinator = coordinator
    }

    @IBOutlet weak var bioContainerView: UIView!
    var bioCodeView: BioCodeView?

    //
    var inputSubject: String! = ""
    var inputContent: String! = ""
    var files = [FileData]()
    fileprivate var currentAttachmentSize: Int = 0

    //
    internal lazy var documentAttachmentProvider = DocumentAttachmentProvider(for: self)
    internal lazy var imageAttachmentProvider = PhotoAttachmentProvider(for: self)

    // pre - defined
    private let propertylist_ket = kUTTypePropertyList as String
    private let url_key = kUTTypeURL as String
    private var localized_errors: [String] = []
    private var isUnlock = false

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sharedUserDataService = UserDataService(api: PMAPIService.shared)
        LanguageManager().setupCurrentLanguage()
        configureNavigationBar()

        let bioView = BioCodeView(frame: .zero)
        bioContainerView.addSubview(bioView)
        bioView.fillSuperview()
        self.bioCodeView = bioView
        self.bioCodeView?.delegate = self
        self.bioCodeView?.setup()

        // Do any additional setup after loading the view.
        self.navigationItem.title = ""
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.cancel,
                                                                target: self,
                                                                action: #selector(ShareUnlockViewController.cancelButtonTapped(sender:)))

        NotificationCenter.default.addObserver(self, selector: #selector(self.didUnlock), name: NSNotification.Name.didUnlock, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        MBProgressHUD.showAdded(to: view, animated: true)
        guard let inputitems = self.extensionContext?.inputItems as? [NSExtensionItem] else {
            self.showErrorAndQuit(errorMsg: LocalString._cant_load_share_content)
            return
        }

        let group = DispatchGroup()
        self.parse(items: inputitems, group: group)
        group.notify(queue: DispatchQueue.global(qos: .userInteractive)) { [unowned self] in
            DispatchQueue.main.async { [unowned self] in
                MBProgressHUD.hide(for: self.view, animated: true)
                // go to composer
                guard self.localized_errors.isEmpty else {
                    self.showErrorAndQuit(errorMsg: self.localized_errors.first ?? LocalString._cant_load_share_content)
                    return
                }
                guard sharedServices.get(by: UsersManager.self).hasUsers() else {
                    self.showErrorAndQuit(errorMsg: LocalString._please_use_protonmail_app_signin_first)
                    return
                }
                self.loginCheck()
            }
        }
    }

    private func parse(items: [NSExtensionItem], group: DispatchGroup) {
        defer {
            group.leave()// #0
        }
        group.enter() // #0
        for item in items {
            let plainText = item.attributedContentText?.string
            if let attachments = item.attachments {
                for att in attachments {
                    let itemProvider = att
                    if let type = itemProvider.hasItem(types: self.filetypes) {
                        group.enter() // #1
                        self.importFile(itemProvider, type: type, errorHandler: self.error) {
                            group.leave() // #1
                        }
                    } else if itemProvider.hasItemConformingToTypeIdentifier(propertylist_ket) {
                    } else if itemProvider.hasItemConformingToTypeIdentifier(url_key) {
                        group.enter()// #2
                        itemProvider.loadItem(forTypeIdentifier: url_key, options: nil) { [unowned self] url, error in
                            defer {
                                group.leave()// #2
                            }
                            if let shareURL = url as? NSURL {
                                self.inputSubject = plainText ?? ""
                                let url = shareURL.absoluteString ?? ""
                                self.inputContent = self.inputContent + "\n" + "<a href=\"\(url)\">\(url)</a>"
                            } else {
                                self.error(LocalString._cant_load_share_content)
                            }
                        }
                    } else if let pt = plainText {
                        self.inputSubject = ""
                        self.inputContent = self.inputContent + "\n" + pt
                    }

                }
            }
        }
    }

    // set up UI only
    internal func loginCheck() {
        let unlockManager = sharedServices.get(by: UnlockManager.self)
        switch unlockManager.getUnlockFlow() {
        case .requirePin:
            self.bioCodeView?.loginCheck(.requirePin)
            self.coordinator?.go(dest: .pin)

        case .requireTouchID:
            self.bioCodeView?.loginCheck(.requireTouchID)
            self.authenticateUser()

        case .restore:
            unlockManager.initiateUnlock(flow: .restore, requestPin: { }, requestMailboxPassword: {})
        }
    }

    private func showErrorAndQuit(errorMsg: String) {
        self.bioCodeView?.showErrorAndQuit()

        let alertController = UIAlertController(title: LocalString._share_alert, message: errorMsg, preferredStyle: .alert)
        let action = UIAlertAction(title: LocalString._general_close_action, style: .default) { action in
            self.hideExtensionWithCompletionHandler { _ in
                let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
                self.extensionContext?.cancelRequest(withError: cancelError)
            }
        }
        alertController.addAction(action)
        self.present(alertController, animated: true, completion: nil)
    }

    func signInIfRememberedCredentials() {
        self.coordinator?.go(dest: .composer)
    }

    @objc func cancelButtonTapped(sender: UIBarButtonItem) {
        self.hideExtensionWithCompletionHandler { _ in
            let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
            self.extensionContext?.cancelRequest(withError: cancelError)
        }
    }

    func touch_id_action(_ sender: Any) {
        self.authenticateUser()
    }

    func authenticateUser() {
        let unlockManager = sharedServices.get(by: UnlockManager.self)
        unlockManager.biometricAuthentication(afterBioAuthPassed: {
            unlockManager.unlockIfRememberedCredentials(requestMailboxPassword: { },
                                                        unlocked:  {
                self.signInIfRememberedCredentials()
            })
        })
    }

    func hideExtensionWithCompletionHandler(completion:@escaping (Bool) -> Void) {
        UIView.animate(withDuration: 0.50,
                       animations: {
                            if let view = self.navigationController?.view {
                                view.transform = CGAffineTransform(translationX: 0, y: view.frame.size.height)
                            }
                       },
                       completion: completion)
    }

    func configureNavigationBar() {
        if let bar = self.navigationController?.navigationBar {
            bar.barTintColor = ColorProvider.BackgroundNorm
            bar.isTranslucent = false
            bar.tintColor = ColorProvider.TextNorm
            bar.titleTextAttributes = [
                NSAttributedString.Key.foregroundColor: ColorProvider.TextNorm as UIColor,
                NSAttributedString.Key.font: Fonts.h2.regular
            ]
        }
    }

    @objc private func didUnlock() {
        DispatchQueue.main.async {
            guard self.isUnlock == false else { return }
            self.signInIfRememberedCredentials()
            self.isUnlock = true
        }
    }
}

extension ShareUnlockViewController: AttachmentController, FileImporter {
    func error(title: String, description: String) {
        self.localized_errors.append(description)
    }

    func error(_ description: String) {
        self.localized_errors.append(description)
    }

    func fileSuccessfullyImported(as fileData: FileData) -> Promise<Void> {
        return Promise { seal in
            guard fileData.contents.dataSize < (Constants.kDefaultAttachmentFileSize - self.currentAttachmentSize) else {
                self.error(LocalString._the_total_attachment_size_cant_be_bigger_than_25mb)
                seal.fulfill_()
                return
            }

            self.files.append(fileData)
            seal.fulfill_()
        }
    }
}
