import 'package:modular_foundation/modular_foundation.dart';

/// A no-operation implementation of [TelemetryService].
class NoopTelemetryService extends TelemetryService {
  @override
  noSuchMethod(Invocation invocation) {
    log('NoopTelemetryService: ${invocation.memberName} called.');
  }
}
