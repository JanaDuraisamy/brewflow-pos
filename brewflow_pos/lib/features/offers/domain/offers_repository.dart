/// ---------------------------------------------------------------------------
/// BrewFlow POS — Offers Repository Interface
///
/// Implemented by [DriftOffersRepository]. Fakes used in tests implement this
/// interface to avoid depending on Drift or the local database.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/offers/domain/offers_models.dart';

abstract interface class OffersRepository {
  /// Returns all offers for a specific shop.
  Future<List<Offer>> offersForShop(String shopId);

  /// Returns all offers across all shops (owner Combined view).
  Future<List<Offer>> allOffers();

  /// Creates a new offer.
  Future<Offer> createOffer({
    required String shopId,
    required String name,
    required OfferType type,
    required String configJson,
    bool isActive = true,
    DateTime? startAt,
    DateTime? endAt,
  });

  /// Updates an existing offer.
  Future<Offer> updateOffer(Offer offer);

  /// Deletes an offer by id.
  Future<void> deleteOffer(String id);
}
