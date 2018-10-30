//
//  PlaybackController.swift
//  SodesAudio
//
//  Created by Jared Sinclair on 7/10/16.
//
//

import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import SodesFoundation

/// Used to obtain album art.
public protocol ArtworkProvider: class {
    func getArtwork(for url: URL, completion: @escaping (UIImage?) -> Void)
}

/// Used to obtain a local file URL for fully-cached audio files.
public protocol WholeFileCache: class {
    func fileUrlForWholeFile(for resourceUrl: URL) -> URL?
}

/// The various notifications posted by PlaybackController.
public enum PlaybackControllerNotification: String {
    
    /// Update Notifications
    case DidUpdateElapsedTime = "PlaybackControllerDidUpdateElapsedTimeNotification"
    case DidUpdateDuration = "PlaybackControllerDidUpdateDurationNotification"
    case DidUpdateLoadedTimeRanges = "PlaybackControllerDidUpdateLoadedTimeRangesNotification"
    case DidUpdateLoadedByteRanges = "PlaybackControllerDidUpdateLoadedByteRangesNotification"
    
    /// Change Notifications
    case WillChangeSource = "PlaybackControllerWillChangeSourceNotification"
    case DidChangeSource = "PlaybackControllerDidChangeSourceNotification"
    case DidChangeBackwardSkipInterval = "PlaybackControllerDidChangeBackwardSkipIntervalNotification"
    case DidChangeForwardSkipInterval = "PlaybackControllerDidChangeForwardSkipIntervalNotification"
    case DidChangePreferredRate = "PlaybackControllerDidChangePreferredRateNotification"
    
    /// Playback Status Notifications
    case DidUpdateStatus = "PlaybackControllerDidUpdateStatusNotification"
    case DidPlayToEnd = "PlaybackControllerDidPlayToEndNotification"
    
    /// User Info Keys
    public static let SourceKey = "source"
    public static let ByteRangesKey = "byteRanges"
    
    /// Convenience
    public var name: Notification.Name {
        return Notification.Name(rawValue)
    }
    
}

fileprivate enum PlaybackMode: String {
    case fromResourceLoader
    case fromRemoteUrl
    case fromFileUrl
}

public enum ResourceLoaderMode: String {
    case automaticDetection
    case system
    case sodes
}

/// Manages playback of audio from a remote or local audio file.
public class PlaybackController: NSObject {
    
    // MARK: Data Types
    
    /// The various states the controller can be in.
    public enum Status {
        
        /// Has no current item.
        case idle
        
        /// Preparing the current item.
        case preparing(playWhenReady: Bool, startTime: TimeInterval)
        
        /// Audio is playing.
        case playing
        
        /// Audio data is being buffered, playback is temporarily suspended.
        case buffering
        
        /// Playback is paused.
        case paused(manually: Bool)
        
        /// Playback encountered an unrecoverable error.
        case error(Error?)
        
    }
    
    // MARK: Singleton (Optional)
    
    /// The singleton instance. Optional.
    public static let shared = PlaybackController(
        resourcesDirectory: defaultDirectory,
        defaults: UserDefaults.standard
    )
    
    // MARK: Delegates & Data Sources
    
    /// Provides album art for the receiver.
    public weak var artworkProvider: ArtworkProvider? {
        didSet { updateArtwork() }
    }
    
    /// Provides access to locally-cached audio files.
    public weak var wholeFileCache: WholeFileCache?
    
    // MARK: Public Properties (Read/Write)
    
    /// The preferred playback rate.
    public var preferredRate: Double {
        get { return _preferredRate }
        set {
            let adjustedValue = (newValue != 0) ? min(32.0,max(newValue, 1.0/32.0)) : 1.0
            _preferredRate = adjustedValue
            if player.isPlaying { player.rate = Float(adjustedValue) }
            updateNowPlayingInfo()
            post(.DidChangePreferredRate)
        }
    }
    
