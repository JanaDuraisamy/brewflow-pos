import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/offers/domain/offers_repository.dart';

/// In-memory fake for [OffersRepository] used in widget/layout tests.
final class FakeOffersRepository implements OffersRepository {
  final List<Offer> _offers = [];

  @override
  Future<List<Offer>> offersForShop(String shopId) async =>
      _offers.where((o) => o.shopId == shopId).toList();

  @override
  Future<List<Offer>> allOffers() async => List.from(_offers);

  @override
  Future<Offer> createOffer({
    required String shopId,
    required String name,
    required OfferType type,
    required String configJson,
    bool isActive = true,
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    final offer = Offer(
      id: 'offer-${_offers.length + 1}',
      shopId: shopId,
      name: name,
      type: type,
      configJson: configJson,
      isActive: isActive,
      startAt: startAt,
      endAt: endAt,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    _offers.add(offer);
    return offer;
  }

  @override
  Future<Offer> updateOffer(Offer offer) async {
    final index = _offers.indexWhere((o) => o.id == offer.id);
    if (index == -1) throw StateError('Offer not found: ${offer.id}');
    _offers[index] = offer;
    return offer;
  }

  @override
  Future<void> deleteOffer(String id) async {
    _offers.removeWhere((o) => o.id == id);
  }
}