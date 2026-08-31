import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/whatsapp_verification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_customers_repository.dart';

void main() {
  group('WhatsApp status model', () {
    test('UNKNOWN is the initial state and never self-promotes', () {
      final customer = Customer(
        id: 'c1',
        name: 'Lakshmi',
        phone: '+919876543210',
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      expect(customer.whatsappStatus, WhatsAppStatus.unknown);

      // copyWith without a status keeps the honest state.
      expect(
        customer.copyWith(name: 'Renamed').whatsappStatus,
        WhatsAppStatus.unknown,
      );
    });

    test('VERIFIED only comes from an explicit verified value', () {
      final authzlessCustomer = Customer(
        id: 'c2',
        name: 'Ravi',
        phone: '+919876543211',
        isActive: true,
        whatsappStatus: WhatsAppStatus.verified,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      expect(authzlessCustomer.whatsappStatus, WhatsAppStatus.verified);
    });
  });

  group('provider boundary', () {
    test(
      'default binding reports UNAVAILABLE (no fake verification)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final service = container.read(whatsappVerificationServiceProvider);
        expect(service, isA<UnavailableWhatsAppVerificationService>());

        final result = await service.verify('+919876543210');
        expect(result, WhatsAppStatus.unavailable);
      },
    );

    test(
      'a future real provider maps verified/not-verified directly',
      () async {
        final service = FakeWhatsAppVerificationService({
          '+919876543210': WhatsAppStatus.verified,
          '+919800000000': WhatsAppStatus.notVerified,
        });
        expect(await service.verify('+919876543210'), WhatsAppStatus.verified);
        expect(
          await service.verify('+919800000000'),
          WhatsAppStatus.notVerified,
        );
      },
    );
  });

  group('persistence via repository', () {
    test(
      'create defaults to UNKNOWN; update preserves existing status',
      () async {
        final repo = FakeCustomersRepository();
        await repo.createCustomer(name: 'New Walkin', phone: '9812345678');
        expect(
          repo.storedCustomers.single.whatsappStatus,
          WhatsAppStatus.unknown,
        );

        await repo.createCustomer(
          name: 'Verified Member',
          phone: '9876500000',
          isActive: true,
          whatsappStatus: WhatsAppStatus.verified,
        );

        // A later edit that does not mention WhatsApp preserves the state.
        await repo.updateCustomer(
          id: 'customer-2',
          name: 'Verified Member 2',
          isActive: true,
        );
        expect(
          repo.storedCustomers.last.whatsappStatus,
          WhatsAppStatus.verified,
        );
      },
    );
  });
}

final class FakeWhatsAppVerificationService
    implements WhatsAppVerificationService {
  FakeWhatsAppVerificationService(this.responses);

  final Map<String, WhatsAppStatus> responses;

  @override
  Future<WhatsAppStatus> verify(String phoneNumberE164) async =>
      responses[phoneNumberE164] ?? WhatsAppStatus.notVerified;
}
