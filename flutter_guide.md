# Flutter S3 Video Upload Implementation Planner

Based on `test.html` — Eduverse upload tester (web)

---

## 1. Architecture Overview

```
Flutter App
  │
  ├── 1. InitUpload (POST /upload-endpoint)
  │     └── Backend returns: { isMultipart, uploadUrl, fileUrl, parts[], uploadId, key }
  │
  ├── 2. Upload Payload
  │     ├── Single PUT (< 15MB) → direct PUT to uploadUrl
  │     └── Multipart (≥ 15MB)  → PUT each part.uploadUrl, collect ETags
  │
  └── 3. Complete Multipart (POST /complete-endpoint)
        └── Body: { key, uploadId, parts: [{ partNumber, eTag }] }
```

---

## 2. Dependencies (pubspec.yaml)

| Package | Purpose |
|---|---|
| `http` or `dio` | HTTP requests (Dio recommended for upload progress) |
| `file_picker` | File selection |
| `path` | File name/path utilities |
| `mime` | MIME type detection |

---

## 3. Constants (matching backend)

```dart
const int chunkSize = 5 * 1024 * 1024; // 5 MB
const int multipartThreshold = 15 * 1024 * 1024; // 15 MB
```

---

## 4. Data Models

### 4.1 Init Upload Response

```dart
class InitUploadResponse {
  final bool isMultipart;
  final String? uploadUrl;       // single PUT only
  final String? fileUrl;         // final file URL
  final String? uploadId;        // multipart only
  final String? key;             // multipart only (S3 key)
  final List<PartInfo>? parts;   // multipart only

  factory InitUploadResponse.fromJson(Map<String, dynamic> json);
}

class PartInfo {
  final int partNumber;
  final String uploadUrl; // presigned URL for this part

  factory PartInfo.fromJson(Map<String, dynamic> json);
}
```

### 4.2 Complete Multipart Request

```dart
class CompleteMultipartRequest {
  final String key;
  final String uploadId;
  final List<PartETag> parts;

  Map<String, dynamic> toJson();
}

class PartETag {
  final int partNumber;
  final String eTag;

  Map<String, dynamic> toJson();
}
```

---

## 5. Service Layer — `S3UploadService`

### 5.1 Initiate Upload

```dart
Future<InitUploadResponse> initiateUpload({
  required String baseUrl,
  required String token,
  required String uploadEndpoint,
  required String fileName,
  required String contentType,
  required int fileSize,
});
```

- `POST $baseUrl$uploadEndpoint`
- Headers: `Content-Type: application/json`, `Authorization: Bearer $token`
- Body: `{ videoFilename, videoContentType, videoFileSize }`
- Returns parsed `InitUploadResponse`

### 5.2 Single PUT Upload

```dart
Future<String> singlePutUpload({
  required String uploadUrl,
  required File file,
  required String contentType,
  required void Function(int progress) onProgress,
  CancelToken? cancelToken,
});
```

- `PUT $uploadUrl` with file bytes as body
- Header: `Content-Type: $contentType`
- Returns `fileUrl`

### 5.3 Multipart Upload

```dart
Future<List<PartETag>> uploadParts({
  required List<PartInfo> parts,
  required File file,
  required String contentType,
  required void Function(int partNumber, double progress) onPartProgress,
  required void Function(int completed, int total) onOverallProgress,
  CancelToken? cancelToken,
});
```

- For each part (in sequence or parallel with limit):
  1. Slice file: `start = (partNumber - 1) * chunkSize`, `end = min(start + chunkSize, fileSize)`
  2. `PUT $part.uploadUrl` with chunk bytes
  3. Header: `Content-Type`, `Content-Length`
  4. Extract `ETag` from response headers
  5. Collect into `List<PartETag>`

### 5.4 Complete Multipart

```dart
Future<String> completeMultipartUpload({
  required String baseUrl,
  required String token,
  required String completeEndpoint,
  required String key,
  required String uploadId,
  required List<PartETag> parts,
});
```

- `POST $baseUrl$completeEndpoint`
- Headers: `Content-Type: application/json`, `Authorization: Bearer $token`
- Body: `{ key, uploadId, parts: [{ partNumber, eTag }] }`
- Returns `fileUrl`

### 5.5 Abort Multipart