    /// A convenience typealias.
    public typealias Seconds = Int
    
    /// The preferred backward skip interval (in seconds).
    public var backwardSkipInterval: Seconds = 15  {
        didSet {
            let center = MPRemoteCommandCenter.shared()
            center.skipBackwardCommand.preferredIntervals = [NSNumber(value: backwardSkipInterval)]
            post(.DidChangeBackwardSkipInterval)
        }
    }
    
    /// The preferred forward skip interval (in seconds).
    public var forwardSkipInterval: Seconds = 30 {
        didSet {
            let center = MPRemoteCommandCenter.shared()
            center.skipForwardCommand.preferredIntervals = [NSNumber(value: forwardSkipInterval)]
            post(.DidChangeForwardSkipInterval)
        }
    }
    
    // MARK: Public Properties (Readonly)
    
    /// The current status. When changed, a notification is posted.
    public fileprivate(set) var status: Status = .idle {
        didSet {
            SodesLog(status)
            updateNowPlayingInfo()
            post(.DidUpdateStatus)
        }
    }
    
    /// The current source. When changed, a notification is posted.
    public fileprivate(set) var currentSource: PlaybackSource? {
        willSet {
            post(.WillChangeSource)
        }
        didSet {
            currentArtwork = nil
            updateArtwork()
            updateNowPlayingInfo()
            post(.DidChangeSource)
        }
    }
    
    /// The current elapsed time. When updated, a notification is posted.
    public fileprivate(set) var elapsedTime: TimeInterval = 0 {
        didSet { post(.DidUpdateElapsedTime) }
    }
    
    /// The current estimated duration. When updated, a notification is posted.
    public fileprivate(set) var duration: TimeInterval?  {
        didSet {
            updateNowPlayingInfo()
            post(.DidUpdateDuration)
        }
    }
    
    /// The loaded (playable) time ranges. When updated, a notification is posted.
    public fileprivate(set) var loadedTimeRanges: [CMTimeRange]? {
        didSet { post(.DidUpdateLoadedTimeRanges) }
    }
    
    // MARK: File Private Properties (Immutable)
    
    /// The default directory for scratch file caching.
    fileprivate static let defaultDirectory: URL = {
        let caches = FileManager.default.cachesDirectory()!
        return caches.appendingPathComponent(
            "PlaybackController",
            isDirectory: true
        )
    }()
    
    /// The lone AVPlayer.
    fileprivate let player: AVPlayer
    
    /// The lone resource loading delegate.
    fileprivate let resourceLoaderDelegate: ResourceLoaderDelegate
    
    /// The preferred time interval for elapsed time callbacks.
    fileprivate let periodicTimeInterval = TimeInterval(1.0/30.0).asCMTime
    
    // MARK: File Private Properties (Mutable)
    
    /// Indicates whether the player is being interrupted by system audio.
    fileprivate var isInterrupted = false
    
    /// The last time a new source began to be prepped (for debugging).
    fileprivate var lastPrepTime: Date?
    
    /// Indicates whether playback has begun for the current source (for debugging).
    fileprivate var hasPlayedYet = false
    
    /// The current artwork, if any.
    fileprivate var currentArtwork: UIImage? = nil {
        didSet { updateNowPlayingInfo() }
    }
    
    /// The preferred playback rate.
    fileprivate var _preferredRate: Double = 1.0
    
    /// An observer for observing the player's elapsed time.
    fileprivate var currentPlayerItemObserver: NSObjectProtocol?
    
    /// The current AVPlayerItem.
    fileprivate var currentPlayerItem: AVPlayerItem? {
        didSet { didSetPlayerItem(oldValue: oldValue) }
    }
    
    /// The current playback mode.
    fileprivate var playbackMode: PlaybackMode = .fromRemoteUrl

    /// The current resource loader mode.
    public fileprivate(set) var resourceLoaderMode: ResourceLoaderMode = .automaticDetection
    
