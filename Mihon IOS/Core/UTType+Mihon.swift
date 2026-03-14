//
//  UTType+Mihon.swift
//  Mihon IOS
//

import UniformTypeIdentifiers

extension UTType {
    static var mihonCBZ: UTType {
        UTType(filenameExtension: "cbz") ?? .zip
    }

    static var mihonEPUB: UTType {
        UTType(filenameExtension: "epub") ?? .data
    }
}
