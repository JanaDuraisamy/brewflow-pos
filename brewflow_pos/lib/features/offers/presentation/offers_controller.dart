import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/features/offers/data/drift_offers_repository.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';

final offersRepositoryProvider = Provider<DriftOffersRepository>((ref) {
  return DriftOffersRepository(
    ref.watch(appDatabaseProvider),
    outbox: ref.watch(syncOutboxCoordinatorProvider),
  );
});

/// Offers scoped to the active business (Cafe / Food Truck / All). For
/// Owner Phone "All" shows combined (both shops' offers). Tablets are
/// single-business so they see only their shop's offers.
final offersProvider = FutureProvider<List<Offer>>((ref) async {
  final business = ref.watch(businessSwitcherProvider);
  final repo = ref.watch(offersRepositoryProvider);
  if (business == BusinessContext.all) {
    return repo.allOffers();
  }
  final shopId = await ref
      .read(businessSwitcherProvider.notifier)
      .shopIdFor(business);
  return repo.offersForShop(shopId);
});

final offersControllerProvider = Provider<OffersController>(
  (ref) => OffersController(ref),
);

final class OffersController {
  OffersController(this.ref);
  final Ref ref;

  Future<Offer> create({
    required String name,
    required OfferType type,
    required String configJson,
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    final business = ref.read(businessSwitcherProvider);
    final shopId = await ref
        .read(businessSwitcherProvider.notifier)
        .shopIdFor(
          business == BusinessContext.all ? BusinessContext.cafe : business,
        );
    final offer = await ref
        .read(offersRepositoryProvider)
        .createOffer(
          shopId: shopId,
          name: name,
          type: type,
          configJson: configJson,
          startAt: startAt,
          endAt: endAt,
        );
    ref.invalidate(offersProvider);
    return offer;
  }

  Future<Offer> update(Offer offer) async {
    final updated = await ref.read(offersRepositoryProvider).updateOffer(offer);
    ref.invalidate(offersProvider);
    return updated;
  }

  Future<void> toggleActive(Offer offer) async {
    await update(
      Offer(
        id: offer.id,
        shopId: offer.shopId,
        name: offer.name,
        type: offer.type,
        configJson: offer.configJson,
        isActive: !offer.isActive,
        startAt: offer.startAt,
        endAt: offer.endAt,
        createdAt: offer.createdAt,
        updatedAt: offer.updatedAt,
      ),
    );
  }

  Future<void> delete(String id) async {
    await ref.read(offersRepositoryProvider).deleteOffer(id);
    ref.invalidate(offersProvider);
  }
}
