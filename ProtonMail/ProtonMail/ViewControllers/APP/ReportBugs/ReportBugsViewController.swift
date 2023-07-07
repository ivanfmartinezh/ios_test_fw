//
//  ReportBugsViewController.swift
//  Proton Mail
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
import LifetimeTracker
import MBProgressHUD
import ProtonCore_Payments
import ProtonCore_UIFoundations
import Reachability
import SideMenuSwift

class ReportBugsViewController: ProtonMailViewController, LifetimeTrackable {
    class var lifetimeConfiguration: LifetimeConfiguration {
        .init(maxCount: 1)
    }

    private let user: UserManager
    fileprivate let bottomPadding: CGFloat = 30.0
    fileprivate let textViewDefaultHeight: CGFloat = 120.0
    fileprivate var beginningVerticalPositionOfKeyboard: CGFloat = 30.0
    fileprivate let textViewInset: CGFloat = 16.0
    fileprivate let topTextViewMargin: CGFloat = 24.0

    fileprivate var sendButton: UIBarButtonItem!

    private let textView = UITextView()
    private weak var textViewHeightConstraint: NSLayoutConstraint!

    private var reportSent: Bool = false

    init(user: UserManager) {
        self.user = user

        super.init(nibName: nil, bundle: nil)
        trackLifetime()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ColorProvider.BackgroundSecondary
        self.sendButton = UIBarButtonItem(title: LocalString._general_send_action,
                                          style: UIBarButtonItem.Style.plain,
                                          target: self,
                                          action: #selector(ReportBugsViewController.sendAction(_:)))
        setUpSendButtonAttribute()
        self.navigationItem.rightBarButtonItem = sendButton

        if cachedBugReport.cachedBug.isEmpty {
            addPlaceholder()
        } else {
            removePlaceholder()
            textView.set(text: cachedBugReport.cachedBug, preferredFont: .body)
        }
        self.title = LocalString._menu_bugs_title

        setupMenuButton()
        setupTextView()
        setupLayout()
        NotificationCenter.default
            .addObserver(self,
                         selector: #selector(preferredContentSizeChanged(_:)),
                         name: UIContentSizeCategory.didChangeNotification,
                         object: nil)
    }

    func setUpSendButtonAttribute() {
        let sendButtonAttributes = FontManager.HeadlineSmall
        self.sendButton.setTitleTextAttributes(
            sendButtonAttributes.foregroundColor(ColorProvider.InteractionNormDisabled),
            for: .disabled
        )
        self.sendButton.setTitleTextAttributes(
            sendButtonAttributes.foregroundColor(ColorProvider.InteractionNorm),
            for: .normal
        )
    }

    func setupTextView() {
        self.textView.delegate = self
        self.textView.backgroundColor = ColorProvider.BackgroundNorm
        self.textView.textContainer.lineFragmentPadding = 0
        self.textView.textContainerInset = .init(all: textViewInset)
        setUpSideMenuMethods()

        self.view.addSubview(self.textView)
    }

    func setupLayout() {
        self.textViewHeightConstraint = self.textView.heightAnchor.constraint(equalToConstant: self.textViewDefaultHeight)

        [
            self.textView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 24),
            self.textView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.textView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            textViewHeightConstraint
        ].activate()
    }

