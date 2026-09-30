import 'dart:async';

import 'package:brewflow_pos/core/network/rpc_timeout.dart';
import 'package:flutter_test/flutter_test.dart';

/// [rpcWithTimeout] gained an optional `name` so every Supabase call can be
/// traced from one choke point. The contract that matters is that naming a call
/// changes only the logging: the value, the thrown type, the timeout and the
/// un-named path must all behave exactly as they did before.
void main() {
  group('rpcWithTimeout', () {
    test('returns the value unchanged when unnamed', () async {
      expect(await rpcWithTimeout(() async => 42), 42);
    });

    test('returns the value unchanged when named', () async {
      expect(await rpcWithTimeout(() async => 42, name: 'some_rpc'), 42);
    });

    test('is called exactly once', () async {
      var calls = 0;
      await rpcWithTimeout(() async {
        calls++;
        return 'ok';
      }, name: 'some_rpc');
      expect(calls, 1);
    });

    test('propagates the original error object when unnamed', () async {
      final boom = StateError('boom');
      await expectLater(
        rpcWithTimeout<void>(() async => throw boom),
        throwsA(same(boom)),
      );
    });

    test('propagates the original error object when named', () async {
      final boom = StateError('boom');
      await expectLater(
        rpcWithTimeout<void>(() async => throw boom, name: 'some_rpc'),
        // Identity, not just type: a wrapped error would break the
        // `on BillingFailure` / `catch (Exception)` handling in the repositories.
        throwsA(same(boom)),
      );
    });

    test(
      'surfaces a TimeoutException when the call exceeds the timeout',
      () async {
        await expectLater(
          rpcWithTimeout<void>(
            () => Completer<void>().future,
            timeout: const Duration(milliseconds: 20),
            name: 'create_sale_atomic',
          ),
          throwsA(isA<TimeoutException>()),
        );
      },
    );

    test('applies the default 30s ceiling when no timeout is given', () {
      expect(kRpcTimeout, const Duration(seconds: 30));
    });

    test(
      'does not complete early when the call is slow but within timeout',
      () async {
        final result = await rpcWithTimeout(
          () async {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return 'slow';
          },
          timeout: const Duration(milliseconds: 200),
          name: 'some_rpc',
        );
        expect(result, 'slow');
      },
    );
  });
}
