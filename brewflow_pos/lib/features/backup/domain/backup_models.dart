/// ---------------------------------------------------------------------------
/// BrewFlow POS — Backup & Restore Domain Models
///
/// A backup is a versioned JSON envelope that carries every business table
/// (as Drift row JSON maps) plus the non-sensitive [ShopSettings]. It never
/// carries auth/user/device/sync rows or secrets — those stay behind, so a
/// restored device keeps its own identities.
///
/// [BackupEnvelope.fromJsonString] only validates the envelope header and the
/// table containers; individual rows are decoded lazily during restore so a
/// bad row fails atomically inside the replace transaction.
/// ---------------------------------------------------------------------------
library;

import 'dart:convert';

import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';

import 'backup_failures.dart';

/// Wire identifier of a BrewFlow backup document.
const String kBackupFormat = 'brewflow.backup';

/// Version of the envelope layout (header + container shape). Bump this when
/// the envelope shape changes; mismatched versions are rejected on restore.
const int kBackupVersion = 1;

/// The business tables carried by a backup, as the raw row maps produced by
/// the Drift `toJson()` codecs. Missing keys decode to empty lists so older
/// envelopes stay readable; wrong-typed values fail as [CorruptBackupFailure].
final class BackupTables {
  const BackupTables({
    this.categories = const [],
    this.products = const [],
    this.productVariants = const [],
    this.customers = const [],
    this.customerPayments = const [],
    this.expenses = const [],
    this.sales = const [],
    this.saleItems = const [],
    this.suppliers = const [],
    this.purchases = const [],
    this.purchaseItems = const [],
    this.stockMovements = const [],
    this.saleSequences = const [],
    this.purchaseSequences = const [],
  });

  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> productVariants;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> customerPayments;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> sales;
  final List<Map<String, dynamic>> saleItems;
  final List<Map<String, dynamic>> suppliers;
  final List<Map<String, dynamic>> purchases;
  final List<Map<String, dynamic>> purchaseItems;
  final List<Map<String, dynamic>> stockMovements;
  final List<Map<String, dynamic>> saleSequences;
  final List<Map<String, dynamic>> purchaseSequences;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'categories': categories,
    'products': products,
    'productVariants': productVariants,
    'customers': customers,
    'customerPayments': customerPayments,
    'expenses': expenses,
    'sales': sales,
    'saleItems': saleItems,
    'suppliers': suppliers,
    'purchases': purchases,
    'purchaseItems': purchaseItems,
    'stockMovements': stockMovements,
    'saleSequences': saleSequences,
    'purchaseSequences': purchaseSequences,
  };

  factory BackupTables.fromJson(Map<String, dynamic> json) => BackupTables(
    categories: _rows(json['categories']),
    products: _rows(json['products']),
    productVariants: _rows(json['productVariants']),
    customers: _rows(json['customers']),
    customerPayments: _rows(json['customerPayments']),
    expenses: _rows(json['expenses']),
    sales: _rows(json['sales']),
    saleItems: _rows(json['saleItems']),
    suppliers: _rows(json['suppliers']),
    purchases: _rows(json['purchases']),
    purchaseItems: _rows(json['purchaseItems']),
    stockMovements: _rows(json['stockMovements']),
    saleSequences: _rows(json['saleSequences']),
    purchaseSequences: _rows(json['purchaseSequences']),
  );

  static List<Map<String, dynamic>> _rows(dynamic value) {
    if (value == null) return const [];
    if (value is! List) throw const CorruptBackupFailure();
    return [
      for (final item in value)
        if (item is Map<String, dynamic>)
          Map<String, dynamic>.from(item)
        else
          throw const CorruptBackupFailure(),
    ];
  }

  BackupSummary get summary => BackupSummary(
    categories: categories.length,
    products: products.length,
    productVariants: productVariants.length,
    customers: customers.length,
    customerPayments: customerPayments.length,
    expenses: expenses.length,
    sales: sales.length,
    saleItems: saleItems.length,
    suppliers: suppliers.length,
    purchases: purchases.length,
    purchaseItems: purchaseItems.length,
    stockMovements: stockMovements.length,
    saleSequences: saleSequences.length,
    purchaseSequences: purchaseSequences.length,
  );
}

/// Human-readable row counts of one backup.
final class BackupSummary {
  const BackupSummary({
    required this.categories,
    required this.products,
    required this.productVariants,
    required this.customers,
    required this.customerPayments,
    required this.expenses,
    required this.sales,
    required this.saleItems,
    required this.suppliers,
    required this.purchases,
    required this.purchaseItems,
    required this.stockMovements,
    required this.saleSequences,
    required this.purchaseSequences,
  });

  final int categories;
  final int products;
  final int productVariants;
  final int customers;
  final int customerPayments;
  final int expenses;
  final int sales;
  final int saleItems;
  final int suppliers;
  final int purchases;
  final int purchaseItems;
  final int stockMovements;
  final int saleSequences;
  final int purchaseSequences;

  int get total =>
      categories +
      products +
      productVariants +
      customers +
      customerPayments +
      expenses +
      sales +
      saleItems +
      suppliers +
      purchases +
      purchaseItems +
      stockMovements +
      saleSequences +
      purchaseSequences;
}

