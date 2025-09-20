//
//  cache.swift
//  wallpapers
//
//  Created by Oleksandr Koreniuk on 08.01.2023.
//

import Foundation
import CoreGraphics

final class ImageCache {
    
    static func cacheExist(id: Int) -> Bool {
        let url = localurl(id: id)
        let exist = FileManager.default.fileExists(atPath: url.path())
        return exist
    }
    
    static func localurl(id: Int) -> URL {
        let folderURLs = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )
        let fileURL = folderURLs[0].appendingPathComponent(String(id) + ".jpeg")
        return fileURL
    }
    
    static func get(id: Int) -> String {
        let url = localurl(id: id)
        if(cacheExist(id: id)) {
            return url.absoluteString
        } else {
            return ""
        }
    }
    
    static func getdata(id: Int) async throws -> Data? {
        let url = localurl(id: id)
        if(cacheExist(id: id)) {
            let session = URLSession.shared
            let (data,_) = try await session.data(from: url)
            return data
        } else {
            return nil
        }
    }
    
    static func set(id: Int, data: Data) {
        let url = localurl(id: id)
        FileManager.default.createFile(atPath: url.path(), contents: data)
    }
    
    static func processExternalUrl(id: Int, url: URL) async throws -> Void {
        if(!cacheExist(id: id)) {
            let session = URLSession.shared
            let (data,_) = try await session.data(from: url)
            set(id: id, data: data)
        }
    }
}


