import 'package:brewflow_pos/features/customers/domain/whatsapp_verification.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_form_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_customers_repository.dart';

void main() {
  testWidgets('phone field shows honest WhatsApp status and never a fake '
      'verified tick', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        customersRepositoryProvider.overrideWithValue(
          FakeCustomersRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CustomerFormPage()),
      ),
    );
    await tester.pumpAndSettle();

    // New customer: honest "Not verified", no green check.
    expect(find.text('WhatsApp: Not verified'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    // Saving with just a phone works; verification is not required.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Customer name *'),
      'Lakshmi',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone number'),
      '9876543210',
    );
    await tester.ensureVisible(find.text('Save Customer'));
    await tester.tap(find.text('Save Customer'));
    await tester.pumpAndSettle();

    final repo =
        container.read(customersRepositoryProvider) as FakeCustomersRepository;
    expect(repo.storedCustomers.single.phone, '9876543210');
    expect(repo.storedCustomers.single.whatsappStatus, WhatsAppStatus.unknown);
  });
}
