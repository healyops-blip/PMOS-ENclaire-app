# Android report PDF integration and acceptance

Issue: #30
Recorded: 2026-08-28

## Flutter integration contract

- The app creates or retries the server artifact with
  `POST /api/reports/{report_id}/pdf` and an `Idempotency-Key`.
- It short-polls `GET /api/reports/{report_id}/pdf` while the task is
  `queued` or `processing`, then handles `succeeded` or `failed` explicitly.
  The client also reads the obsolete draft value `pending` as `queued` so an
  independently rolling server cannot strand an in-flight task.
- A successful task is downloaded only through authenticated
  `GET /api/reports/{report_id}/pdf/file`. The existing `PomiApiClient`
  attaches the opaque Session bearer token. Flutter does not consume or
  expose `download_url`, a server storage path, a QR code, or a public URL.
- The downloaded response must start with the PDF signature before it is
  stored. The client never generates a report PDF or captures App screens.
- Save uses the Android document picker, share uses the Android system share
  sheet, and print uses the Android print-service preview. Each action is
  initiated by the user from the immutable report page.
- A generation, status, download, save, share, or print error is shown in a
  persistent report-page status card with a retry action. The App report
  stays visible and neither the immutable snapshot nor an existing server
  file is changed.

## Private cache policy

`ReportPdfCache` writes into the application temporary directory under
`pomi-report-pdf-cache/` using an atomic `.part` file and a sanitized file
name.

- Maximum age: 24 hours.
- Maximum retained files: 4, newest first.
- Cleanup: before and after each completed download; stale partial files are
  deleted as well.
- This cache is an implementation detail, not a public sharing location.
  Users who choose **Save PDF** select the destination through Android.

## Automated verification

- API path, idempotency header, Session authorization, queued/processing/
  succeeded polling, and authenticated byte download.
- Backward-compatible parsing of the old `pending` status.
- PDF signature rejection, safe cache naming, expiry, file-count cap, and
  partial-file cleanup, plus full private-cache removal on logout/account switch.
- Report-page status, retry, cached system share/print dispatch, and continued
  visibility of the three-layer App report after failure.
- `flutter build apk --debug --no-pub` completed successfully on 2026-08-28.

## Android acceptance record

| Environment | Generate/poll | Auth download | Save | Share | Print | Failure/retry | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Android 16 / API 36 emulator | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | **PARTIAL — APK from code head `8633e7f` installed; cold launch completed in 1.542 s, `MainActivity` remained resumed, and no AndroidRuntime fatal crash was found. The complete PDF path remains NOT_RUN.** |
| Android physical device | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | **NOT_RUN — no physical Android device was connected to this agent** |

Before release, repeat the following on both targets with a signed-in account
and a successful immutable report:

1. Select each of **Save PDF**, **Share PDF**, and **Print PDF**.
2. Observe `queued`/`processing` and a successful authenticated download.
3. Open the saved copy, choose a share target, and open the Android print
   preview (a physical printer is not required for preview validation).
4. Disable networking during status polling and during file download, then
   verify the explicit retry card and that the App report remains usable.
5. Cancel the document picker, share sheet, and print preview; verify no public
   link or QR code is created and the report remains unchanged.
