import Foundation

// MARK: - Upload Job Data (received from Dart)

struct UploadJobData: Codable {
    let jobId: String
    let filePath: String
    let fileSize: Int64
    let title: String
    let initUrl: String
    let completeUrl: String
    let abortUrl: String
    let callbackUrl: String
    let callbackMethod: String
    let initBody: String
    let courseAssetKey: String?
    let callbackBodyTemplate: String
    let createdAt: Int64

    init(from dict: [String: Any]) {
        jobId = dict["jobId"] as? String ?? ""
        filePath = dict["filePath"] as? String ?? ""
        fileSize = dict["fileSize"] as? Int64 ?? 0
        title = dict["title"] as? String ?? "Upload"
        initUrl = dict["initUrl"] as? String ?? ""
        completeUrl = dict["completeUrl"] as? String ?? ""
        abortUrl = dict["abortUrl"] as? String ?? ""
        callbackUrl = dict["callbackUrl"] as? String ?? ""
        callbackMethod = dict["callbackMethod"] as? String ?? "POST"
        initBody = dict["initBody"] as? String ?? "{}"
        courseAssetKey = dict["courseAssetKey"] as? String
        callbackBodyTemplate = dict["callbackBodyTemplate"] as? String ?? "{}"
        createdAt = dict["createdAt"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
    }

    func toDict() -> [String: Any] {
        var d: [String: Any] = [
            "jobId": jobId,
            "filePath": filePath,
            "fileSize": fileSize,
            "title": title,
            "initUrl": initUrl,
            "completeUrl": completeUrl,
            "abortUrl": abortUrl,
            "callbackUrl": callbackUrl,
            "callbackMethod": callbackMethod,
            "initBody": initBody,
            "callbackBodyTemplate": callbackBodyTemplate,
            "createdAt": createdAt,
        ]
        if let key = courseAssetKey { d["courseAssetKey"] = key }
        return d
    }
}

// MARK: - Init Response (parsed from backend)

struct InitResult {
    let isMultipart: Bool
    let uploadUrl: String?
    var fileUrl: String
    let key: String?
    let s3UploadId: String?
    var parts: [PartUrl]
}

struct PartUrl {
    let partNumber: Int
    var uploadUrl: String
}

// MARK: - Terminal Result (persisted for Dart to poll)

struct UploadResult: Codable {
    let jobId: String
    let status: String // "completed" or "failed"
    let fileUrl: String?
    let error: String?
    let completedAt: Int64

    init(jobId: String, status: String, fileUrl: String?, error: String?) {
        self.jobId = jobId
        self.status = status
        self.fileUrl = fileUrl
        self.error = error
        self.completedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    func toDict() -> [String: Any] {
        var d: [String: Any] = [
            "jobId": jobId,
            "status": status,
            "completedAt": completedAt,
        ]
        if let url = fileUrl { d["fileUrl"] = url }
        if let err = error { d["error"] = err }
        return d
    }
}

// MARK: - Init Parser

struct InitParser {
    static func parse(_ body: String, courseAssetKey: String?) -> InitResult? {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var d: [String: Any] = (root["data"] as? [String: Any]) ?? root

        // Course endpoints nest: data.data.{thumbnail|video}
        if let nested = d["data"] as? [String: Any],
           (nested["thumbnail"] != nil || nested["video"] != nil) {
            let sectionKey = courseAssetKey ?? "thumbnail"
            if let section = nested[sectionKey] as? [String: Any] {
                d = section
            }
        }

        let isMultipart = d["isMultipart"] as? Bool ?? false
        let uploadUrl = d["uploadUrl"] as? String
        let fileUrl = d["fileUrl"] as? String ?? ""
        let key = d["key"] as? String
        let s3UploadId = isMultipart ? (d["uploadId"] as? String) : nil

        var parts: [PartUrl] = []
        if let partsArr = d["parts"] as? [[String: Any]] {
            for p in partsArr {
                if let num = p["partNumber"] as? Int {
                    parts.append(PartUrl(
                        partNumber: num,
                        uploadUrl: p["uploadUrl"] as? String ?? ""
                    ))
                }
            }
        }

        return InitResult(
            isMultipart: isMultipart,
            uploadUrl: uploadUrl,
            fileUrl: fileUrl,
            key: key,
            s3UploadId: s3UploadId,
            parts: parts
        )
    }

    static func extractFileUrl(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let dataObj = json["data"] as? [String: Any],
           let url = dataObj["fileUrl"] as? String, !url.isEmpty {
            return url
        }
        return json["fileUrl"] as? String
    }
}