/// The full, versioned backup document.
final class BackupEnvelope {
  BackupEnvelope({
    required this.shopId,
    required this.tables,
    DateTime? createdAt,
    this.sourceDeviceId,
    this.settingsJson = const {},
    this.schemaVersion = AppConstants.databaseSchemaVersion,
    this.format = kBackupFormat,
    this.backupVersion = kBackupVersion,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  final String format;
  final int backupVersion;
  final DateTime createdAt;

  /// Installation that produced the backup; informational only.
  final String? sourceDeviceId;

  /// The shop the backup belongs to. Restore is rejected when this does not
  /// match the current shop row.
  final String shopId;

  /// Database schema version the data was exported from.
  final int schemaVersion;

  /// Serialized, non-sensitive [ShopSettings] values.
  final Map<String, dynamic> settingsJson;

  final BackupTables tables;

  BackupSummary get summary => tables.summary;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': format,
    'backupVersion': backupVersion,
    'createdAt': createdAt.toIso8601String(),
    if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
    'shopId': shopId,
    'schemaVersion': schemaVersion,
    'settings': settingsJson,
    'data': tables.toJson(),
  };

  /// Encodes the envelope as a single JSON string ready for file/share.
  String encodeJson() => const JsonEncoder().convert(toJson());

  /// Parses and structurally validates a raw backup JSON string.
  ///
  /// Throws [InvalidBackupFormatFailure] when the document is not a BrewFlow
  /// backup, [IncompatibleBackupSchemaFailure] for a newer envelope layout,
  /// and [CorruptBackupFailure] for damaged content.
  factory BackupEnvelope.fromJsonString(String raw) {
    final Object? decoded;
    try {
      decoded = const JsonDecoder().convert(raw);
    } on FormatException {
      throw const CorruptBackupFailure();
    }
    if (decoded is! Map<String, dynamic>) {
      throw const CorruptBackupFailure();
    }
    return BackupEnvelope.fromJson(decoded);
  }

  factory BackupEnvelope.fromJson(Map<String, dynamic> json) {
    if (json['format'] != kBackupFormat) {
      throw const InvalidBackupFormatFailure();
    }
    if (json['backupVersion'] != kBackupVersion) {
      throw const IncompatibleBackupSchemaFailure();
    }
    final shopId = json['shopId'];
    if (shopId is! String || shopId.trim().isEmpty) {
      throw const CorruptBackupFailure();
    }
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw const CorruptBackupFailure();
    }
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const CorruptBackupFailure();
    }
    final settingsJson = json['settings'];
    if (settingsJson is! Map<String, dynamic>) {
      // A backup without settings is still restorable, but a damaged
      // settings block is corruption, not a valid empty document.
      if (settingsJson != null) throw const CorruptBackupFailure();
    }
    final createdRaw = json['createdAt'];
    return BackupEnvelope(
      shopId: shopId,
      schemaVersion: schemaVersion,
      sourceDeviceId: _optionalText(json['sourceDeviceId']),
      settingsJson: Map<String, dynamic>.from(settingsJson ?? const {}),
      createdAt: createdRaw is String
          ? (DateTime.tryParse(createdRaw) ?? DateTime.now().toUtc())
          : DateTime.now().toUtc(),
      tables: BackupTables.fromJson(data),
    );
  }

  static String? _optionalText(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Serializes the non-sensitive [ShopSettings] into the backup envelope.
/// Keys mirror the settings model field names, never preference storage keys.
Map<String, dynamic> shopSettingsToJson(ShopSettings settings) =>
    <String, dynamic>{
      'shopName': settings.shopName,
      'appDisplayName': settings.appDisplayName,
      if (settings.ownerName != null) 'ownerName': settings.ownerName,
      if (settings.phone != null) 'phone': settings.phone,
      if (settings.email != null) 'email': settings.email,
      if (settings.address != null) 'address': settings.address,
      'lowStockThreshold': settings.lowStockThreshold,
      'theme': settings.theme.name,
      'membershipEnabled': settings.membershipEnabled,
    };

/// Rebuilds [ShopSettings] from a backup block; returns `null` when the block
/// is absent or too damaged to trust. Field-level fallbacks mirror
/// [ShopSettings.defaults] so a bad value degrades instead of crashing.
ShopSettings? shopSettingsFromJson(Map<String, dynamic> json) {
  final shopName = json['shopName'];
  if (shopName is! String || shopName.trim().isEmpty) return null;
  final threshold = json['lowStockThreshold'];
  final themeName = json['theme'];
  return ShopSettings(
    shopName: shopName,
    appDisplayName: _textOr(
      json['appDisplayName'],
      fallback: AppConstants.defaultAppDisplayName,
    ),
    ownerName: _textOrNull(json['ownerName']),
    phone: _textOrNull(json['phone']),
    email: _textOrNull(json['email']),
    address: _textOrNull(json['address']),
    lowStockThreshold: threshold is int && threshold > 0
        ? threshold
        : ShopSettings.defaultLowStockThreshold,
    theme:
        ThemePreference.values.asNameMap()[themeName] ??
        ShopSettings.defaultTheme,
    membershipEnabled: json['membershipEnabled'] is bool
        ? json['membershipEnabled'] as bool
        : ShopSettings.defaultMembershipEnabled,
  );
}

String _textOr(dynamic value, {required String fallback}) {
  final text = _textOrNull(value);
  return text ?? fallback;
}

String? _textOrNull(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
