//
//  ImageProcessor.swift
//  Proton Mail - Created on 28/06/2018.
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
import Photos
import PromiseKit

protocol ImageProcessor {
    func process(original originalImage: UIImage) -> Promise<Void>
    func process(asset: PHAsset)
}
extension ImageProcessor where Self: AttachmentProvider {

    private func writeItemToTempDirectory(_ item: Data, filename: String) throws -> URL {
        let tempFileUrl = try FileManager.default.createTempURL(forCopyOfFileNamed: filename)
        try item.write(to: tempFileUrl)
        return tempFileUrl
    }

    internal func process(original originalImage: UIImage) -> Promise<Void> {
        let fileName = "\(NSUUID().uuidString).PNG"
        let ext = "image/png"
        var fileData: FileData!

        #if APP_EXTENSION
            guard let data = originalImage.pngData(),
                let newUrl = try? self.writeItemToTempDirectory(data, filename: fileName) else {
                self.controller?.error(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil).description)
                return Promise()
            }
            fileData = ConcreteFileData(name: fileName, ext: ext, contents: newUrl)
        #else
            fileData = ConcreteFileData(name: fileName, ext: ext, contents: originalImage)
        #endif

        return self.controller?.fileSuccessfullyImported(as: fileData) ?? Promise()
    }

    internal func process(asset: PHAsset) {
        switch asset.mediaType {
        case .video:
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.progressHandler = { progress, error, pointer, info in
                DispatchQueue.main.async {
                    (LocalString._importing + " \(Int(progress * 100))%").alertToastBottom()
                }
            }
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options, resultHandler: { asset, audioMix, info in
                if let error = info?[PHImageErrorKey] as? NSError {
                    DispatchQueue.main.async {
                        self.controller?.error(error.debugDescription)
                    }
                    return
                }

                var fileData: ConcreteFileData?
                var isSlowMotion = false

                if let asset = asset as? AVURLAsset,
                   let image_data = try? Data(contentsOf: asset.url) { // video files
                    let fileName = asset.url.lastPathComponent
                    fileData = ConcreteFileData(name: fileName, ext: fileName.mimeType(), contents: image_data)
                } else if let asset = asset as? AVComposition,
                          let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) { // slow motion files
                    isSlowMotion = true

                    convertMovieFilesForSlowMotionVideo(exportSession: exportSession) { fileData in
                        self.controller?.fileSuccessfullyImported(as: fileData).cauterize()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.controller?.error(LocalString._cant_open_the_file)
                    }
                    return
                }

                guard !isSlowMotion else {
                    return
                }

                guard let fileData = fileData else {
                    DispatchQueue.main.async {
                        self.controller?.error(LocalString._cant_open_the_file)
                    }
                    return
                }
                self.controller?.fileSuccessfullyImported(as: fileData).cauterize()
            })

        case .image:
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.progressHandler = { progress, error, pointer, info in
                DispatchQueue.main.async {
                    (LocalString._importing + " \(Int(progress * 100))%").alertToastBottom()
                }
            }
            PHImageManager.default().requestImageData(for: asset, options: options) { imagedata, dataUTI, orientation, info in
                guard var image_data = imagedata, /* let _ = dataUTI,*/ let info = info, image_data.count > 0 else {
                    DispatchQueue.main.async {
                        self.controller?.error(LocalString._cant_open_the_file)
                    }
                    return
                }
                var fileName = "\(NSUUID().uuidString).jpg"
                if let url = info["PHImageFileURLKey"] as? NSURL, let url_filename = url.lastPathComponent {
                    fileName = url_filename
                }

                let UTIstr = dataUTI ?? ""

                if fileName.preg_match(".(heif|heic)") || UTIstr.preg_match(".(heif|heic)") {
                    if let rawImage = UIImage(data: image_data) {
                        if let newData = rawImage.jpegData(compressionQuality: 1.0), newData.count > 0 {
                            image_data = newData
                            fileName = fileName.preg_replace(".(heif|heic)", replaceto: ".jpeg")
                        }
                    }
                }
                let fileData = ConcreteFileData(name: fileName, ext: fileName.mimeType(), contents: image_data)
                self.controller?.fileSuccessfullyImported(as: fileData).cauterize()
            }

        default:
            self.controller?.error(LocalString._cant_open_the_file)
        }
    }

    private func convertMovieFilesForSlowMotionVideo(exportSession: AVAssetExportSession, completion: ((ConcreteFileData) -> Void)?) {
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        exportSession.outputURL = tempUrl
        exportSession.outputFileType = AVFileType.mov
        exportSession.shouldOptimizeForNetworkUse = true

        exportSession.exportAsynchronously {
            defer {
                try? FileManager.default.removeItem(at: tempUrl)
            }
            let exportedAsset = AVURLAsset(url: tempUrl)

            guard let videoData = try? Data(contentsOf: exportedAsset.url) else {
                DispatchQueue.main.async {
                    self.controller?.error(LocalString._cant_open_the_file)
                }
                return
            }

            let fileName = exportedAsset.url.lastPathComponent
            let fileData = ConcreteFileData(name: fileName, ext: fileName.mimeType(), contents: videoData)
            completion?(fileData)
        }
    }
}
