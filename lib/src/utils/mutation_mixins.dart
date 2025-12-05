import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:modular_foundation/modular_foundation.dart';

/// A mixin that provides mutation capabilities to a [Repo].
mixin MutationMixins<T> on Repo<T>, RepoLifecycleHooksMixin<T> {
  bool _installed = false;
  int _stateVersion = 0;

  /// Installs required lifecycle hooks required for [MutationMixins] to function.
  @mustCallInConstructor
  void installMutationHooks() {
    if (_installed) return;

    onData((_) => _stateVersion++);
    onError((_, _) => _stateVersion++);

    _installed = true;
  }

  /// Runs a stateful mutation on the repo's current data with telemetry + analytics.
  ///
  /// - [name] is the logical name of the mutation (also used for the span name).
  /// - [mutation] is called with the current data and returns the new value.
  /// - [attributes] (optional) are attached as analytics event properties.
  /// - [eventName] (optional) overrides the default `mutation_<name>` event key.
  /// - [retryPolicy] (optional) defines the retry behavior for the mutation.
  /// - [optimisticPolicy] (optional) defines the optimistic update strategy.
  ///
  /// Behavior:
  /// - Throws a [StateError] if [installMutationHooks] was not called.
  /// - Returns `null` if the repo has no data or if an error occurs.
  /// - Wraps the mutation in a telemetry span and tracks an analytics event.
  Future<T?> mutate(
    String name,
    FutureOr<T> Function(T currentData) mutation, {
    Map<String, String>? attributes,
    String? eventName,
    RetryPolicy retryPolicy = RetryPolicy.noRetry,
    OptimisticPolicy<RepoState<T>>? optimisticPolicy,
  }) async {
    eventName ??= 'mutation_$name';

    final snapshot = state;
    final stateVersion = ++_stateVersion;

    if (!_installed) {
      throw StateError(
        'Mutation hooks are not installed. Please call installMutationHooks() in the constructor.',
      );
    }

    if (!state.hasData) {
      log('Cannot perform mutation $name: Repo has no data');
      return null;
    }

    _applyOptimistics(optimisticPolicy);

    final telemetry = GetIt.I.get<TelemetryService>();
    final analytics = GetIt.I.get<AnalyticsService>();

    try {
      await analytics.trackEvent(eventName, properties: attributes);

      final result = await telemetry.runSpan(name, () async {
        for (var i = 0; i < retryPolicy.maxAttempts; i++) {
          try {
            final result = await telemetry.runSpan(
              'try_$i',
              () async => mutation(state.requireData),
            );

            return result;
          } catch (e) {
            if (i == retryPolicy.maxAttempts - 1) {
              rethrow;
            } else {
              await Future.delayed(retryPolicy.timeout);
              continue;
            }
          }
        }

        throw StateError('Unreachable code in mutation retry logic');
      });

      data(result);
      return result;
    } catch (e, st) {
      log('Error during mutation $name', e, st);
      _revertOptimistic(optimisticPolicy, snapshot, e, stateVersion);
      return null;
    }
  }

  /// Runs a side-effecting action with telemetry + analytics, without repo data.
  ///
  /// - [name] is the logical name of the action (also used for the span name).
  /// - [action] is the callback to execute.
  /// - [attributes] (optional) are attached as analytics event properties.
  /// - [eventName] (optional) overrides the default `mutation_<name>` event key.
  /// - [retryPolicy] (optional) defines the retry behavior for the action.
  /// - [optimisticPolicy] (optional) defines the optimistic update strategy.
  ///
  /// Behavior:
  /// - Throws a [StateError] if [installMutationHooks] was not called.
  /// - Wraps the action in a telemetry span and tracks an analytics event.
  /// - Logs but swallows errors; failures do not throw.
  ///
  /// Similar to [mutate], but does not provide the current data.
  Future<void> action(
    String name,
    FutureOr<void> Function() action, {
    Map<String, String>? attributes,
    String? eventName,
    RetryPolicy retryPolicy = RetryPolicy.noRetry,
    OptimisticPolicy<RepoState<T>>? optimisticPolicy,
  }) async {
    eventName ??= 'action_$name';

    if (!_installed) {
      throw StateError(
        'Mutation hooks are not installed. Please call installMutationHooks() in the constructor.',
      );
    }
    _applyOptimistics(optimisticPolicy);
    final telemetry = GetIt.I.get<TelemetryService>();
    final analytics = GetIt.I.get<AnalyticsService>();

    try {
      await analytics.trackEvent(eventName, properties: attributes);
      await telemetry.runSpan(name, () async {
        for (var i = 0; i < retryPolicy.maxAttempts; i++) {
          try {
            await telemetry.runSpan('try_$i', () async => action());
            return;
          } catch (e) {
            if (i == retryPolicy.maxAttempts - 1) {
              rethrow;
            } else {
              await Future.delayed(retryPolicy.timeout);
              continue;
            }
          }
        }
      });
    } catch (e, st) {
      log('Error during action $name', e, st);
      _revertOptimistic(optimisticPolicy, state, e, _stateVersion);
    }
  }

  void _applyOptimistics(OptimisticPolicy<RepoState<T>>? policy) {
    if (policy == null) return;

    final optimisticValue = policy.optimisticValue(state);

    optimisticValue.when(
      data: (d) => data(d.requireData),
      loading: (_) => loading,
      error: error,
    );
  }

  void _revertOptimistic(
    OptimisticPolicy<RepoState<T>>? policy,
    RepoState<T> snapshot,
    Object? error,
    int version,
  ) {
    if (policy == null) return;
    if (!policy.shouldRevert(error)) return;
    if (version != _stateVersion) return;

    snapshot.when(
      data: (d) => data(d.requireData),
      loading: (_) => loading,
      error: this.error,
    );
  }
}
