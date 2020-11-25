[![Carthage Compatible](https://img.shields.io/badge/Carthage-Compatible-brightgreen.svg)](https://github.com/Carthage/Carthage)
[![SwiftPM Compatible](https://img.shields.io/badge/SwiftPM-Compatible-brightgreen.svg)](https://swift.org/package-manager)
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/WSAudioKit.svg?style=flat)](https://cocoapods.org/pods/WSAudioKit)
[![Swift 5.3](https://img.shields.io/badge/Swift-5.3-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![Platforms iOS](https://img.shields.io/badge/Platforms-iOS-lightgray.svg?style=flat)](https://developer.apple.com/swift/)
[![License MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat)](https://github.com/whitesmith/WSAudioKit/blob/master/LICENSE)

# WSAudioKit

Convenient wrapper around AVFoundation & MediaPlayer.

## Installation

#### CocoaPod:

```ruby
pod 'WSAudioKit'
```

#### Carthage:

```ruby
github "whitesmith/WSAudioKit"
```

## Usage

```
let controller = PlaybackController(
    resourcesDirectory: AudioManager.defaultDirectory,
    defaults: UserDefaults.standard,
    resourceLoaderMode: .system
)
controller.artworkProvider = AudioManager.artworkFetcher
controller.backwardSkipInterval = 30
controller.forwardSkipInterval = 30

NotificationCenter.default.addObserver(self, selector: #selector(self.updateUI), name: UIApplication.willEnterForegroundNotification, object: nil)

NotificationCenter.default.addObserver(self, selector: #selector(self.savePosition), name: UIApplication.didEnterBackgroundNotification, object: nil)

playbackControllerNotificationvDidUpdateElapsedTimeToken = center.addObserver(forName: PlaybackControllerNotification.DidUpdateElapsedTime.name, object: nil, queue: .main) {
...
}

playbackControllerNotificationDidUpdateStatusToken = center.addObserver(forName: PlaybackControllerNotification.DidUpdateStatus.name, object: nil, queue: .main) { [weak self]
...
}

playbackControllerNotificationDidPlayToEndToken = center.addObserver(forName: PlaybackControllerNotification.DidPlayToEnd.name, object: nil, queue: .main) { [weak self] (note) in
...
}
```

## Acknowledgements

This is a modified copy of [sodes-audio](https://github.com/jaredsinclair/sodes-audio-example).

### Sodes-audio-example

An example AVAssetResourceLoaderDelegate implementation. A variation of this will be used in **’sodes**, a podcast app I'm working on.

This repo accompanies a blog post [which can be found here](http://blog.jaredsinclair.com/post/149892449150/avassetresourceloaderdelegate).

You are welcome to use this code as allowed under the generous terms of the MIT License, but **this code is not intended to be used as a re-usable library**. It's highly optimized for the needs of my particular app. I'm sharing it here for the benefit of anyone who's looking for an example of how to write an AVAssetResourceLoaderDelegate implementation.

### What It Does

Contains an example implementation of an AVAssetResourceLoaderDelegate which downloads the requested byte ranges to a "scratch file" of locally-cached byte ranges. It also re-uses previously-downloaded byte ranges from that scratch file to service future requests that overlap the downloaded byte ranges, both during the current app session and in future sessions. This helps limit the number of times the same bytes are downloaded when streaming a podcast episode over more than one app session. Ideally each byte should never be downloaded more than once.

When a request for a byte range is sent to the resource loader delegate, an array of "subrequests" is formed which are either scratch file requests or network requests. Scratch file requests read the data from existing byte ranges in the scratch file which have already been downloaded. Network requests are made for any gaps in the scratch file. The results of network requests are both passed to the AVAssetResourceLoader and written to the scratch file to be re-used later if the need arises.

### Sample App Screenshot

This repository also contains an example application so you can see it in action.

You can see below some basic play controls, as well as a text view that prints out the byte ranges that have been successfully written to the current scratch file. 

Delete and reinstall the app to clear out the scratch file (or change the hard-coded MP3 URL to some other MP3 url and rebuild and run).

<img src="https://raw.githubusercontent.com/jaredsinclair/sodes-audio-example/master/screenshot.png" width="375">

