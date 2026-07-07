# Upload System Rewrite — Plan & Spec

> Goal: one clean, understandable, native-background upload system for **all**
> uploads (video + images), with the current bugs fixed and the dead/legacy
> code removed. Old code is **kept as backup** (moved to `_legacy/`), not deleted.
>
> Guiding principle: **you should be able to read the flow top-to-bottom and
> understand it.** Every stage below is small enough to review on its own.

---

## 0. The mental model (read this first)

Every upload — a 2 GB course video or a 40 KB avatar — follows the **same 4 steps**:

```
  ┌──────────┐   ┌──────────────┐   ┌────────────┐   ┌────────────┐
  │ 1. INIT  │──▶│ 2. UPLOAD    │──▶│ 3. COMPLETE│──▶│ 4. CALLBACK│
  │ ask our  │   │ send bytes   │   │ tell S3    │   │ tell our   │
  │ backend  │   │ to S3 (pre-  │   │ "done", get│   │ backend the│
  │ for URLs │   │ signed URLs) │   │ final URL  │   │ file URL   │
  └──────────┘   └──────────────┘   └────────────┘   └────────────┘
```

- **Small file** → step 2 is a single `PUT` (direct upload).
- **Big file** → step 2 splits into parts, uploads each, collects ETags; step 3
  sends the ETags to finalize (multipart).

The backend decides small-vs-big and returns either one `uploadUrl` or a list of
`parts[]`. The client never guesses.

This 4-step model is ALREADY what your `UploadEngine` interface encodes. We keep it.

---

## 1. Target architecture (one system, three layers)

```
 Flutter UI  ──▶  UploadQueueProvider  ──▶  UploadQueue  ──▶  UploadEngine
 (buttons)        (app-specific: URLs,      (persistence,     (does the actual
                   bodies, callbacks)        retries, order)    HTTP / native work)
                                                                │
                                          ┌─────────────────────┼─────────────────────┐
                                          │                     │                     │
                                    DartHttpEngine       Android native         iOS native
                                    (desktop/tests)      (WorkManager +         (background
                                                          foreground svc)        URLSession)
```

- **One provider** (`UploadQueueProvider`) replaces the current
  `UnifiedUploadQueueProvider` + avatar/cover providers + `S3UploadService`.
  Images just use the same 4-step flow with a tiny file (direct upload).
