//
//  URLRequest.swift
//  SodesAudio
//
//  Created by Jared Sinclair on 8/19/16.
//
//

import Foundation
import AVFoundation

extension AVAssetResourceLoadingDataRequest {

    var byteRange: ByteRange {
        let lowerBound = requestedOffset
        let upperBound = (lowerBound + Int64(requestedLength) - 1)
        return (lowerBound..<upperBound)
    }

}

extension URLRequest {

    /// Convenience method
    var byteRange: ByteRange? {
        if let value = allHTTPHeaderFields?["Range"] {
            if let prefixRange = value.range(of: "bytes=") {
                let rangeString = String(value[prefixRange.upperBound...])
                let comps = rangeString.components(separatedBy: "-")
                let ints = comps.compactMap{Int64($0)}
                if ints.count == 2 {
                    return (ints[0]..<(ints[1]+1))
                }
            }
        }
        return nil
    }

    /// Convenience method
    mutating func setByteRangeHeader(for range: ByteRange) {
        let rangeHeader = "bytes=\(range.lowerBound)-\(range.lastValidIndex)"
        setValue(rangeHeader, forHTTPHeaderField: "Range")
    }

    /// Convenience method for creating a byte range network request.
    static func dataRequest(from url: URL, for range: ByteRange) -> URLRequest {
        var request = URLRequest(url: url)
        request.setByteRangeHeader(for: range)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

}
