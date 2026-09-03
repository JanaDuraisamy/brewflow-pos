/// ---------------------------------------------------------------------------
/// BrewFlow POS — Master-Data Sync Wire Models (domain)
///
/// The canonical, typed contract between any two devices through the cloud
/// mirror. Field lists mirror the local Drift tables EXACTLY except:
///
/// - `imagePath` is intentionally ABSENT everywhere: product images are
///   device-relative file paths today, so propagating them would fabricate
///   data other devices cannot open. Image/blob storage is a later phase;
///   the applier never overwrites a local image with a remote absence.
///
/// - Timestamps: clients send their true creation instant (`createdAt`);
///   the server records it as `client_created_at` while owning conflict
///   ordering itself via trigger-set `updated_at` (arrival order — see
///   supabase/migrations/0003_master_data_sync.sql).
///
/// Money stays integer paise. Enum fields travel as their DB string values.
/// ---------------------------------------------------------------------------
library;

/// Master-data entity keys, identical to the outbox `entity` values.
enum MasterEntity {
  shop('SHOP'),
  category('CATEGORY'),
  product('PRODUCT'),
  productVariant('PRODUCT_VARIANT'),
  supplier('SUPPLIER'),
  customer('CUSTOMER'),
  sale('SALE'),
  saleItem('SALE_ITEM'),
  expense('EXPENSE'),
  customerPayment('CUSTOMER_PAYMENT'),
  offer('OFFER');

  const MasterEntity(this.wire);
  final String wire;

  static MasterEntity fromWire(String value) => MasterEntity.values.firstWhere(
    (entity) => entity.wire == value,
    orElse: () => throw ArgumentError('Unknown master entity: $value'),
  );
}

// ---------------------------------------------------------------------------
// Shops — business identity (single-shop design, id must never change)
// ---------------------------------------------------------------------------

/// The shop row itself. Its [id] is the identity scope shared by every other
/// synced entity and must NEVER change; only the display [name] syncs.
///
/// [shopId] equals [id] because the shop is its own scope — this keeps the
/// outbox/gateway payload shape uniform with every other master entity.
final class SyncShop {
  const SyncShop({
    required this.id,
    required this.shopId,
    required this.name,
    required this.createdAt,
  });