- **One engine interface** (unchanged — it's good).
- **Native engines fixed** (see §3).
- **Legacy files** (`S3UploadService`, `BackgroundUploadManager`,
  `NativeUploadBridge` stub) → moved to `lib/_legacy/upload/` and no longer wired.

---

## 2. The API contract (from your working code — confirm this is right)

Base: `.../api/v1`

| Step | Endpoint (varies by type) | Request body (key fields) | Response (key fields) |
|------|---------------------------|---------------------------|-----------------------|
| INIT (video) | `/video-post/assets/upload` | `{videoFilename, videoContentType, videoFileSize}` | `{isMultipart, uploadUrl?, parts?[{partNumber,uploadUrl}], key, uploadId, fileUrl, totalParts, expiresIn}` |
| INIT (lesson) | `/course/module/lesson/upload` | `+ moduleID` | same |
| INIT (course thumb) | `/course/assets/upload` | `{thumbnailFilename, thumbnailContentType, thumbnailFileSize}` | nested `data.thumbnail` / `data.video` |
| INIT (resource) | `/course/module/resource/assets/upload` | `{filename, contentType}` | same |
| COMPLETE (all) | `/video-post/upload/complete` | `{key, uploadId, parts:[{partNumber, eTag}]}` | `{data:{fileUrl}}` |
| ABORT (all) | `/video-post/upload/abort` | `{key, uploadId}` | — |
| CALLBACK (video) | `/video-post` | `{title, videoUrl, duration, fileSize}` + `Idempotency-Key` | — |
| CALLBACK (lesson) | `/course/module/lesson` | `{title, moduleId, videoUrl, duration, fileSize}` | — |

**ETag rule:** S3 returns the ETag quoted (`"abc..."`). Keep it verbatim including
quotes — the complete endpoint expects the raw header value. (Confirmed in your code.)

> ❓ **Please confirm**: is this table correct and complete? If any endpoint
> expects a field I don't list, tell me now — this table is the single source of
> truth the whole rewrite builds against.

---

## 3. The bugs we fix during the rewrite

| # | Where | Bug | Fix |
|---|-------|-----|-----|
| B1 | iOS `AppDelegate.swift` | `uploadTask(with:fromFile:)` sends the **whole file** for every part → corrupt multipart on iOS | Write each part's byte range to its own temp file, upload that; delete after |
| B2 | `app_config.dart` + Android manifest | Plaintext **HTTP** + `usesCleartextTraffic` → tokens sent unencrypted | Move to HTTPS base URL; remove cleartext flag (needs a TLS endpoint from you) |
| B3 | iOS complete/callback | Uses foreground `URLSession.shared` → lost if app killed mid-finalize → orphaned S3 upload | Run complete+callback on a background session / retry on relaunch |
| B4 | Android `TokenRefreshUtil.kt` | Doc claims encrypted storage; really volatile in-memory; refreshed token never returned to Dart; `UploadWorker` PUT has no 401 path | Persist refreshed token, propagate to Dart `AuthController`; document the real behavior |
| B5 | Both natives | No content integrity check | Add optional MD5/SHA per part (S3 supports `Content-MD5`) — behind a config flag |
| B6 | Logging | `HttpLoggingInterceptor.BODY` + Dart body logs leak tokens | Redact Authorization headers; drop to `HEADERS` level in release |

B1–B4 are correctness/security and are the core reason the current system "isn't
good enough." B5–B6 are hardening.

---

## 4. Implementation stages (each is a separate, reviewable step)

I will do these **in order** and stop after each for you to review. I will NOT
dump everything at once.

- **Stage 0 — Safety net.** Move legacy files to `lib/_legacy/upload/`. Confirm
  the app still builds using only the `upload_queue` path. No behavior change.
- **Stage 1 — Consolidate the provider.** Fold avatar/cover image uploads into the
  unified queue (images = direct upload). Delete `S3UploadService` usage. One
  provider, one code path. Add a short `README.md` in the feature folder.
- **Stage 2 — Fix iOS byte-range (B1).** The most serious correctness bug. Add a
  Swift test/log to prove each part uploads the right bytes.
- **Stage 3 — Fix iOS finalize survival (B3)** + **Android token refresh (B4).**
- **Stage 4 — Security pass (B2, B6).** HTTPS, cleartext off, log redaction.
- **Stage 5 — Integrity + tests (B5).** Optional checksums; add native-path tests
  and a provider test. Wire telemetry hooks (success/failure counters).
- **Stage 6 — Docs.** One `docs/uploads.md` that explains the whole flow with the
  diagram above, so the next person (or you in 3 months) gets it in 10 minutes.

Each stage ends with `flutter analyze` clean and the existing `upload_queue`
tests passing.

---

## 5. What I will NOT do (unless you say so)

- I won't delete the legacy code — it moves to `_legacy/` as backup.
- I won't change the backend or the API contract.
- I won't rip out the WorkManager/URLSession design — you chose full native
  background, and the design is sound; we're fixing and consolidating it.

---

## 6. Open questions for you

1. **API table in §2 — correct and complete?** (Most important.)
2. **HTTPS endpoint (B2):** do you have an HTTPS/domain URL for the backend, or is
   `http://108.181.195.154:3000` all that exists right now? (Affects whether B2 is
   a code change or blocked on infra.)
3. **Images (avatar/cover):** OK to route them through the same queue as
   direct-uploads, or do you want them kept separate and simple?
4. **Order:** happy with the stage order in §4, or want a specific bug first?
