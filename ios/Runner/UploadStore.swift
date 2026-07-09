import Foundation

/// File-based persistence for the iOS native upload pipeline.
/// Mirrors the Android `UploadStore` pattern.
///
/// Directories:
///   Library/Caches/eduverse_upload/pending/<jobId>.json — UploadJobData
///   Library/Caches/eduverse_upload/results/<jobId>.json  — UploadResult
class UploadStore {
    private let pendingDir: URL
    private let resultsDir: URL
    private let fileManager = FileManager.default

    init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("eduverse_upload", isDirectory: true)
        pendingDir = base.appendingPathComponent("pending", isDirectory: true)
        resultsDir = base.appendingPathComponent("results", isDirectory: true)
        try? fileManager.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: resultsDir, withIntermediateDirectories: true)
    }

    // MARK: - Pending jobs

    func savePending(_ job: UploadJobData) {
        let url = pendingDir.appendingPathComponent("\(job.jobId).json")
        if let data = try? JSONSerialization.data(withJSONObject: job.toDict()) {
            try? data.write(to: url)
        }
    }

    func loadPending(_ jobId: String) -> UploadJobData? {
        let url = pendingDir.appendingPathComponent("\(jobId).json")
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return UploadJobData(from: dict)
    }

    func deletePending(_ jobId: String) {
        let url = pendingDir.appendingPathComponent("\(jobId).json")
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Results

    func saveResult(_ result: UploadResult) {
        let url = resultsDir.appendingPathComponent("\(result.jobId).json")
        if let data = try? JSONSerialization.data(withJSONObject: result.toDict()) {
            try? data.write(to: url)
        }
    }

    func allResults() -> [[String: Any]] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: resultsDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return dict
        }
    }

    func clearResult(_ jobId: String) {
        let url = resultsDir.appendingPathComponent("\(jobId).json")
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Counts

    var pendingCount: Int {
        (try? fileManager.contentsOfDirectory(at: pendingDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.count) ?? 0
    }
}
