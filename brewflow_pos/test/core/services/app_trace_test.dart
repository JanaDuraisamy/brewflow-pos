import 'package:brewflow_pos/core/services/app_trace.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks down the two rules that make a trace line safe to ship to a device
/// log: field keys are screened, and values are bounded. A regression in either
/// is a credential or a customer record on disk, so these are asserted rather
/// than trusted to review.
void main() {
  group('AppTrace.format', () {
    test('renders `event key=value` pairs', () {
      expect(
        AppTrace.format('sale.ok', {
          'receipt': 'BF-000042',
          'totalPaise': 27800,
        }),
        'sale.ok receipt=BF-000042 totalPaise=27800',
      );
    });

    test('returns the bare event name when there are no fields', () {
      expect(AppTrace.format('rpc.ok', const {}), 'rpc.ok');
    });

    test('omits null values instead of printing "null"', () {
      expect(
        AppTrace.format('checkout.begin', {'method': null, 'totalPaise': 100}),
        'checkout.begin totalPaise=100',
      );
    });

    test('folds whitespace so one event stays on one line', () {
      expect(
        AppTrace.format('cart.add', {'name': 'Masala\n  Chai'}),
        'cart.add name=Masala Chai',
      );
    });

    test('renders a Duration as milliseconds', () {
      expect(
        AppTrace.format('rpc.ok', {'ms': const Duration(milliseconds: 412)}),
        'rpc.ok ms=412ms',
      );
    });

    test('truncates an over-long value', () {
      final line = AppTrace.format('x.y', {'note': 'a' * 500});
      expect(line, contains('…'));
      expect(line.length, lessThan(200));
    });
  });

  group('AppTrace secret screening', () {
    // Every one of these must be masked no matter what a call site passes.
    const denied = <String, String>{
      'password': 'hunter2',
      'passwd': 'hunter2',
      'pwd': 'hunter2',
      'userPassword': 'hunter2',
      'token': 'abc123',
      'accessToken': 'abc123',
      'refresh_token': 'abc123',
      'idToken': 'abc123',
      'apiKey': 'sk-live-123',
      'api_key': 'sk-live-123',
      'publishableKey': 'pk-123',
      'secret': 'shh',
      'clientSecret': 'shh',
      'authorization': 'Bearer abc',
      'jwt': 'a.b.c',
      'credential': 'x',
      'privateKey': 'x',
      'email': 'owner@example.com',
      'userEmail': 'owner@example.com',
      'phone': '+91 99999 99999',
      'address': '12 Market Road',
      'shippingAddress': '12 Market Road',
      'otp': '123456',
      'cvv': '999',
    };

    denied.forEach((key, value) {
      test('redacts a `$key` value', () {
        final line = AppTrace.format('e', {key: value});
        expect(line, isNot(contains(value)));
        expect(line, contains('<redacted>'));
      });
    });

    test('redacts a denied key regardless of case or separators', () {
      for (final key in const [
        'PASSWORD',
        'Access-Token',
        'apiKey',
        'API_KEY',
        'user.email',
      ]) {
        expect(
          AppTrace.format('e', {key: 'leak-me-please'}),
          isNot(contains('leak-me-please')),
          reason: 'expected `$key` to be screened',
        );
      }
    });

    test('masks the key name too, so a denied field is identifiable', () {
      final line = AppTrace.format('e', {'password': 'hunter2'});
      expect(line, contains('<denied>'));
    });

    test('a denied key does not consume the next key', () {
      final line = AppTrace.format('e', {'token': 'abc', 'totalPaise': 500});
      expect(line, 'e <denied>=<redacted> totalPaise=500');
    });

    test('does not over-redact ordinary field names', () {
      final line = AppTrace.format('e', {
        'shopRef': 'a1b2c3d4',
        'productRef': 'deadbeef',
        'lineRef': '00112233',
        'reason': 'split_underpaid',
      });
      expect(line, isNot(contains('<redacted>')));
      expect(line, contains('shopRef=a1b2c3d4'));
    });
  });

  group('AppTrace.userRef', () {
    test('is stable for the same identity', () {
      expect(AppTrace.userRef('a@b.com'), AppTrace.userRef('a@b.com'));
    });

    test('differs across identities', () {
      expect(AppTrace.userRef('a@b.com'), isNot(AppTrace.userRef('c@d.com')));
    });

    test('does not contain the source identity', () {
      const identity = 'owner@example.com';
      final ref = AppTrace.userRef(identity);
      expect(ref, isNot(contains(identity)));
      expect(ref, isNot(contains('example')));
    });

    test('is short enough to stay readable in a log line', () {
      expect(AppTrace.userRef('owner@example.com').length, 8);
    });

    test('degrades to a marker for a missing identity', () {
      expect(AppTrace.userRef(null), '<none>');
      expect(AppTrace.userRef(''), '<none>');
    });
  });

  test('every trace shares one Logcat marker', () {
    expect(kAppTraceTag, 'BREWFLOW');
  });
}
