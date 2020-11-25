Pod::Spec.new do |s|
  s.name = "WSAudioKit"
  s.version = "1.1.0"
  s.summary = "Convenient wrapper around AVFoundation & MediaPlayer"
  s.homepage = "https://github.com/whitesmith/WSAudioKit"
  s.license = 'MIT'
  s.author = { "Ricardo Pereira" => "ricardopereira@whitesmith.co" }
  s.source = { :git => "https://github.com/whitesmith/WSAudioKit.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/whitesmithco'
  s.platform     = :ios, '11.0'
  s.requires_arc = true
  s.swift_version = '5.3'
  s.source_files = 'Source/**/*.{h,swift}'
  s.frameworks = 'UIKit'
end