    // MARK: Init/Deinit
    
    /// Designated initializer.
    public init(resourcesDirectory: URL, defaults: UserDefaults, customLoadingScheme: String = "playbackcontroller", resourceLoaderMode: ResourceLoaderMode = .automaticDetection) {
        player = AVPlayer()

        // Discussion (DTS 696294259, rdar://42881405)
        // "Volume control is disabled when connected to Apple TV using AirPlay"
        // Workaroung: set the “allowsExternalPlayback” property of your AVQueuePlayer to ‘false’.
        //   This works by disallowing the routing of video playback to AirPlay,
        //   and (as a side-effect) allows the pure audio playback.
        player.allowsExternalPlayback = false

        self.resourceLoaderMode = resourceLoaderMode
        self.resourceLoaderDelegate = ResourceLoaderDelegate(
            customLoadingScheme: customLoadingScheme,
            resourcesDirectory: resourcesDirectory,
            defaults: defaults
        )
        
        super.init()

        let audioSession = AVAudioSession.sharedInstance()

        if #available(iOS 11.0, *) {
            do {
                try audioSession.setCategory(
                    AVAudioSessionCategoryPlayback,
                    mode: AVAudioSessionModeDefault,
                    routeSharingPolicy: .longForm
                )
                try audioSession.setActive(true)
            }
            catch {
                print(error)
            }
        } else {
            // Fallback on earlier versions
            _ = try! audioSession.setCategory(AVAudioSessionCategoryPlayback)
            _ = try! audioSession.setMode(AVAudioSessionModeSpokenAudio)
        }

        resourceLoaderDelegate.delegate = self
        registerCommandHandlers()
        
        player.addObserver(self, forKeyPath: "timeControlStatus", options: .new, context: &PlaybackControllerContext)
        
