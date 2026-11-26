/// Stable, user-facing error categories shared by every engine.
///
/// Engines translate transport-specific failures into these kinds so the UI can
/// show consistent guidance without leaking implementation details.
enum AppErrorKind {
  network,
  unauthorized,
  quotaExceeded,
  rateLimited,
  invalidRequest,
  modelUnavailable,
  server,
  cancelled,
  storage,
  modelMissing,
  unsupported,
  malformedResponse,
  unknown,
}

class AppException implements Exception {
  const AppException(
    this.kind,
    this.message, {
    this.detail,
    this.retryable = false,
  });

  final AppErrorKind kind;
  final String message;
  final String? detail;
  final bool retryable;

  bool get isCancellation => kind == AppErrorKind.cancelled;

  @override
  String toString() => 'AppException($kind): $message';
}

class CancelledException extends AppException {
  const CancelledException()
    : super(AppErrorKind.cancelled, 'Generation cancelled.');
}
