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

import ProtonCore_UIFoundations
import UIKit

final class InAppFeedbackViewController: UIViewController {
    private var viewModel: InAppFeedbackViewModelProtocol
    private(set) var actionSheetView: InAppFeedbackActionSheetView!
    private var bottomActionSheetConstraint: NSLayoutConstraint!

    init(viewModel: InAppFeedbackViewModelProtocol) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        let onDismissActionSheet = { [weak self] in
            self?.viewModel.cancelFeedback()
            self?.dismiss(animated: true, completion: nil)
        }
        let onSubmitActionSheet = { [weak self] (comment: String?) in
            if let comment = comment {
                self?.viewModel.updateFeedbackComment(comment: comment)
            }

            self?.viewModel.submitFeedback()

            self?.dismiss(animated: true, completion: nil)
        }
        self.actionSheetView = InAppFeedbackActionSheetView(ratings: viewModel.ratingScale,
                                                            onRatingSelection: viewModel.select(rating:),
                                                            onDismiss: onDismissActionSheet,
                                                            onSubmit: onSubmitActionSheet)
        self.viewModel.updateViewCallback = { [weak self] in
            self?.actionSheetView.feedbackCommentView.commentTextView.resignFirstResponder()
            self?.actionSheetView.expandIfNeeded()
        }
        providesPresentationContextTransitionStyle = true
        definesPresentationContext = true
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addKeyboardObserver(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeKeyboardObserver(self)
    }

    private func setup() {
        self.view.backgroundColor = ColorProvider.BlenderNorm
        self.view.addSubview(actionSheetView)
        let tapToDismiss = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        self.view.addGestureRecognizer(tapToDismiss)
        [
            actionSheetView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionSheetView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ].activate()
        bottomActionSheetConstraint = actionSheetView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        view.addConstraint(bottomActionSheetConstraint)
        addWhiteView()
    }

    private func addWhiteView() {
        let whiteView = UIView(frame: .zero)
        whiteView.backgroundColor = ColorProvider.BackgroundNorm
        self.view.insertSubview(whiteView, at: 0)
        [
            whiteView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            whiteView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            whiteView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            whiteView.heightAnchor.constraint(equalToConstant: 150)
        ].activate()
    }

    @objc
    private func backgroundTapped(gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self.actionSheetView)
        guard point.y < 0 else { return }
        viewModel.cancelFeedback()
        dismiss(animated: true)
    }
}

extension InAppFeedbackViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        InAppFeedbackTransitioner()
    }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        InAppFeedbackTransitioner()
    }
}

extension InAppFeedbackViewController: NSNotificationCenterKeyboardObserverProtocol {
    func keyboardWillHideNotification(_ notification: Notification) {
        let keyboardInfo = notification.keyboardInfo
        bottomActionSheetConstraint.constant = 0
        UIView.animate(withDuration: keyboardInfo.duration,
                       delay: 0,
                       options: keyboardInfo.animationOption,
                       animations: {
                        self.view.layoutIfNeeded()
                       },
                       completion: nil)
    }

    func keyboardWillShowNotification(_ notification: Notification) {
        let keyboardInfo = notification.keyboardInfo
        bottomActionSheetConstraint.constant = -keyboardInfo.endFrame.size.height
        UIView.animate(withDuration: keyboardInfo.duration,
                       delay: 0,
                       options: keyboardInfo.animationOption,
                       animations: {
                        self.view.layoutIfNeeded()
                       },
                       completion: nil)
    }
}