        player.addPeriodicTimeObserver(forInterval: periodicTimeInterval, queue: DispatchQueue.main) { [weak self] (time) in
            DispatchQueue.main.async {
                guard let this = self else {return}
                if let elapsedTime = time.asTimeInterval {
                    this.elapsedTime = elapsedTime
                    if !this.hasPlayedYet && elapsedTime > 0.5 {
                        this.hasPlayedYet = true
                        if let lastPrepTime = this.lastPrepTime {
                            let delay = Date().timeIntervalSince(lastPrepTime)
                            SodesLog("Latency was: \(delay) seconds")
                        }
                    }
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVAudioSessionInterruption,
            object: nil,
            queue: .main,
            using: handleAudioSessionInterruptionNotification
        )

        NotificationCenter.default.addObserver(
            forName: .AVAudioSessionRouteChange,
            object: nil,
            queue: .main,
            using: handleAudioSessionRouteChangeNotification
        )
    }

    deinit {
        SodesLog("Deinitialized")
    }
    
    // MARK: Public Methods
    
    /// Prepares a new playback source.
    public func prepare(_ source: PlaybackSource, startTime: TimeInterval = 0, playWhenReady: Bool = false) {
        
        if case .playing = status, (startTime > 0 || !playWhenReady) {
            // If the player is configured to disable automatic waiting and the
            // player is already playing, then unless we pause the player here 
            // the new source will begin playback automatically. This is even
            // worse when the requested start time is greater than zero because
            // playback will trigger the timeControlStatus KVO update, blowing
            // away our .preparing(...) status.
            pause(manually: true)
        }
        
        lastPrepTime = Date()
        hasPlayedYet = false
        currentPlayerItem = nil
        currentSource = source
        status = .preparing(playWhenReady: playWhenReady, startTime: startTime)
        
        let asset: AVURLAsset
        
        if let fileUrl = wholeFileCache?.fileUrlForWholeFile(for: source.remoteUrl) {
            // Files should play without waiting.
            if #available(iOS 10.0, *) {
                player.automaticallyWaitsToMinimizeStalling = false
            }
            asset = AVURLAsset(url: fileUrl)
            playbackMode = .fromFileUrl
        }
        else if let delegatedAsset = resourceLoaderDelegate.prepareAsset(for: source.remoteUrl), resourceLoaderMode == .automaticDetection || resourceLoaderMode == .sodes {
            // Enable automatic waiting when streaming over the network.
            if #available(iOS 10.0, *) {
                // BUG in iOS 9 and 10: it occurs while seeking a specific position of the current source using a streaming
                //audio file where the `AppendBufferReferenceSubBlock` method from `com.apple.coremedia.audiomentor`
                //does an endless loop. Next, if you call [`timeControlStatus`](https://developer.apple.com/documentation/avfoundation/avplayer/1643485-timecontrolstatus?preferredLanguage=occ) from AVPlayer when `automaticallyWaitsToMinimizeStalling`
                // is true, then a deadlock will happen because the it is waiting for the buffer that doesn't finish.
                //  - https://gist.github.com/ricardopereira/a789c9257e4c03d56fce9cf9e3c8c74f
                //  - https://gist.github.com/ricardopereira/b895cab8b75c78df2e261140c487bb57
                player.automaticallyWaitsToMinimizeStalling = ProcessInfo.processInfo.operatingSystemVersion.majorVersion > 10
            }
            asset = delegatedAsset
            playbackMode = .fromResourceLoader
        }
        else {
            // Enable automatic waiting when streaming over the network.
            if #available(iOS 10.0, *) {
                player.automaticallyWaitsToMinimizeStalling = true
            }
            asset = AVURLAsset(url: source.remoteUrl)
            playbackMode = .fromRemoteUrl
        }
        
        currentPlayerItem = AVPlayerItem(asset: asset)

        player.replaceCurrentItem(with: currentPlayerItem!)
    }
    
    /// Removes the current source.s
    public func removeCurrentSource() {
        currentSource = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentPlayerItem = nil
        loadedTimeRanges = nil
        status = .idle
        duration = nil
        elapsedTime = 0
        lastPrepTime = nil
        hasPlayedYet = false
        currentArtwork = nil
    }

    public func reasonForWaitingToPlay() -> String? {
        if #available(iOS 10.0, *) {
            return player.reasonForWaitingToPlay
        }
        else {
            return nil
        }
    }
    
    /// Resumes playback if possible.
    public func play() {
        guard !isInterrupted else {return}
        switch status {
        case .paused, .preparing:
            assert((currentPlayerItem?.status ?? .unknown) == .readyToPlay)
            status = .playing
            // Play immediately because... it seems to perform well even on my
            // shitty-ass U-Verse internet.
            if #available(iOS 10.0, *) {
                player.playImmediately(atRate: Float(preferredRate))
            } else {
                player.play()
            }
        case .idle, .playing, .buffering, .error:
            break
        }
    }

    /// Pauses playback if possible.
    public func pause(manually: Bool) {
        switch status {
        case .preparing(let playWhenReady, let startTime):
            if playWhenReady {
                status = .preparing(playWhenReady: false, startTime: startTime)
            }
        case .playing, .buffering:
            status = .paused(manually: manually)
            player.pause()
        case .idle, .paused, .error:
            break
        }
    }
    
    /// Toggles play/pause
    public func togglePlayPause() {
        switch status {
        case .playing:
            pause(manually: true)
        case .paused:
            play()
        case .idle, .buffering, .preparing(_,_), .error(_):
            break
        }
    }
    
    /// Seeks to a given time.
    public func seekToTime(_ time: TimeInterval, accurately: Bool = true, completion: @escaping () -> Void = {}) {
        guard player.currentItem != nil else {return}
        if accurately {
            player.seek(
                to: time.asCMTime,
                toleranceBefore: kCMTimeZero,
                toleranceAfter: kCMTimeZero,
                completionHandler: { [weak self] (finished) in
                    if finished {
                        self?.updateNowPlayingInfo()
                        completion()
                    }
                }
            )
        } else {
            player.seek(to: time.asCMTime) { [weak self] (finished) in
                if finished {
                    self?.updateNowPlayingInfo()
                }
            }
        }
    }
    
    /// Skips forward by the preferred interval.
    public func skipForward() {
        let newTime = elapsedTime + TimeInterval(forwardSkipInterval)
        seekToTime(newTime, accurately: true)
    }
    
    /// Skips backward by the preferred interval.
    public func skipBackward() {
        let newTime = elapsedTime - TimeInterval(backwardSkipInterval)
        seekToTime(newTime, accurately: false)
    }
    
}

