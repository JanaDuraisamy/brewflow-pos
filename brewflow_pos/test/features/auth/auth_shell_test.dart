import 'dart:async';

import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  final validEmail = 'owner@brewflow.example';
  final validPassword = 'secret-password';

  Widget shell(FakeAuthRepository fake) => ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(fake)],
    child: const MaterialApp(home: AuthShell()),
  );

  Future<void> enterCredentials(
    WidgetTester tester, {
    required String email,
    required String password,
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(find.byType(TextFormField).at(1), password);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('Sign In'));
    await tester.pump();
  }

  testWidgets('empty submission shows required-field validation', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(shell(fake));

    await submit(tester);

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(fake.signIns, isEmpty);
  });

  testWidgets('invalid email format is rejected without submission', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(shell(fake));

    await enterCredentials(
      tester,
      email: 'not-an-email',
      password: validPassword,
    );
    await submit(tester);

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(fake.signIns, isEmpty);
  });

  testWidgets('valid credentials submit and show progress while in flight', (
    tester,
  ) async {
    final fake = FakeAuthRepository()..signInGate = Completer<void>();
    await tester.pumpWidget(shell(fake));

    await enterCredentials(tester, email: validEmail, password: validPassword);
    await submit(tester);

    expect(fake.signIns, [(validEmail, validPassword)]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      button.onPressed,
      isNull,
      reason: 'button disabled while signing in',
    );

    fake.signInGate!.complete();
    await tester.pumpAndSettle();
    expect(
      fake.user?.email,
      validEmail,
      reason: 'repository reports the signed-in user',
    );
  });

  testWidgets('tapping the button twice does not double-submit', (
    tester,
  ) async {
    final fake = FakeAuthRepository()..signInGate = Completer<void>();
    await tester.pumpWidget(shell(fake));

    await enterCredentials(tester, email: validEmail, password: validPassword);
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();

    expect(fake.signIns.length, 1);
    fake.signInGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('failed sign-in shows the safe message and clears the password', (
    tester,
  ) async {
    final fake = FakeAuthRepository()
      ..signInError = const InvalidCredentialsFailure();
    await tester.pumpWidget(shell(fake));

    await enterCredentials(tester, email: validEmail, password: validPassword);
    await submit(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Incorrect email or password. Please try again.'),
      findsOneWidget,
    );
    expect(
      find.text(validPassword),
      findsNothing,
      reason: 'password field cleared after failure',
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull, reason: 'retry enabled after failure');
  });

  testWidgets('password visibility can be toggled', (tester) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(shell(fake));

    await tester.enterText(find.byType(TextFormField).at(1), 'abc');

    EditableText editable() =>
        tester.widget<EditableText>(find.byType(EditableText).last);
    expect(editable().obscureText, isTrue);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(editable().obscureText, isFalse);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(editable().obscureText, isTrue);
  });
}
