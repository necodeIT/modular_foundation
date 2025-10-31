import 'package:modular_foundation/modular_foundation.dart';

/// A no-operation implementation of [AnalyticsService].
class NoopAnalyticsService extends AnalyticsService {
  @override
  noSuchMethod(Invocation invocation) {
    log('NoopAnalyticsService: ${invocation.memberName} called.');
  }
}
