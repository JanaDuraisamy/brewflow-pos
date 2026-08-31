import 'dart:async';

import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';

/// In-memory [PurchaseRepository] for tests.
///
/// Mirrors the Drift repository semantics that matter to state and UI:
/// newest-first ordering, sequential PUR numbers, snapshot items synthesized
/// from the submitted lines, and safe failures. Probe hooks ([loadError],
/// [loadGate], [receiveError], [receiveGate]) drive loading and error states.
final class FakePurchasesRepository implements PurchaseRepository {
  /// Stored purchases, newest first.
  final List<Purchase> storedPurchases = [];

  /// Snapshot items keyed by purchase id.
  final Map<String, List<PurchaseItem>> storedItems = {};

  /// Variant display names used to snapshot variant lines; the Drift
  /// repository resolves them from the database at receive time, so tests
  /// seed this map to mirror that behavior.
  final Map<String, String> variantNames = {};

  /// When set, every load throws this error instead of running.
  Object? loadError;

  /// When set, [purchases] waits for this (loading-state tests).
  Completer<void>? loadGate;

  /// Number of [purchases] calls.
  int purchasesCalls = 0;

  /// When set, [receivePurchase] throws it (no purchase is written).
  Object? receiveError;

  /// When set, [receivePurchase] waits for this before writing.
  Completer<void>? receiveGate;

  /// Number of [receivePurchase] calls.
  int receiveCalls = 0;

  /// The last successfully submitted lines / supplier / notes.
  List<PurchaseLine> lastLines = const [];
  String? lastSupplierId;
  String? lastNotes;

  /// Ids that have been voided via [voidPurchase].
  final Set<String> voidedIds = {};

  Future<void> _gate() async {
    final gate = loadGate;
    if (gate != null) {
      await gate.future;
    }
  }

  void _throwIfLoadError() {
    final error = loadError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<List<Purchase>> purchases() async {
    purchasesCalls += 1;
    await _gate();
    _throwIfLoadError();
    return List<Purchase>.of(storedPurchases);
  }

  @override
  Future<Purchase?> purchaseById(String id) async {
    _throwIfLoadError();
    for (final purchase in storedPurchases) {
      if (purchase.id == id) {
        return purchase;
      }
    }
    return null;
  }

  @override
  Future<List<PurchaseItem>> purchaseItems(String purchaseId) async {
    _throwIfLoadError();
    return List<PurchaseItem>.of(storedItems[purchaseId] ?? const []);
  }

  @override
  Future<Purchase> receivePurchase({
    required List<PurchaseLine> lines,
    String? supplierId,
    String? notes,
  }) async {
    receiveCalls += 1;
    final gate = receiveGate;
    if (gate != null) {
      await gate.future;
    }
    final error = receiveError;
    if (error != null) {
      throw error;
    }
    lastLines = lines;
    lastSupplierId = supplierId;
    lastNotes = notes;

    final subtotal = lines.fold(
      0,
      (sum, line) => sum + line.unitCostPaise * line.quantity,
    );
    final now = DateTime.now().toUtc();
    final purchase = Purchase(
      id: 'purchase-${storedPurchases.length + 1}',
      supplierId: supplierId,
      purchaseNumber:
          'PUR-${(storedPurchases.length + 1).toString().padLeft(6, '0')}',
      subtotalPaise: subtotal,
      totalPaise: subtotal,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    storedPurchases.insert(0, purchase);
    storedItems[purchase.id] = [
      for (var i = 0; i < lines.length; i++)
        PurchaseItem(
          id: 'item-${purchase.id}-$i',
          purchaseId: purchase.id,
          productId: lines[i].productId,
          productName: 'Product ${lines[i].productId}',
          variantId: lines[i].variantId,
          variantName: lines[i].variantId == null
              ? null
              : variantNames[lines[i].variantId],
          sku: null,
          unitCostPaise: lines[i].unitCostPaise,
          quantity: lines[i].quantity,
          lineTotalPaise: lines[i].unitCostPaise * lines[i].quantity,
        ),
    ];
    return purchase;
  }

  @override
  Future<void> voidPurchase(String id) async {
    _throwIfLoadError();
    if (!storedPurchases.any((p) => p.id == id)) {
      throw const UnexpectedPurchasesFailure('Purchase not found.');
    }
    storedPurchases.removeWhere((p) => p.id == id);
    storedItems.remove(id);
    voidedIds.add(id);
  }
}
