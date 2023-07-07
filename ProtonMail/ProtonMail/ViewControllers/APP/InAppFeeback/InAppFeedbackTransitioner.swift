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

import UIKit

final class InAppFeedbackTransitioner: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromVC = transitionContext.viewController(forKey: .from),
              let toVC = transitionContext.viewController(forKey: .to) else {
            return
        }
        if let toVC = toVC as? InAppFeedbackViewController {
            toVC.view.alpha = 0.0
            toVC.view.layoutIfNeeded()
            let finalFrame = toVC.actionSheetView.frame
            toVC.actionSheetView.frame.origin.y += finalFrame.height
            transitionContext.containerView.addSubview(toVC.view)
            UIView.animate(withDuration: transitionDuration(using: transitionContext),
                           animations: {
                            toVC.view.alpha = 1.0
                            toVC.actionSheetView.frame = finalFrame
            }, completion: { _ in
                transitionContext.completeTransition(true)
            })
        } else if let fromVC = fromVC as? InAppFeedbackViewController {
            UIView.animate(withDuration: transitionDuration(using: transitionContext),
                           animations: {
                            fromVC.view.alpha = 0.0
                            fromVC.actionSheetView.frame.origin.y += fromVC.actionSheetView.frame.height
            }, completion: { _ in
                transitionContext.completeTransition(true)
            })
        } else {
            return
        }
    }
}