```dart
Future<void> abortMultipartUpload({
  required String baseUrl,
  required String token,
  required String key,
  required String uploadId,
});
```

- `POST $baseUrl/upload/video/abort` (or configurable abort endpoint)
- Body: `{ key, uploadId }`

---

## 6. Upload Orchestrator — `UploadController`

```dart
class UploadController {
  CancelToken? _cancelToken;

  Future<String> startUpload({
    required String baseUrl,
    required String token,
    required String uploadEndpoint,
    required String completeEndpoint,
    required File file,
    required String contentType,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatusChange,
  });
}
```

### Flow:

```
1. onStatusChange("Requesting upload URL...")
2. InitUploadResponse resp = await initiateUpload(...)

3. if (!resp.isMultipart) {
     onStatusChange("Uploading to S3...")
     fileUrl = await singlePutUpload(resp.uploadUrl, ...)
   } else {
     onStatusChange("Uploading parts...")
     etags = await uploadParts(resp.parts, ...)
     onStatusChange("Completing multipart...")
     fileUrl = await completeMultipartUpload(etags, ...)
   }

4. return fileUrl
```

---

## 7. UI Layer

### 7.1 Screens / Widgets

| Widget | Purpose |
|---|---|
| `UploadScreen` | Main screen — file picker + config inputs |
| `FilePickerCard` | Drop zone / file selection button |
| `ConfigSection` | Base URL, JWT token inputs |
| `UploadProgressCard` | Progress bar, status text, part grid |
| `PartGrid` | Grid of part tiles showing status per part |
| `LogViewer` | Scrollable log (optional, for debug builds) |

### 7.2 State Management (Provider / Riverpod / BLoC)

```dart
enum UploadStatus { idle, initiating, uploading, completing, done, error }

class UploadState {
  final UploadStatus status;
  final double progress;        // 0.0 – 1.0
  final String? statusMessage;
  final String? fileUrl;
  final String? errorMessage;
  final List<PartState> parts;  // per-part status
}

class PartState {
  final int partNumber;
  final PartUploadStatus status; // waiting, uploading, done, failed
  final String? eTag;
}
```

---

## 8. Key Implementation Details

### 8.1 File Slicing (without loading entire file into memory)

Use `RandomAccessFile` for efficient chunk reading:

```dart
final raf = await file.open(mode: FileMode.read);
try {
  final chunk = await raf.read(chunkSize);
  // upload chunk
} finally {
  await raf.close();
}
```

### 8.2 Dio for Upload Progress

```dart
Future<void> uploadChunk(String url, List<int> bytes) async {
  await dio.put(
    url,
    data: Stream.fromIterable([bytes]),
    options: Options(
      headers: { 'Content-Type': contentType },
      contentType: contentType,
    ),
    onSendProgress: (sent, total) {
      final pct = sent / total;
      onPartProgress(partNumber, pct);
    },
    cancelToken: cancelToken,
  );
}
```

### 8.3 Concurrency for Multipart Parts

Consider uploading 3–5 parts concurrently with a limit:

```dart
final pool = Pool(3); // max 3 concurrent uploads
final results = await Future.wait(
  parts.map((p) => pool.withResource(() => uploadSinglePart(p))),
);
```

### 8.4 ETag Extraction

The ETag header is returned on each part upload. Use Dio's `response.headers.value('etag')` or `http` package's `response.headers['etag']`.

---

## 9. Error Handling

| Scenario | Handling |
|---|---|
| Network failure on part upload | Retry up to N times, then fail |
| Backend returns non-200 on init | Surface error message from API |
| Part upload returns non-200 | Mark part failed, abort multipart |
| Complete call fails | Show error, upload remains on S3 (orphaned) |
| User cancels | Call `cancelToken.cancel()`, then `abortMultipartUpload()` |
| App killed during multipart | No recovery — backend should have lifecycle/cleanup |

---

## 10. Testing Plan

1. **Single PUT** — file < 15MB → verify direct PUT to S3
2. **Multipart** — file ≥ 15MB → verify part uploads + complete
3. **Abort mid-upload** → verify backend cleanup
4. **Network error** → verify retry logic
5. **Invalid token** → verify 401 handling
6. **Very large file** (1GB+) → verify memory efficiency (streaming)
