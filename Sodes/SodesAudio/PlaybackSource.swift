//
//  PlaybackSource.swift
//  SodesAudio
//
//  Created by Jared Sinclair on 7/16/16.
//
//

import Foundation
import UIKit
import MediaPlayer

public protocol PlaybackSource {
    var uniqueId: String { get }
    var artistId: String { get }
    var remoteUrl: URL { get }
    var title: String? { get }
    var albumTitle: String? { get }
    var artist: String? { get }
    var artworkUrl: URL? { get }
    var artworkImage: UIImage? { get }
    var mediaType: MPMediaType { get }
    var expectedLengthInBytes: Int64? { get }    
}

internal extension PlaybackSource {

    func nowPlayingInfo(image: UIImage? = nil, duration: TimeInterval? = nil, elapsedPlaybackTime: TimeInterval? = nil, rate: Double? = nil) -> [String: Any] {
        var info: [String: Any] = [:]

        if #available(iOS 10.0, *) {
            info[MPMediaItemPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        }

        if let title = title {
            info[MPMediaItemPropertyTitle] = title
        }
        if let albumTitle = albumTitle {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        if let artist = artist {
            info[MPMediaItemPropertyArtist] = artist
            info[MPMediaItemPropertyAlbumArtist] = artist
        }
        if let image = image {
            let artwork: MPMediaItemArtwork
            if #available(iOS 10.0, *) {
                artwork = MPMediaItemArtwork(boundsSize: image.size) { (inputSize) -> UIImage in
                    return image.draw(at: inputSize)
                }
            }
            else {
                artwork = MPMediaItemArtwork(image: image)
            }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if let duration = UInt.withInterval(duration) {
            info[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: duration)
        }
        if let time = elapsedPlaybackTime {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: time)
        }
        if let rate = rate {
            info[MPNowPlayingInfoPropertyPlaybackRate] = NSNumber(value: rate)
        }

        return info
    }

}

private extension UIImage {

    func draw(at targetSize: CGSize) -> UIImage {
        guard !self.size.equalTo(CGSize.zero) else {
            return self
        }

        guard !targetSize.equalTo(CGSize.zero) else {
            return self
        }

        let scaledSize = sizeThatFills(targetSize)
        let x = (targetSize.width - scaledSize.width) / 2.0
        let y = (targetSize.height - scaledSize.height) / 2.0
        let drawingRect = CGRect(x: x, y: y, width: scaledSize.width, height: scaledSize.height)
        
        UIGraphicsBeginImageContextWithOptions(targetSize, true, 0)
        draw(in: drawingRect)
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage!
    }

    func sizeThatFills(_ other: CGSize) -> CGSize {
        guard !size.equalTo(CGSize.zero) else {
            return other
        }
        let heightRatio = other.height / size.height
        let widthRatio = other.width / size.width
        if heightRatio > widthRatio {
            return CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        }
        else {
            return CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
    }

}
