# Upload Queue — Usage Examples

## 1. Your current backend (defaults work out of the box)

```dart
final queue = UploadQueue(
  config: UploadConfig(
    initUploadEndpoint: '$baseUrl/course/module/lesson/upload',
    tokenProvider: () => AuthController.accessToken ?? '',
    buildCallback: (task) => CallbackRequest(
      url: '$baseUrl/course/module/lesson',
      body: {'videoUrl': task.fileUrl, 'title': task.title},
      idempotencyKey: 'cb_${task.id}',
    ),
  ),
);
// → All defaults match your backend's {isMultipart, uploadId, fileUrl, ...}
```

## 2. Different field names (e.g. `signedUrl` instead of `uploadUrl`)

```dart
UploadConfig(
  // ...
  parseInitResponse: (json) {
    final isMultipart = json['multipart'] == true;
    return InitUploadResponse(
      isMultipart: isMultipart,
      uploadUrl: json['signedUrl'] as String?,
      fileUrl: json['downloadUrl'] as String,
      s3UploadId: isMultipart ? json['s3UploadId'] as String? : null,
      totalParts: json['totalParts'] as int? ?? 0,
      parts: (json['chunks'] as List?)?.map((p) => PartPresignedUrl(
        partNumber: p['index'] as int,
        uploadUrl: p['signedUrl'] as String,
      )).toList() ?? [],
    );
  },
  parseCompleteResponse: (json) => json['data']?['url'] as String?,
  buildCompleteBody: (s3UploadId, parts) => {
    's3UploadId': s3UploadId,
    'parts': parts.map((p) => p.toJson()).toList(),
  },
  buildAbortBody: (s3UploadId) => {'s3UploadId': s3UploadId},
  extractETag: (headers) => headers['etag']?.replaceAll('"', ''),
)
```

## 3. `data` wrapper (e.g. `{data: {fileUrl: "..."}}`)

```dart
UploadConfig(
  parseInitResponse: (json) {
    final data = json['data'] as Map<String, dynamic>;
    return InitUploadResponse.fromJson(data); // reuse default parser on inner data
  },
  parseCompleteResponse: (json) {
    final data = json['data'] as Map<String, dynamic>;
    return data['fileUrl'] as String?;
  },
)
```

## 4. No multipart — always direct upload

```dart
UploadConfig(
  parseInitResponse: (json) => InitUploadResponse(
    isMultipart: false,
    uploadUrl: json['uploadUrl'] as String,
    fileUrl: json['fileUrl'] as String,
  ),
  // completeMultipart won't be called since isMultipart is always false
)
```

## 5. Custom init request body

```dart
UploadConfig(
  buildInitBody: (fileName, extraFields) => {
    'name': fileName,
    'mimeType': extraFields?['contentType'] ?? 'video/mp4',
    'moduleID': extraFields?['moduleId'],
  },
  // parseInitResponse: ... (match your backend's response)
)
```

## What's customizable

| Hook | Purpose | Default value |
|------|---------|---------------|
| `buildInitBody` | Request body for init POST | `{filename, contentType}` + extras |
| `parseInitResponse` | Parse init response → `InitUploadResponse` | `{isMultipart, uploadUrl, fileUrl, uploadId, totalParts, parts}` |
| `buildCompleteBody` | Request body for complete POST | `{uploadId, parts[{partNumber, eTag}]}` |
| `parseCompleteResponse` | Extract `fileUrl` from complete response | `json['fileUrl']` |
| `buildAbortBody` | Request body for abort POST | `{uploadId}` |
| `extractETag` | Extract ETag from S3 PUT headers | `headers['etag']` (strip quotes) |
