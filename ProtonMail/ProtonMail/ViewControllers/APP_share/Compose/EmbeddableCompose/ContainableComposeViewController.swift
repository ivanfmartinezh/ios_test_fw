//
//  EditorViewController.swift
//  Proton Mail - Created on 25/03/2019.
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

import UIKit
import PromiseKit
import ProtonCore_Foundations
import ProtonCore_UIFoundations
import WebKit

/// The class hierarchy is following: ContainableComposeViewController > ComposeViewController > HorizontallyScrollableWebViewContainer > UIViewController
///
/// HtmlEditorBehavior only adds some functionality to HorizontallyScrollableWebViewContainer's webView, is not a UIView or webView's delegate any more. ComposeViewController is tightly coupled with ComposeHeaderViewController and needs separate refactor, while ContainableComposeViewController and HorizontallyScrollableWebViewContainer contain absolute minimum of logic they need: logic allowing to embed composer into tableView cell and logic allowing 2D scroll in fullsize webView.
///
class ContainableComposeViewController: ComposeContentViewController, BannerRequester {
    private var latestErrorBanner: BannerView?
    private var heightObservation: NSKeyValueObservation!
    private var queueObservation: NSKeyValueObservation!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ColorProvider.BackgroundNorm
        self.webView.scrollView.clipsToBounds = false
        
        self.heightObservation = self.htmlEditor.observe(\.contentHeight, options: [.new, .old]) { [weak self] htmlEditor, change in
            guard let self = self, change.oldValue != change.newValue else { return }

            let totalHeight = htmlEditor.contentHeight
            self.updateHeight(to: totalHeight)
            self.viewModel.contentHeight = totalHeight
        }

        NotificationCenter.default.addObserver(self, selector: #selector(self.willShowMenuNotification), name: UIMenuController.willShowMenuNotification, object: nil)

        // notifications
        #if APP_EXTENSION
        NotificationCenter.default.addObserver(self, selector: #selector(self.errorOccurredNotification(notification:)), name: NSError.errorOccuredNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.noErrorNotification), name: NSError.noErrorNotification, object: nil)
        #endif
        generateAccessibilityIdentifiers()
    }

    @objc func removeStyleFromSelection() {
        self.htmlEditor.removeStyleFromSelection()
    }

    @objc private func willShowMenuNotification() {
        let saveMenuItem = UIMenuItem(title: LocalString._clear_style, action: #selector(self.removeStyleFromSelection))
        UIMenuController.shared.menuItems = [saveMenuItem]
    }

    @objc private func errorOccurredNotification(notification: NSNotification) {
        #if APP_EXTENSION
            if self.step.contains(.storageExceeded) { return }
            self.latestError = notification.userInfo?["text"] as? String
            if self.latestError == LocalString._storage_exceeded {
                self.step.insert(.storageExceeded)
            } else {
                self.step.insert(.sendingFinishedWithError)
            }
        #endif
    }

    @objc private func noErrorNotification() {
        #if APP_EXTENSION
            self.step.insert(.sendingFinishedSuccessfully)
        #endif
    }

    override func shouldDefaultObserveContentSizeChanges() -> Bool {
        return false
    }

    deinit {
        self.heightObservation = nil
        self.queueObservation = nil
    }

    override func caretMovedTo(_ offset: CGPoint) {
        self.stopInertia()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) { [weak self] in
            guard let self = self, let enclosingScroller = self.enclosingScroller else { return }
             // approx height and width of our text row
            let сaretBounds = CGSize(width: 100, height: 100)

            // horizontal
            let offsetAreaInWebView = CGRect(x: offset.x - сaretBounds.width / 2, y: 0, width: сaretBounds.width, height: 1)
            self.webView.scrollView.scrollRectToVisible(offsetAreaInWebView, animated: true)

            // vertical
            let offsetAreaInCell = CGRect(x: 0, y: offset.y - сaretBounds.height / 2, width: 1, height: сaretBounds.height)
            let offsetArea = self.view.convert(offsetAreaInCell, to: enclosingScroller.scroller)
            enclosingScroller.scroller.scrollRectToVisible(offsetArea, animated: true)
        }
    }

    override func webViewPreferences() -> WKPreferences {
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        preferences.javaScriptCanOpenWindowsAutomatically = false
        return preferences
    }

    override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.htmlEditor.loadContentIfNeeded()
        super.webView(webView, didFinish: navigation)
    }

