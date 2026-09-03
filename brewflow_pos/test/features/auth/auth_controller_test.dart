import 'dart:async';

import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_offers_repository.dart';
import '../../helpers/fake_staff_repository.dart';

void main() {
  late FakeAuthRepository fake;
  late ProviderContainer container;

  setUp(() {
    fake = FakeAuthRepository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(fake),
        offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
        staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
      ],
    );
  });

  tearDown(() => container.dispose());

  AuthState read() => container.read(authControllerProvider);
  AuthController controller() =>
      container.read(authControllerProvider.notifier);

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  group('initial state', () {
    test('starts in initializing when no session is present', () {
      expect(read().status, AuthStatus.initializing);
      expect(read().signingIn, isFalse);
    });

    test('starts authenticated when a session already exists', () {
      final signedInContainer = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              user: const AuthUser(id: 'u1', email: 'a@b.com'),
            ),
          ),
        ],
      );
      addTearDown(signedInContainer.dispose);

      final state = signedInContainer.read(authControllerProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.userEmail, 'a@b.com');
    });
  });

  group('auth state changes', () {
    test('session event switches to authenticated', () async {
      expect(read().status, AuthStatus.initializing);

      fake.emit(const AuthUser(id: 'u1', email: 'a@b.com'));
      await flush();

      expect(read().status, AuthStatus.authenticated);
      expect(read().userEmail, 'a@b.com');
    });

    test('sign-out event switches to unauthenticated', () async {
      read();
      fake.emit(const AuthUser(id: 'u1', email: 'a@b.com'));
      await flush();
      expect(read().status, AuthStatus.authenticated);

      fake.emit(null);
      await flush();

      expect(read().status, AuthStatus.unauthenticated);
      expect(read().userEmail, isNull);
    });

    test('follows authenticated → unauthenticated → authenticated', () async {
      read();
      fake.emit(const AuthUser(id: 'u1', email: 'a@b.com'));
      await flush();
      expect(read().status, AuthStatus.authenticated);

      fake.emit(null);
      await flush();
      expect(read().status, AuthStatus.unauthenticated);

      fake.emit(const AuthUser(id: 'u2', email: 'b@c.com'));
      await flush();
      expect(read().status, AuthStatus.authenticated);
      expect(read().userEmail, 'b@c.com');
    });

    test('exactly one auth subscription exists per scope', () {
      container.read(authControllerProvider);
      container.read(authControllerProvider.notifier);
      container.read(authControllerProvider);

      expect(fake.listenCount, 1);
    });

    test('an error on the auth stream surfaces a safe error state', () async {
      read();
      fake.emitError(StateError('stream failed'));
      await flush();

      expect(read().status, AuthStatus.error);
      expect(read().failure, isA<UnexpectedAuthFailure>());
    });
  });

  group('sign-in', () {
    test('successful sign-in authenticates through the repository', () async {
      await controller().signInWithEmailAndPassword('a@b.com', 'secret');

      expect(fake.signIns, [('a@b.com', 'secret')]);
      expect(read().status, AuthStatus.authenticated);
      expect(read().userEmail, 'a@b.com');
      expect(read().signingIn, isFalse);
      expect(read().failure, isNull);
    });

    test('mapped failure becomes an error state with a safe failure', () async {
      fake.signInError = const InvalidCredentialsFailure();

      await controller().signInWithEmailAndPassword('a@b.com', 'wrong');

      expect(read().status, AuthStatus.error);
      expect(read().failure, isA<InvalidCredentialsFailure>());
      expect(read().signingIn, isFalse);
      expect(read().userEmail, isNull);
    });

    test('network failure becomes a network error state', () async {
      fake.signInError = const NetworkFailure();

      await controller().signInWithEmailAndPassword('a@b.com', 'x');

      expect(read().status, AuthStatus.error);
      expect(read().failure, isA<NetworkFailure>());
    });

    test('unexpected errors are mapped to a safe generic failure', () async {
      fake.signInRawError = StateError('backend exploded');

      await controller().signInWithEmailAndPassword('a@b.com', 'x');

      expect(read().status, AuthStatus.error);
      expect(read().failure, isA<UnexpectedAuthFailure>());
    });

    test(
      'duplicate submission is ignored while a sign-in is in flight',
      () async {
        fake.signInGate = Completer<void>();

        final first = controller().signInWithEmailAndPassword('a@b.com', 'x');
        final second = controller().signInWithEmailAndPassword('a@b.com', 'x');

        expect(fake.signIns.length, 1);
        expect(read().signingIn, isTrue);
        expect(read().status, AuthStatus.initializing);

        fake.signInGate!.complete();
        await Future.wait([first, second]);

        expect(read().status, AuthStatus.authenticated);
        expect(read().signingIn, isFalse);
      },
    );
  });

  group('sign-out', () {
    test(
      'signs out through the repository and returns to unauthenticated',
      () async {
        read();
        fake.emit(const AuthUser(id: 'u1', email: 'a@b.com'));
        await flush();
        expect(read().status, AuthStatus.authenticated);

        await controller().signOut();

        expect(fake.signOutCalls, 1);
        expect(read().status, AuthStatus.unauthenticated);
      },
    );

    test('sign-out clears the POS cart, filter and purchase draft', () async {
      read();
      fake.emit(const AuthUser(id: 'u1', email: 'a@b.com'));
      await flush();
      expect(read().status, AuthStatus.authenticated);

      final now = DateTime.now().toUtc();
      final product = Product(
        id: 'p1',
        categoryId: 'c1',
        name: 'Filter Coffee',
        sku: null,
        sellingPricePaise: 12000,
        costPricePaise: null,
        stockQuantity: 5,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
      container.read(cartProvider.notifier).add(product);
      container.read(posFilterProvider.notifier).setQuery('coffee');
      container
          .read(purchaseFormProvider.notifier)
          .addLine(product: product, quantity: 2, unitCostPaise: 8000);
      expect(container.read(cartProvider).lines, hasLength(1));
      expect(container.read(posFilterProvider).query, 'coffee');
      expect(container.read(purchaseFormProvider).lines, hasLength(1));

      await controller().signOut();

      expect(container.read(cartProvider).isEmpty, isTrue);
      expect(container.read(posFilterProvider).query, isEmpty);
      expect(container.read(purchaseFormProvider).lines, isEmpty);
      expect(read().status, AuthStatus.unauthenticated);
    });
  });
}
