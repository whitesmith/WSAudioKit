//
//  ViewController.swift
//  SodesExample
//
//  Created by Jared Sinclair on 9/2/16.
//
//

import UIKit
import SodesAudio
import MediaPlayer
import AVKit

struct TestSource: PlaybackSource {
    let uniqueId: String = "abcxyz"
    var artistId: String = "123456"
    var remoteUrl: URL = URL(string: "http://content.blubrry.com/exponent/exponent86.mp3")!
    var title: String? = "Track Title"
    var albumTitle: String? = "Album Title"
    var artist: String? = "Artist"
    var artworkUrl: URL? = URL(string: "http://exponent.fm/wp-content/uploads/2014/02/cropped-Exponent-header.png")
    var artworkImage: UIImage? = nil
    var mediaType: MPMediaType = .podcast
    var expectedLengthInBytes: Int64? = nil
}

class ArtworkFetcher: ArtworkProvider {

    func getArtwork(for url: URL, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global().async {
            do {
                let image = UIImage(data: try Data(contentsOf: url))
                completion(image)
            }
            catch {
                completion(nil)
            }
        }
    }
    
}

class ViewController: UIViewController {
    
    @IBOutlet private var playPauseButton: UIButton!
    @IBOutlet private var backButton: UIButton!
    @IBOutlet private var forwardButton: UIButton!
    @IBOutlet private var progressBar: UIProgressView!
    @IBOutlet private var elapsedTimeLabel: UILabel!
    @IBOutlet private var remainingTimeLabel: UILabel!
    @IBOutlet private var activityIndicator: UIActivityIndicatorView!
    @IBOutlet private var byteRangeTextView: UITextView!

    let artworkFetcher = ArtworkFetcher()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.playPauseButton.setTitle("PLAY", for: .normal)

        PlaybackController.shared.artworkProvider = self.artworkFetcher

        PlaybackController.shared.prepare(TestSource(), startTime: 0, playWhenReady: true)

        if #available(iOS 11.0, *) {
            let routePickerView = AVRoutePickerView()
            routePickerView.tintColor = playPauseButton.tintColor
            routePickerView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(routePickerView)

            NSLayoutConstraint.activate([
                routePickerView.widthAnchor.constraint(equalToConstant: 40),
                routePickerView.heightAnchor.constraint(equalToConstant: 40),
                routePickerView.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
                routePickerView.bottomAnchor.constraint(equalTo: playPauseButton.topAnchor, constant: -10),
            ])
        }
        else {
            let volumeView = MPVolumeView()
            volumeView.backgroundColor = .red
            volumeView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(volumeView)

            NSLayoutConstraint.activate([
                volumeView.widthAnchor.constraint(equalToConstant: 300),
                volumeView.heightAnchor.constraint(equalToConstant: 40),
                volumeView.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
                volumeView.bottomAnchor.constraint(equalTo: playPauseButton.topAnchor, constant: -10),
            ])
        }

        let center = NotificationCenter.default
        
        center.addObserver(forName: PlaybackControllerNotification.DidUpdateElapsedTime.name, object: nil, queue: .main) { (note) in
            let controller = PlaybackController.shared
            guard
                let duration = controller.duration
            else {
                return
            }
            let elapsed = floor(controller.elapsedTime)
            self.elapsedTimeLabel.text = EpisodeDurationParsing.string(from: elapsed)
            let remaining = floor(duration - elapsed)
            self.remainingTimeLabel.text = EpisodeDurationParsing.string(from: remaining)
            self.progressBar.progress = Float(elapsed / duration)
        }
        
        center.addObserver(forName: PlaybackControllerNotification.DidUpdateStatus.name, object: nil, queue: .main) { (note) in
            switch PlaybackController.shared.status {
            case .buffering, .preparing(_,_):
                self.activityIndicator.startAnimating()
            case .paused(_), .idle:
                self.playPauseButton.setTitle("PLAY", for: .normal)
                self.activityIndicator.stopAnimating()
            case .playing:
                self.playPauseButton.setTitle("PAUSE", for: .normal)
                self.activityIndicator.stopAnimating()
            case .error(_):
                self.activityIndicator.stopAnimating()
            }
        }

        center.addObserver(forName: PlaybackControllerNotification.DidPlayToEnd.name, object: nil, queue: .main) { (note) in
            let key = PlaybackControllerNotification.SourceKey
            if let source = note.userInfo?[key] as? PlaybackSource {
                print("Ended", source)
            }
        }
    }
    
    @IBAction func togglePlayPause(sender: AnyObject?) {
        PlaybackController.shared.togglePlayPause()
    }
    
    @IBAction func back(sender: AnyObject?) {
        PlaybackController.shared.skipBackward()
    }
    
    @IBAction func forward(sender: AnyObject?) {
        PlaybackController.shared.skipForward()
    }

}