  factory SyncShop.fromJson(Map<String, dynamic> json) => SyncShop(
    id: json['id'] as String,
    shopId: json['shopId'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String shopId;
  final String name;

  /// Original creation instant (device UTC).
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

final class SyncCategory {
  const SyncCategory({
    required this.id,
    required this.shopId,
    required this.name,
    required this.isActive,
    required this.createdAt,
  });

  factory SyncCategory.fromJson(Map<String, dynamic> json) => SyncCategory(
    id: json['id'] as String,
    shopId: json['shopId'] as String,
    name: json['name'] as String,
    isActive: json['isActive'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String shopId;
  final String name;
  final bool isActive;

  /// Creation instant from the OWNING device (UTC).
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'name': name,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Products
// ---------------------------------------------------------------------------

enum SyncStockUnit { count, ml, gram, kg, none }

extension SyncStockUnitWire on SyncStockUnit {
  String get wire => switch (this) {
    SyncStockUnit.count => 'COUNT',
    SyncStockUnit.ml => 'ML',
    SyncStockUnit.gram => 'GRAM',
    SyncStockUnit.kg => 'KG',
    SyncStockUnit.none => 'NONE',
  };

  static SyncStockUnit from(String value) => switch (value) {
    'COUNT' => SyncStockUnit.count,
    'ML' => SyncStockUnit.ml,
    'GRAM' => SyncStockUnit.gram,
    'KG' => SyncStockUnit.kg,
    'NONE' => SyncStockUnit.none,
    _ => throw ArgumentError('Unknown stock unit: $value'),
  };
}

enum SyncLowStockMode { useDefault, custom, off }

extension SyncLowStockModeWire on SyncLowStockMode {
  String get wire => switch (this) {
    SyncLowStockMode.useDefault => 'USE_DEFAULT',
    SyncLowStockMode.custom => 'CUSTOM',
    SyncLowStockMode.off => 'OFF',
  };

  static SyncLowStockMode from(String value) => switch (value) {
    'USE_DEFAULT' => SyncLowStockMode.useDefault,
    'CUSTOM' => SyncLowStockMode.custom,
    'OFF' => SyncLowStockMode.off,
    _ => throw ArgumentError('Unknown low-stock mode: $value'),
  };
}

final class SyncProduct {
  const SyncProduct({
    required this.id,
    required this.shopId,
    required this.categoryId,
    required this.name,
    this.sku,
    required this.sellingPricePaise,
    this.costPricePaise,
    required this.stockQuantity,
    required this.stockUnit,
    required this.lowStockMode,
    this.lowStockThreshold,
    required this.membershipEnabled,
    this.memberPricePaise,
    required this.isActive,
    required this.createdAt,
    this.cloudImagePath,
  });

  factory SyncProduct.fromJson(Map<String, dynamic> json) => SyncProduct(
    id: json['id'] as String,
    shopId: json['shopId'] as String,
    categoryId: json['categoryId'] as String,
    name: json['name'] as String,
    sku: json['sku'] as String?,
    sellingPricePaise: json['sellingPricePaise'] as int,
    costPricePaise: json['costPricePaise'] as int?,
    stockQuantity: json['stockQuantity'] as int,
    stockUnit: SyncStockUnitWire.from(json['stockUnit'] as String),
    lowStockMode: SyncLowStockModeWire.from(json['lowStockMode'] as String),
    lowStockThreshold: json['lowStockThreshold'] as int?,
    membershipEnabled: json['membershipEnabled'] as bool,
    memberPricePaise: json['memberPricePaise'] as int?,
    isActive: json['isActive'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
    cloudImagePath: json['cloudImagePath'] as String?,
  );

  final String id;
  final String shopId;
  final String categoryId;
  final String name;
  final String? sku;
  final int sellingPricePaise;
  final int? costPricePaise;

  /// Device-local stock snapshot; cross-device reconciliation is a later
  /// phase. Carried verbatim so a fresh device boots close to reality.
  final int stockQuantity;
  final SyncStockUnit stockUnit;
  final SyncLowStockMode lowStockMode;
  final int? lowStockThreshold;
  final bool membershipEnabled;
  final int? memberPricePaise;
  final bool isActive;
  final DateTime createdAt;

  /// Cloud object path (Supabase Storage) of the product image; null when no
  /// image is uploaded. This is metadata only — binary is never carried on
  /// the wire. Other devices read it to enqueue a local DOWNLOAD.
  final String? cloudImagePath;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'categoryId': categoryId,
    'name': name,
    'sku': sku,
    'sellingPricePaise': sellingPricePaise,
    'costPricePaise': costPricePaise,
    'stockQuantity': stockQuantity,
    'stockUnit': stockUnit.wire,
    'lowStockMode': lowStockMode.wire,
    'lowStockThreshold': lowStockThreshold,
    'membershipEnabled': membershipEnabled,
    'memberPricePaise': memberPricePaise,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
    'cloudImagePath': cloudImagePath,
  };
}

// ---------------------------------------------------------------------------
// Product variants
// ---------------------------------------------------------------------------

final class SyncProductVariant {
  const SyncProductVariant({
    required this.id,
    required this.shopId,
    required this.productId,
    required this.name,
    this.sku,
    required this.sellingPricePaise,
    this.costPricePaise,
    required this.stockQuantity,
    required this.lowStockMode,
    this.lowStockThreshold,
    required this.membershipEnabled,
    this.memberPricePaise,
    required this.isActive,
    required this.createdAt,
  });

  factory SyncProductVariant.fromJson(Map<String, dynamic> json) =>
      SyncProductVariant(
        id: json['id'] as String,
        shopId: json['shopId'] as String,
        productId: json['productId'] as String,
        name: json['name'] as String,
        sku: json['sku'] as String?,
        sellingPricePaise: json['sellingPricePaise'] as int,
        costPricePaise: json['costPricePaise'] as int?,
        stockQuantity: json['stockQuantity'] as int,
        lowStockMode: SyncLowStockModeWire.from(json['lowStockMode'] as String),
        lowStockThreshold: json['lowStockThreshold'] as int?,
        membershipEnabled: json['membershipEnabled'] as bool,
        memberPricePaise: json['memberPricePaise'] as int?,
        isActive: json['isActive'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String shopId;
  final String productId;
  final String name;
  final String? sku;
  final int sellingPricePaise;
  final int? costPricePaise;
  final int stockQuantity;
  final SyncLowStockMode lowStockMode;
  final int? lowStockThreshold;
  final bool membershipEnabled;
  final int? memberPricePaise;
  final bool isActive;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'productId': productId,
    'name': name,
    'sku': sku,
    'sellingPricePaise': sellingPricePaise,
    'costPricePaise': costPricePaise,
    'stockQuantity': stockQuantity,
    'lowStockMode': lowStockMode.wire,
    'lowStockThreshold': lowStockThreshold,
    'membershipEnabled': membershipEnabled,
    'memberPricePaise': memberPricePaise,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Suppliers
// ---------------------------------------------------------------------------

final class SyncSupplier {
  const SyncSupplier({
    required this.id,
    required this.shopId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    required this.isActive,
    required this.createdAt,
  });

  factory SyncSupplier.fromJson(Map<String, dynamic> json) => SyncSupplier(
    id: json['id'] as String,
    shopId: json['shopId'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    address: json['address'] as String?,
    notes: json['notes'] as String?,
    isActive: json['isActive'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String shopId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'notes': notes,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Customers — phone is canonical contact; WhatsApp status travels verbatim
// and is NEVER inferred or fabricated by sync.
// ---------------------------------------------------------------------------

final class SyncCustomer {
  const SyncCustomer({
    required this.id,
    required this.shopId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    required this.isActive,
    required this.membershipActive,
    this.membershipFeePaise,
    required this.whatsappStatus,
    required this.createdAt,
  });

  factory SyncCustomer.fromJson(Map<String, dynamic> json) => SyncCustomer(
    id: json['id'] as String,
    shopId: json['shopId'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    address: json['address'] as String?,
    isActive: json['isActive'] as bool,
    membershipActive: json['membershipActive'] as bool,
    membershipFeePaise: json['membershipFeePaise'] as int?,
    whatsappStatus: json['whatsappStatus'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String shopId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final bool isActive;
  final bool membershipActive;
  final int? membershipFeePaise;

  /// DB string value ('UNKNOWN' | 'VERIFIED' | 'NOT_VERIFIED' |
  /// 'UNAVAILABLE'). Kept as raw wire string here; repositories own the enum.
  final String whatsappStatus;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'isActive': isActive,
    'membershipActive': membershipActive,
    'membershipFeePaise': membershipFeePaise,
    'whatsappStatus': whatsappStatus,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// A hard deletion that happened on some device; pulled by all others.
final class SyncDeletion {
  const SyncDeletion({
    required this.entity,
    required this.id,
    required this.shopId,
  });

  final MasterEntity entity;
  final String id;
  final String shopId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'entity': entity.wire,
    'id': id,
    'shopId': shopId,
  };

  factory SyncDeletion.fromJson(Map<String, dynamic> json) => SyncDeletion(
    entity: MasterEntity.fromWire(json['entity'] as String),
    id: json['id'] as String,
    shopId: json['shopId'] as String,
  );
}

// ---------------------------------------------------------------------------
// Sales
// ---------------------------------------------------------------------------

final class SyncSale {
  const SyncSale({
    required this.id,
    required this.shopId,
    this.customerId,
    required this.receiptNumber,
    required this.subtotalPaise,
    required this.totalPaise,
    this.paymentMethod,
    required this.paymentStatus,
    required this.createdAt,
    this.voided = false,
    this.voidedAt,
    this.offerDiscountPaise = 0,
  });

  factory SyncSale.fromJson(Map<String, dynamic> json) => SyncSale(
    id: json['id'] as String,
    shopId: json['shopId'] as String,
    customerId: json['customerId'] as String?,
    receiptNumber: json['receiptNumber'] as String,
    subtotalPaise: json['subtotalPaise'] as int,
    totalPaise: json['totalPaise'] as int,
    paymentMethod: json['paymentMethod'] as String?,
    paymentStatus: json['paymentStatus'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    voided: json['voided'] as bool? ?? false,
    voidedAt: json['voidedAt'] != null
        ? DateTime.parse(json['voidedAt'] as String)
        : null,
    // Tolerant: payloads written before offer sync carry no discount field.
    offerDiscountPaise: json['offerDiscountPaise'] as int? ?? 0,
  );

  final String id;
  final String shopId;
  final String? customerId;
  final String receiptNumber;
  final int subtotalPaise;
  final int totalPaise;
  final String? paymentMethod;
  final String paymentStatus;
  final DateTime createdAt;
  final bool voided;
  final DateTime? voidedAt;

  /// Total offer discount on this sale in paise; 0 when no offer applied.
  final int offerDiscountPaise;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'customerId': customerId,
    'receiptNumber': receiptNumber,
    'subtotalPaise': subtotalPaise,
    'totalPaise': totalPaise,
    'paymentMethod': paymentMethod,
    'paymentStatus': paymentStatus,
    'createdAt': createdAt.toIso8601String(),
    'voided': voided,
    'voidedAt': voidedAt?.toIso8601String(),
    'offerDiscountPaise': offerDiscountPaise,
  };
}

// ---------------------------------------------------------------------------
// Sale Items
// ---------------------------------------------------------------------------

final class SyncSaleItem {
  const SyncSaleItem({
    required this.id,
    required this.shopId,
    required this.saleId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantName,
    this.sku,
    required this.unitPricePaise,
    required this.quantity,
    required this.lineTotalPaise,
    this.offerDiscountPaise = 0,
    this.appliedOfferId,
    this.appliedOfferName,
    this.appliedOfferType,
  });

  factory SyncSaleItem.fromJson(Map<String, dynamic> json) => SyncSaleItem(
    id: json['id'] as String,
    shopId: json['shopId'] as String,
    saleId: json['saleId'] as String,
    productId: json['productId'] as String,
    variantId: json['variantId'] as String?,
    productName: json['productName'] as String,
    variantName: json['variantName'] as String?,
    sku: json['sku'] as String?,
    unitPricePaise: json['unitPricePaise'] as int,
    quantity: json['quantity'] as int,
    lineTotalPaise: json['lineTotalPaise'] as int,
    // Tolerant: payloads written before offer sync carry no offer fields.
    offerDiscountPaise: json['offerDiscountPaise'] as int? ?? 0,
    appliedOfferId: json['appliedOfferId'] as String?,
    appliedOfferName: json['appliedOfferName'] as String?,
    appliedOfferType: json['appliedOfferType'] as String?,
  );

  final String id;
  final String shopId;
  final String saleId;
  final String productId;
  final String? variantId;
  final String productName;
  final String? variantName;
  final String? sku;
  final int unitPricePaise;
  final int quantity;
  final int lineTotalPaise;

  /// Offer discount on this line in paise; 0 when no offer applied.
  final int offerDiscountPaise;

  /// Identity of the applied offer (offer-table id, display name, wire
  /// type); all null when no offer applied.
  final String? appliedOfferId;
  final String? appliedOfferName;
  final String? appliedOfferType;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'saleId': saleId,
    'productId': productId,
    'variantId': variantId,
    'productName': productName,
    'variantName': variantName,
    'sku': sku,
    'unitPricePaise': unitPricePaise,
    'quantity': quantity,
    'lineTotalPaise': lineTotalPaise,
    'offerDiscountPaise': offerDiscountPaise,
    'appliedOfferId': appliedOfferId,
    'appliedOfferName': appliedOfferName,
    'appliedOfferType': appliedOfferType,
  };
}

// ---------------------------------------------------------------------------
// Expenses
// ---------------------------------------------------------------------------

final class SyncExpense {
  const SyncExpense({
    required this.id,
    required this.shopId,
    required this.name,
    required this.amountPaise,
    required this.category,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.expenseDate,
    this.note,
    required this.isActive,
    required this.createdAt,
  });

  factory SyncExpense.fromJson(Map<String, dynamic> json) => SyncExpense(
    id: json['id'] as String,
    shopId: json['shopId'] as String,
    name: json['name'] as String,
    amountPaise: json['amountPaise'] as int,
    category: json['category'] as String,
    paymentMethod: json['paymentMethod'] as String,
    paymentStatus: json['paymentStatus'] as String,
    expenseDate: DateTime.parse(json['expenseDate'] as String),
    note: json['note'] as String?,
    isActive: json['isActive'] as bool,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String shopId;
  final String name;
  final int amountPaise;
  final String category;
  final String paymentMethod;
  final String paymentStatus;
  final DateTime expenseDate;
  final String? note;
  final bool isActive;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'name': name,
    'amountPaise': amountPaise,
    'category': category,
    'paymentMethod': paymentMethod,
    'paymentStatus': paymentStatus,
    'expenseDate': expenseDate.toIso8601String(),
    'note': note,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Customer Payments
// ---------------------------------------------------------------------------

final class SyncCustomerPayment {
  const SyncCustomerPayment({
    required this.id,
    required this.shopId,
    required this.customerId,
    this.saleId,
    required this.amountPaise,
    required this.paymentMethod,
    this.note,
    required this.paidAt,
    required this.reversed,
    this.reversedAt,
    required this.createdAt,
  });

  factory SyncCustomerPayment.fromJson(Map<String, dynamic> json) =>
      SyncCustomerPayment(
        id: json['id'] as String,
        shopId: json['shopId'] as String,
        customerId: json['customerId'] as String,
        saleId: json['saleId'] as String?,
        amountPaise: json['amountPaise'] as int,
        paymentMethod: json['paymentMethod'] as String,
        note: json['note'] as String?,
        paidAt: DateTime.parse(json['paidAt'] as String),
        reversed: json['reversed'] as bool,
        reversedAt: json['reversedAt'] != null
            ? DateTime.parse(json['reversedAt'] as String)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String shopId;
  final String customerId;
  final String? saleId;
  final int amountPaise;
  final String paymentMethod;
  final String? note;
  final DateTime paidAt;
  final bool reversed;
  final DateTime? reversedAt;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'customerId': customerId,
    'saleId': saleId,
    'amountPaise': amountPaise,
    'paymentMethod': paymentMethod,
    'note': note,
    'paidAt': paidAt.toIso8601String(),
    'reversed': reversed,
    'reversedAt': reversedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Offers — business-scoped promotions (Cafe / Food Truck isolated)
// ---------------------------------------------------------------------------

final class SyncOffer {
  const SyncOffer({
    required this.id,
    required this.shopId,
    required this.name,
    required this.type,
    required this.configJson,
    required this.isActive,
    this.startAt,
    this.endAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SyncOffer.fromJson(Map<String, dynamic> json) => SyncOffer(
    id: json['id'] as String,
    shopId: json['shopId'] as String,
    name: json['name'] as String,
    type: json['type'] as String,
    configJson: json['configJson'] as String,
    isActive: json['isActive'] as bool,
    startAt: json['startAt'] != null
        ? DateTime.parse(json['startAt'] as String)
        : null,
    endAt: json['endAt'] != null
        ? DateTime.parse(json['endAt'] as String)
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  final String id;
  final String shopId;
  final String name;
  final String type;
  final String configJson;
  final bool isActive;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'shopId': shopId,
    'name': name,
    'type': type,
    'configJson': configJson,
    'isActive': isActive,
    'startAt': startAt?.toIso8601String(),
    'endAt': endAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