    private func setUpSideMenuMethods() {
        let pmSideMenuController = sideMenuController as? PMSideMenuController
        pmSideMenuController?.willHideMenu = { [weak self] in
            self?.textView.becomeFirstResponder()
        }

        pmSideMenuController?.willRevealMenu = { [weak self] in
            self?.textView.resignFirstResponder()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateSendButtonForText(textView.text)
        NotificationCenter.default.addKeyboardObserver(self)
        textView.becomeFirstResponder()
        resizeHeightIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        textView.resignFirstResponder()
        NotificationCenter.default.removeKeyboardObserver(self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard let keywindow = UIApplication.shared.keyWindow, self.reportSent else { return }
        keywindow.enumerateViewControllerHierarchy { (controller, stop) in
            guard controller is MenuViewController else {return}
            let alert = UIAlertController(title: LocalString._bug_report_received,
                                          message: LocalString._thank_you_for_submitting_a_bug_report_we_have_added_your_report_to_our_bug_tracking_system,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: LocalString._general_ok_action, style: .default, handler: { (_) in

            }))
            controller.present(alert, animated: true, completion: {

            })

            stop = true
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        resizeHeightIfNeeded()
    }

    // MARK: - Private methods

    fileprivate func addPlaceholder() {
        textView.set(text: LocalString._bug_description, preferredFont: .body, textColor: ColorProvider.TextHint)
    }

    fileprivate func removePlaceholder() {
        textView.set(text: .empty, preferredFont: .body)
    }

    fileprivate func reset() {
        removePlaceholder()
        cachedBugReport.cachedBug = ""
        updateSendButtonForText(textView.text)
        resizeHeightIfNeeded()
        addPlaceholder()
    }

    fileprivate func updateSendButtonForText(_ text: String?) {
        sendButton.isEnabled = (text != nil) && !text!.isEmpty && !(text! == LocalString._bug_description)
    }

    @objc
    private func preferredContentSizeChanged(_ notification: Notification) {
        textView.font = .adjustedFont(forTextStyle: .body, weight: .regular)
        setUpSendButtonAttribute()
    }

    // MARK: Actions

    @IBAction fileprivate func sendAction(_ sender: UIBarButtonItem) {
        guard let text = textView.text, !text.isEmpty else {
            return
        }

        let storeKitManager = self.user.payments.storeKitManager
        if storeKitManager.hasUnfinishedPurchase(),
            let receipt = try? storeKitManager.readReceipt() {
            let alert = UIAlertController(title: LocalString._iap_bugreport_title, message: LocalString._iap_bugreport_user_agreement, preferredStyle: .alert)
            alert.addAction(.init(title: LocalString._iap_bugreport_yes, style: .default, handler: { _ in
                self.send(text + "\n\n\n --- AppStore receipt: ---\n\n\(receipt)")
            }))
            alert.addAction(.init(title: LocalString._iap_bugreport_no, style: UIAlertAction.Style.cancel, handler: { _ in
                self.send(text)
            }))
            self.present(alert, animated: true, completion: nil)
        } else {
            self.send(text)
        }
    }

    private func send(_ text: String) {
        let v: UIView = self.navigationController?.view ?? self.view
        MBProgressHUD.showAdded(to: v, animated: true)
        sendButton.isEnabled = false
        let username = self.user.defaultEmail.split(separator: "@")[0]
        let reachabilityStatus: String = (try? Reachability().connection.description) ?? Reachability.Connection.unavailable.description
        user.reportService.reportBug(text,
                                     username: String(username),
                                     email: self.user.defaultEmail,
                                     lastReceivedPush: SharedUserDefaults().lastReceivedPushTimestamp,
                                     reachabilityStatus: reachabilityStatus) { error in
            MBProgressHUD.hide(for: v, animated: true)
            self.sendButton.isEnabled = true
            if let error = error {
                guard !self.checkDoh(error), !error.isBadVersionError else {
                    return
                }
                let alert = error.alertController(title: LocalString._offline_bug_report)
                alert.addAction(UIAlertAction(title: LocalString._general_ok_action, style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
            } else {
                self.reportSent = true
                self.reset()
                NotificationCenter.default.post(name: .switchView, object: nil)
            }
        }
    }

    private func checkDoh(_ error: NSError) -> Bool {
        guard BackendConfiguration.shared.doh.errorIndicatesDoHSolvableProblem(error: error) else {
            return false
        }

        let message = error.localizedDescription
        let alertController = UIAlertController(title: LocalString._protonmail,
                                                message: message,
                                                preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Troubleshoot", style: .default, handler: { action in
            let troubleShootView = NetworkTroubleShootViewController(viewModel: NetworkTroubleShootViewModel())
            let nav = UINavigationController(rootViewController: troubleShootView)
            self.present(nav, animated: true, completion: nil)
        }))
        alertController.addAction(UIAlertAction(title: LocalString._general_cancel_button, style: .cancel, handler: { action in

        }))
        UIApplication.shared.keyWindow?.rootViewController?.present(alertController, animated: true, completion: nil)

        return true
    }

    fileprivate func resizeHeightIfNeeded() {
        let maxTextViewSize = CGSize(width: textView.frame.size.width, height: CGFloat.greatestFiniteMagnitude)
        let wantedHeightAfterVerticalGrowth = textView.sizeThatFits(maxTextViewSize).height
        if wantedHeightAfterVerticalGrowth < textViewDefaultHeight {
            textViewHeightConstraint.constant = textViewDefaultHeight
        } else {
            let heightMinusKeyboard = view.bounds.height - topTextViewMargin - beginningVerticalPositionOfKeyboard
            textViewHeightConstraint.constant = min(wantedHeightAfterVerticalGrowth + textViewInset * 2, heightMinusKeyboard)
        }
    }
}

// MARK: - NSNotificationCenterKeyboardObserverProtocol

extension ReportBugsViewController: NSNotificationCenterKeyboardObserverProtocol {
    func keyboardWillHideNotification(_ notification: Notification) {
        let keyboardInfo = notification.keyboardInfo
        beginningVerticalPositionOfKeyboard = bottomPadding
        resizeHeightIfNeeded()
        UIView.animate(withDuration: keyboardInfo.duration, delay: 0, options: keyboardInfo.animationOption, animations: { () -> Void in
            self.view.layoutIfNeeded()
            }, completion: nil)
    }

    func keyboardWillShowNotification(_ notification: Notification) {
        let keyboardInfo = notification.keyboardInfo
        beginningVerticalPositionOfKeyboard = view.window?.convert(keyboardInfo.endFrame, to: view).origin.y ?? bottomPadding
        resizeHeightIfNeeded()
    }
}

extension ReportBugsViewController: UITextViewDelegate {

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let oldText = textView.text as NSString
        let changedText = oldText.replacingCharacters(in: range, with: text)
        updateSendButtonForText(changedText)
        cachedBugReport.cachedBug = changedText
        resizeHeightIfNeeded()
        return true
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.text == LocalString._bug_description {
            removePlaceholder()
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            addPlaceholder()
        }
    }
}
