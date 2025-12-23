import 'package:grumpy/grumpy.dart';

/// A no-operation implementation of [TelemetryService].
class NoopTelemetryService extends TelemetryService {
  @override
  noSuchMethod(Invocation invocation) {
    log('NoopTelemetryService: ${invocation.memberName} called.');
  }
}
