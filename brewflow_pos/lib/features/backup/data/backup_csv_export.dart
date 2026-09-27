/// ---------------------------------------------------------------------------
/// BrewFlow POS — CSV Data Export (export-only, NOT a restorable backup)
///
/// Renders one human/Excel-readable CSV document per business table from an
/// already shop-scoped [BackupEnvelope] (built by the backup repository, so
/// the selected shop/business context is respected by construction).
///
/// Every sheet keeps relationship identifiers (`id`, `shopId` and the
/// relevant foreign keys) so rows stay traceable across files. Values are
/// RFC-4180 quoted only when they need it (comma, quote, newline).
///
/// CSV is a readable export, never a backup: it carries no envelope header,
/// no checksum and no settings, and restore never accepts it.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/backup/domain/backup_models.dart';

/// One exported sheet: file name plus its CSV text.
final class CsvSheet {
  const CsvSheet({required this.fileName, required this.content});

  final String fileName;
  final String content;
}

/// Column spec: header label plus the row-map key it reads.
typedef _CsvColumn = ({String header, String key});

/// Builds every CSV sheet for [envelope]. Tables without rows still produce
/// a headers-only sheet so the export shape is stable.
List<CsvSheet> buildCsvExport(BackupEnvelope envelope) {
  final tables = envelope.tables;
  return [
    _sheet('categories.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'name', key: 'name'),
      (header: 'is_active', key: 'isActive'),
    ], tables.categories),
    _sheet('products.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'category_id', key: 'categoryId'),
      (header: 'name', key: 'name'),
      (header: 'sku', key: 'sku'),
      (header: 'selling_price_paise', key: 'sellingPricePaise'),
      (header: 'cost_price_paise', key: 'costPricePaise'),
      (header: 'stock_quantity', key: 'stockQuantity'),
      (header: 'is_active', key: 'isActive'),
    ], tables.products),
    _sheet('product_variants.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'product_id', key: 'productId'),
      (header: 'name', key: 'name'),
      (header: 'selling_price_paise', key: 'sellingPricePaise'),
      (header: 'stock_quantity', key: 'stockQuantity'),
    ], tables.productVariants),
    _sheet('customers.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'name', key: 'name'),
      (header: 'phone', key: 'phone'),
      (header: 'email', key: 'email'),
      (header: 'is_active', key: 'isActive'),
    ], tables.customers),
    _sheet('sales.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'customer_id', key: 'customerId'),
      (header: 'receipt_number', key: 'receiptNumber'),
      (header: 'total_paise', key: 'totalPaise'),
      (header: 'payment_method', key: 'paymentMethod'),
      (header: 'payment_status', key: 'paymentStatus'),
      (header: 'created_at', key: 'createdAt'),
    ], tables.sales),
    _sheet('sale_items.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'sale_id', key: 'saleId'),
      (header: 'product_id', key: 'productId'),
      (header: 'product_name', key: 'productName'),
      (header: 'quantity', key: 'quantity'),
      (header: 'unit_price_paise', key: 'unitPricePaise'),
      (header: 'line_total_paise', key: 'lineTotalPaise'),
    ], tables.saleItems),
    _sheet('customer_payments.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'customer_id', key: 'customerId'),
      (header: 'sale_id', key: 'saleId'),
      (header: 'amount_paise', key: 'amountPaise'),
      (header: 'payment_method', key: 'paymentMethod'),
      (header: 'paid_at', key: 'paidAt'),
    ], tables.customerPayments),
    _sheet('suppliers.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'name', key: 'name'),
      (header: 'phone', key: 'phone'),
      (header: 'is_active', key: 'isActive'),
    ], tables.suppliers),
    _sheet('purchases.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'supplier_id', key: 'supplierId'),
      (header: 'total_paise', key: 'totalPaise'),
      (header: 'payment_status', key: 'paymentStatus'),
      (header: 'created_at', key: 'createdAt'),
    ], tables.purchases),
    _sheet('purchase_items.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'purchase_id', key: 'purchaseId'),
      (header: 'product_id', key: 'productId'),
      (header: 'quantity', key: 'quantity'),
      (header: 'unit_cost_paise', key: 'unitCostPaise'),
    ], tables.purchaseItems),
    _sheet('expenses.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'name', key: 'name'),
      (header: 'amount_paise', key: 'amountPaise'),
      (header: 'category', key: 'category'),
      (header: 'expense_date', key: 'expenseDate'),
    ], tables.expenses),
    _sheet('stock_movements.csv', const [
      (header: 'id', key: 'id'),
      (header: 'shop_id', key: 'shopId'),
      (header: 'product_id', key: 'productId'),
      (header: 'movement_type', key: 'movementType'),
      (header: 'quantity', key: 'quantity'),
      (header: 'reference_id', key: 'referenceId'),
      (header: 'created_at', key: 'createdAt'),
    ], tables.stockMovements),
  ];
}

CsvSheet _sheet(
  String fileName,
  List<_CsvColumn> columns,
  List<Map<String, dynamic>> rows,
) {
  final buffer = StringBuffer();
  buffer.writeln(columns.map((c) => _escape(c.header)).join(','));
  for (final row in rows) {
    buffer.writeln(columns.map((c) => _escape(_cell(row[c.key]))).join(','));
  }
  return CsvSheet(fileName: fileName, content: buffer.toString());
}

String _cell(Object? value) {
  if (value == null) return '';
  if (value is bool) return value ? 'true' : 'false';
  return value.toString();
}

/// Quotes a field only when it contains a comma, quote, newline or leading /
/// trailing whitespace — plain numbers and simple text stay bare for Excel.
String _escape(String value) {
  if (value.isEmpty) return '';
  final needsQuotes =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r') ||
      value.startsWith(' ') ||
      value.startsWith('\t') ||
      value.endsWith(' ') ||
      value.endsWith('\t');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}