// MARK: KVO

fileprivate var PlaybackControllerContext = "PlaybackControllerContext"

extension PlaybackController {
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        guard let keyPath = keyPath else {return}
        guard let object = object as AnyObject? else {return}
        
        DispatchQueue.main.async {
            if self.player === object {
                if keyPath == "timeControlStatus" {
                    self.playerDidChangeTimeControlStatus()
                }
            }
            else if let item = object as? AVPlayerItem {
                guard item === self.currentPlayerItem else {return}
                if keyPath == "status" {
                    self.playerItemDidChangeStatus(item)
                }
                else if keyPath == "duration" {
                    if item.duration.isNumeric {
                        self.duration = TimeInterval(CMTimeGetSeconds(item.duration))
                    } else {
                        self.duration = nil
                    }
                }
                else if keyPath == "loadedTimeRanges" {
                    self.loadedTimeRanges = item.loadedTimeRanges.map{$0.timeRangeValue}
                }
            }
        }
    }
    
}

// MARK: Convenience

fileprivate extension PlaybackController {
    
    fileprivate func post(_ notification: PlaybackControllerNotification, userInfo: [String: Any]? = nil) {
        let note = Notification(name: notification.name, object: self, userInfo: userInfo)
        NotificationCenter.default.post(note)
    }
    
    fileprivate func updateNowPlayingInfo() {
        let info = currentSource?.nowPlayingInfo(
            image: currentArtwork,
            duration: duration,
            elapsedPlaybackTime: elapsedTime,
            rate: Double(player.rate)
        )
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    fileprivate func updateArtwork() {
        if let image = currentSource?.artworkImage {
            currentArtwork = image
        }
        if let url = currentSource?.artworkUrl {
            artworkProvider?.getArtwork(for: url) { [weak self] (image) in
                self?.currentArtwork = image ?? self?.currentSource?.artworkImage
            }
        }
    }
    
    fileprivate func didSetPlayerItem(oldValue: AVPlayerItem?) {
        let keyPaths = ["status", "duration", "loadedTimeRanges"]
        oldValue?.remove(observer: self, for: keyPaths, context: &PlaybackControllerContext)
        currentPlayerItem?.add(observer: self, for: keyPaths, context: &PlaybackControllerContext)
        currentPlayerItem?.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmTimeDomain
        if let observer = currentPlayerItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let item = currentPlayerItem {
            currentPlayerItemObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main,
                using: { [weak self] (note) in
                    guard let this = self else {return}
                    guard let object = note.object as AnyObject? else {return}
                    guard object === this.currentPlayerItem else {return}
                    let sourceOrNil = this.currentSource
                    this.removeCurrentSource()
                    if let source = sourceOrNil {
                        let userInfo: [String: Any] = [
                            PlaybackControllerNotification.SourceKey: source
                        ]
                        this.post(.DidPlayToEnd, userInfo: userInfo)
                    }
            })
        }
    }
    
    fileprivate func handleAudioSessionInterruptionNotification(note: Notification) {
        SodesLog(note)
        
        guard let typeNumber = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber else {return}
        guard let type = AVAudioSessionInterruptionType(rawValue: typeNumber.uintValue) else {return}
        
        switch type {

        case .began:
            if case .paused(let manually) = status, manually == true {
                break
            }
            else {
                isInterrupted = true
            }

        case .ended:
            isInterrupted = false
            let optionNumber = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber
            if let number = optionNumber {
                let options = AVAudioSessionInterruptionOptions(rawValue: number.uintValue)
                let shouldResume = options.contains(.shouldResume)
                switch status {
                case .playing:
                    if shouldResume {
                        play()
                    } else {
                        pause(manually: false)
                    }
                case .paused(let manually):
                    if manually {
                        // Do not resume! The user manually paused.
                    } else {
                        play()
                    }
                case .preparing(_, let startTime):
                    status = .preparing(playWhenReady:shouldResume, startTime: startTime)
                case .idle, .error(_), .buffering:
                    break
                }
            } else {
                switch status {
                case .playing:
                    play()
                case .paused(let manually):
                    if manually {
                        // Do not resume! The user manually paused.
                    } else {
                        play()
                    }
                case .idle, .buffering, .preparing(_,_), .error(_):
                    break
                }
            }
        }
    }

    fileprivate func handleAudioSessionRouteChangeNotification(notification: Notification) {
        SodesLog(notification)

        var headphonesConnected = false
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSessionRouteChangeReason(rawValue: reasonValue),
            let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
                return
        }

        switch reason {
        case .newDeviceAvailable:
            let session = AVAudioSession.sharedInstance()
            for output in session.currentRoute.outputs where output.portType == AVAudioSessionPortHeadphones {
                headphonesConnected = true
                break
            }
        case .oldDeviceUnavailable:
            if let previousRoute =
                userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                for output in previousRoute.outputs where output.portType == AVAudioSessionPortHeadphones {
                    headphonesConnected = false
                    break
                }
            }
        default: ()
        }

        SodesLog("Headphones: \(headphonesConnected)")
        SodesLog(reason)
        SodesLog(previousRoute)
    }
    
    fileprivate func playerDidChangeTimeControlStatus() {
        if #available(iOS 10.0, *) {
            switch player.timeControlStatus {
            case .paused:
                switch status {
                case .paused(_), .idle, .error(_), .preparing(_,_):
                    break
                case .playing, .buffering:
                    status = .paused(manually: false)
                }
            case .playing:
                status = .playing
            case .waitingToPlayAtSpecifiedRate:
                switch status {
                case .idle, .error(_), .preparing(_,_):
                    break
                case .paused, .playing, .buffering:
                    status = .buffering
                }
            }
        } else {
            // Discussion:
            //  - `rate` is NOT the way to check whether a video is playing (it could stalled). From documentation of rate: "Indicates the desired rate of playback; 0.0 means "paused", 1.0 indicates a desire to play at the natural rate of the current item."
            // Reference https://stackoverflow.com/questions/5655864/check-play-state-of-avplayer
            if player.rate != 0 && player.error == nil {
                // Playing
                status = .playing
            }
            else {
                // Paused
                switch status {
                case .paused(_), .idle, .error(_), .preparing(_,_):
                    break
                case .playing, .buffering:
                    status = .paused(manually: false)
                }
            }
        }
        updateNowPlayingInfo()
    }

    fileprivate func playerItemDidChangeStatus(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            if case .preparing(let shouldPlay, let startTime) = status {
                if startTime > 0 {
                    seekToTime(startTime, accurately: true) { [weak self] in
                        guard let this = self else {return}
                        if shouldPlay {
                            this.play()
                        } else {
                            this.status = .paused(manually: true)
                        }
                    }
                }
                else if shouldPlay {
                    play()
                }
                else {
                    status = .paused(manually: true)
                }
            }
        case .failed:
            SodesLog("Item status failed: \(item.error?.localizedDescription ?? "unknown error")")
            status = .error(item.error)
        case .unknown:
            SodesLog("Item status unknown")
            status = .error(nil)
        }
    }
    
}

