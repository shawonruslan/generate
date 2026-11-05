/// Central configuration for the Team Drive Flutter app.
///
/// Fill in [workerBaseUrl] with your deployed Cloudflare Worker URL
/// (the same backend the web app uses). Everything else is derived from it.
class AppConfig {
  /// Default: the live Team Drive worker. Change if you redeploy elsewhere.
  static const String workerBaseUrl = 'https://mainstorage.jonchristiangarcia.workers.dev';

  /// Expected worker version string (shown in Settings > About).
  static const String expectedWorkerVersion = '7.6';

  /// Multipart upload threshold + chunk size (mirrors the web app:
  /// single-shot ≤95 MiB, MPU with 25 MiB parts, 3 parallel).
  static const int multipartThresholdBytes = 95 * 1024 * 1024;
  static const int multipartChunkBytes = 25 * 1024 * 1024;

  /// Group post file cap enforced by the worker.
  static const int groupPostMaxBytes = 512 * 1024 * 1024;
}
