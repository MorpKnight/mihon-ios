//
//  AppModel+Imports.swift
//  Mihon IOS
//

import Foundation

extension AppModel {
    func importItems(from urls: [URL]) {
        do {
            let result = try importRepository.importItems(from: urls)
            importRecords = result.records
            importJobsState = result.jobs
            for failure in result.failures {
                appendDiagnostic(kind: .app, title: "Local Import Failed", message: failure.reason, metadata: ["file": failure.fileName])
            }
        } catch {
            appendDiagnostic(kind: .app, title: "Local Import Failed", message: error.localizedDescription, metadata: [:])
            bootState = .failed("Failed to import local content: \(error.localizedDescription)")
        }
    }

    func importedJobs() -> [ImportJob] {
        importJobsState
    }

    func fileURL(for page: ReaderPage) -> URL? {
        readerAssetRepository.fileURL(for: page)
    }

    func localImportSummary() -> String {
        importRecords.isEmpty ? "No local titles imported yet." : "\(importRecords.count) local title(s) available."
    }

    func storageSummary() -> String {
        "\(state.library.count) library • \(importRecords.count) imports • \(state.history.count) history"
    }
}