// MARK: ResourceLoaderDelegateDelegate

extension PlaybackController: ResourceLoaderDelegateDelegate {
    
    func resourceLoaderDelegate(_ delegate: ResourceLoaderDelegate, didEncounter error: Error?) {
        if let error = error as? SodesAudioError {
            switch error {
            case .byteRangeAccessNotSupported(_):
                fatalError("Examine which feeds don't support byte ranges, and why.")
            case .unknown:
                // For now there's no need to panic. This method is most likely
                // to be called before the error mode reaches the AVPlayerItem.
                // We will respond to the error via the KVO response to that.
                // Furthermore, it is possible that `delegate` is responding to
                // a delayed error from a request associated with an asset that
                // is no longer the current asset.
                break
            }
        } else {
            // For now there's no need to panic. This method is most likely to be
            // called before the error mode reaches the AVPlayerItem. We will
            // respond to the error via the KVO response to that.
            // Furthermore, it is possible that `delegate` is responding to a
            // delayed error from a request associated with an asset that is no
            // longer the current asset.
        }
    }
    
    func resourceLoaderDelegate(_ delegate: ResourceLoaderDelegate, didUpdateLoadedByteRanges ranges: [ByteRange]) {
        onMainQueue {
            let info: [String: Any] = [PlaybackControllerNotification.ByteRangesKey: ranges]
            self.post(.DidUpdateLoadedByteRanges, userInfo: info)
        }
    }
    
}