    override func addInlineAttachment(_ sid: String, data: Data, completion: (() -> Void)?) {
        guard viewModel.validateAttachmentsSize(withNew: data) == true else {
            DispatchQueue.main.async {
                self.latestErrorBanner?.remove(animated: true)
                self.latestErrorBanner = BannerView(appearance: .red, message: LocalString._the_total_attachment_size_cant_be_bigger_than_25mb, buttons: nil, offset: 8.0)
                #if !APP_EXTENSION
                UIApplication.shared.sendAction(#selector(BannerPresenting.presentBanner(_:)), to: nil, from: self, for: nil)
                #else
                // hackish way to get to UIApplication in Share extension
                (self.view.window?.next as? UIApplication)?.sendAction(#selector(BannerPresenting.presentBanner(_:)), to: nil, from: self, for: nil)
                #endif
            }

            self.htmlEditor.remove(embedImage: "cid:\(sid)")
            completion?()
            return
        }
        return super.addInlineAttachment(sid, data: data, completion: completion)
    }

    func errorBannerToPresent() -> BannerView? {
        return self.latestErrorBanner
    }

// TODO: when refactoring ComposeViewController, place this stuff in a higher level ViewModel and Controller - ComposeContainer
#if APP_EXTENSION
    private var latestError: String?
    private struct SendingStep: OptionSet {
        let rawValue: Int

        static var composing = SendingStep(rawValue: 1 << 0)
        static var composingCanceled = SendingStep(rawValue: 1 << 1)
        static var sendingStarted = SendingStep(rawValue: 1 << 2)
        static var sendingFinishedWithError = SendingStep(rawValue: 1 << 3)
        static var sendingFinishedSuccessfully = SendingStep(rawValue: 1 << 4)
        static var resultAcknowledged = SendingStep(rawValue: 1 << 5)
        static var queueIsEmpty = SendingStep(rawValue: 1 << 6)
        static var storageExceeded = SendingStep(rawValue: 1 << 7)
    }

    private var step: SendingStep = .composing {
        didSet {
            if step.contains(.storageExceeded) {
                let title = LocalString._storage_exceeded
                let message = LocalString._please_upgrade_plan
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(.init(title: LocalString._general_ok_action, style: .default, handler: { [weak self] _ in self?.dismissAnimation() }))
                self.stepAlert = alert
                return
            }
            guard !step.contains(.composing) else {
                return
            }
            if step.contains(.resultAcknowledged) && step.contains(.queueIsEmpty) {
                self.dismissAnimation()
                return
            }
            if step.contains(.queueIsEmpty) {
                return
            }
            if step.contains(.sendingFinishedSuccessfully) {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) { [weak self] in
                    self?.step.insert(.resultAcknowledged)
                }

                let alert = UIAlertController(title: "✅", message: LocalString._message_sent_ok_desc, preferredStyle: .alert)
                self.stepAlert = alert
                return
            }
            if step.contains(.sendingFinishedWithError) {
                let alert = UIAlertController(title: "⚠️", message: self.latestError, preferredStyle: .alert)
                alert.addAction(.init(title: "Ok", style: .default, handler: { [weak self] _ in self?.step = .composing }))
                self.stepAlert = alert
                return
            }
            if step.contains(.composingCanceled) {
                let alert = UIAlertController(title: LocalString._closing_draft,
                                                   message: LocalString._please_wait_in_foreground,
                                                   preferredStyle: .alert)
                self.stepAlert = alert
                return
            }
            if step.contains(.sendingStarted) {
                let alert = UIAlertController(title: LocalString._sending_message,
                                               message: LocalString._please_wait_in_foreground,
                                               preferredStyle: .alert)

                self.stepAlert = alert
                return
            }
        }
    }
    private var stepAlert: UIAlertController? {
        didSet {
            DispatchQueue.main.async {
                self.presentedViewController?.dismiss(animated: false)
                if let alert = self.stepAlert {
                    self.present(alert, animated: false, completion: nil)
                }
            }
        }
    }

    override func cancel() {
        self.step = [.composingCanceled, .resultAcknowledged]
    }

    override func startSendingMessage() {
        super.startSendingMessage()
        self.step = .sendingStarted
    }

    override func dismiss() {
        [self.headerView.toContactPicker,
         self.headerView.ccContactPicker,
         self.headerView.bccContactPicker].forEach { $0.prepareForDesctruction() }

        NotificationCenter.default.addObserver(self, selector: #selector(self.updateStepWhenTheQueueIsEmpty), name: .queueIsEmpty, object: nil)
    }

    @objc private func updateStepWhenTheQueueIsEmpty() {
        guard !step.contains(.queueIsEmpty) else { return }
        self.step.insert(.queueIsEmpty)
    }

    private func dismissAnimation() {
        DispatchQueue.main.async {
            let animationBlock: () -> Void = { [weak self] in
                if let view = self?.navigationController?.view {
                    view.transform = CGAffineTransform(translationX: 0, y: view.frame.size.height)
                }
            }
            self.stepAlert = nil
            keymaker.lockTheApp()
            UIView.animate(withDuration: 0.25, animations: animationBlock) { _ in
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }

    @objc
    func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                return application.perform(#selector(openURL(_:)), with: url) != nil
            }
            responder = responder?.next
        }
        return false
    }
#endif
}
