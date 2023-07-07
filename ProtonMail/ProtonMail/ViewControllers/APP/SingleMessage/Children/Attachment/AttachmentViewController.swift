//
//  AttachmentViewController.swift
//  Proton Mail
//
//
//  Copyright (c) 2021 Proton AG
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

protocol AttachmentViewControllerDelegate: AnyObject {
    func openAttachmentList(with attachments: [AttachmentInfo])
}

class AttachmentViewController: UIViewController {
    private let viewModel: AttachmentViewModel
    private(set) lazy var customView = AttachmentView()

    weak var delegate: AttachmentViewControllerDelegate?

    init(viewModel: AttachmentViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = customView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel.reloadView = { [weak self] in
            guard let self = self else { return }
            self.setup(view: self.customView, with: self.viewModel)
        }

        setup(view: customView, with: viewModel)
        setUpTapGesture()
    }

    private func setup(view: AttachmentView, with data: AttachmentViewModel) {
        var text = String(format: LocalString._attachment, data.numberOfAttachments)

        let byteCountFormatter = ByteCountFormatter()
        let sizeString = "(\(byteCountFormatter.string(fromByteCount: Int64(data.totalSizeOfAllAttachments))))"

        text += sizeString
        view.titleLabel.set(text: text,
                            preferredFont: .subheadline)
    }

    private func setUpTapGesture() {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
        customView.addGestureRecognizer(gesture)
    }

    @objc
    private func handleTap() {
        delegate?.openAttachmentList(with: Array(viewModel.attachments).sorted(by: { $0.order < $1.order }))
    }
}

extension AttachmentViewController: CustomViewPrintable {
    func printPageRenderer() -> CustomViewPrintRenderer {
        let newView = AttachmentView()
        if #available(iOS 13, *) {
            newView.overrideUserInterfaceStyle = .light
        }
        self.setup(view: newView, with: viewModel)
        newView.backgroundColor = .white
        return CustomViewPrintRenderer(newView)
    }

    func printingWillStart(renderer: CustomViewPrintRenderer) {
        guard let newView = renderer.view as? AttachmentView else { return }

        newView.widthAnchor.constraint(equalToConstant: 560).isActive = true
        newView.layoutIfNeeded()

        renderer.updateImage(in: newView.frame)
    }
}