// MARK: Remote Commands

fileprivate extension PlaybackController {
    
    func registerCommandHandlers() {
        let center = MPRemoteCommandCenter.shared()
        
        // Playback Commands
        center.playCommand.addTarget(handler: handlePlayCommand)
        center.pauseCommand.addTarget(handler: handlePauseCommand)
        center.stopCommand.isEnabled = false
        center.togglePlayPauseCommand.addTarget(handler: handleTogglePlayPauseCommand)
        
        // Changing Tracks
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        
        // Navigating a Track's Contents
        center.changePlaybackRateCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.skipBackwardCommand.addTarget(handler: handleSkipBackwardCommand)
        center.skipForwardCommand.addTarget(handler: handleSkipForwardCommand)
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: backwardSkipInterval)]
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: forwardSkipInterval)]
        
        // Other
        center.ratingCommand.isEnabled = false
        center.likeCommand.isEnabled = false
        center.dislikeCommand.isEnabled = false
        center.bookmarkCommand.isEnabled = false
    }
    
    func handlePlayCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        switch status {
        case .playing:
            return .success
        case .paused:
            play()
            return .success
        case .idle, .buffering, .preparing(_,_), .error(_):
            return .noActionableNowPlayingItem
        }
    }
    
    func handlePauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        switch status {
        case .playing:
            pause(manually: true)
            return .success
        case .paused(_):
            status = .paused(manually: true)
            return .success
        case .idle, .buffering, .preparing(_,_), .error(_):
            return .noActionableNowPlayingItem
        }
    }
    
    func handleTogglePlayPauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        switch status {
        case .playing:
            return handlePauseCommand(event)
        case .paused:
            return handlePlayCommand(event)
        case .idle, .buffering, .preparing(_,_), .error(_):
            return .noActionableNowPlayingItem
        }
    }
    
    func handleSkipBackwardCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        switch status {
        case .playing, .paused, .buffering:
            skipBackward()
            return .success
        case .idle, .preparing(_,_), .error(_):
            return .noActionableNowPlayingItem
        }
    }
    
    func handleSkipForwardCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        switch status {
        case .playing, .paused, .buffering:
            skipForward()
            return .success
        case .idle, .preparing(_,_), .error(_):
            return .noActionableNowPlayingItem
        }
    }
    
}

// MARK: DispatchTime Convenience

fileprivate extension DispatchTime {
    
    static func fromNow(_ seconds: TimeInterval) -> DispatchTime {
        return DispatchTime.now() + Double(Int64(seconds * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
    }
    
}
