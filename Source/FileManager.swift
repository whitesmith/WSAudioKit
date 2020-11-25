//
//  FileManagement.swift
//  SodesFoundation
//
//  Created by Jared Sinclair on 7/9/16.
//
//

import Foundation

extension FileManager {
    
    func cachesDirectory() -> URL? {
        let directories = urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )
        return directories.first
    }

    func documentsDirectory() -> URL? {
        let directories = urls(
            for: .documentDirectory,
            in: .userDomainMask
        )
        return directories.first
    }

}
