import '../../core/errors/app_exception.dart';

/// Cooperative cancellation shared by the UI and engines.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }
}
