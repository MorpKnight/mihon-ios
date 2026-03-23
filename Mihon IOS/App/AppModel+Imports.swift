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
                appendDiagnostic(
                    kind: .app,
                    severity: .error,
                    title: "Local Import Failed",
                    message: failure.reason,
                    errorCode: DiagnosticErrorCode.appLocalImportFailed.rawValue,
                    module: "Imports",
                    resolutionHint: "Verify file format and try importing again.",
                    metadata: ["file": failure.fileName]
                )
            }
        } catch {
            appendDiagnostic(
                kind: .app,
                severity: .critical,
                title: "Local Import Failed",
                message: error.localizedDescription,
                errorCode: DiagnosticErrorCode.appLocalImportBatchFailed.rawValue,
                module: "Imports",
                resolutionHint: "Retry with fewer files and verify storage permissions.",
                metadata: [:]
            )
            bootState = .failed("Failed to import local content: \(error.localizedDescription)")
        }
    }

    func importedJobs() -> [ImportJob] {
        importJobsState
    }

    func fileURL(for page: ReaderPage) -> URL? {
        guard let resolved = readerAssetRepository.fileURL(for: page) else { return nil }
        if FileManager.default.fileExists(atPath: resolved.path) {
            return resolved
        }
        guard let assetPath = page.assetPath, assetPath.contains(".partial/") else {
            return resolved
        }

        let normalizedPath = assetPath.replacingOccurrences(of: ".partial/", with: "/")
        if FileManager.default.fileExists(atPath: normalizedPath) {
            return URL(fileURLWithPath: normalizedPath)
        }

        return resolved
    }

    func localImportSummary() -> String {
        importRecords.isEmpty ? "No local titles imported yet." : "\(importRecords.count) local title(s) available."
    }

    func storageSummary() -> String {
        "\(state.library.count) library • \(importRecords.count) imports • \(state.history.count) history"
    }
}
