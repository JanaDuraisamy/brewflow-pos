import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/reports/domain/management_report_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart'
    show formatHoursMinutes;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Management Report (PDF, export-only)
///
/// A professional, reader-ready date-range report: shop identity + range in
/// the header, then Sales Summary, Expense Summary (full ledger + totals),
/// Staff Salary Details and Daily Closing Summary (records + cash-taken
/// aggregation). Built purely from a [ManagementReportData] value, so nothing
/// here touches repositories, auth or the database.
///
/// Money is rendered in INR with the bundled Inter ttf font (so the ₹ glyph
/// prints correctly). When the font cannot be embedded (e.g. headless tests
/// without an asset bundle) the builder falls back to built-in PDF fonts and
/// prints 'Rs.' — the same ASCII convention the receipt encoder uses.
/// ---------------------------------------------------------------------------

/// Lazily embedded feature font (Inter carries the ₹ glyph). Loaded once per
/// process; on any failure the builder falls back to default PDF fonts.
final class _PdfFonts {
  _PdfFonts._();

  static pw.Font? regular;
  static pw.Font? bold;
  static bool _attempted = false;

  static Future<void> ensure() async {
    if (_attempted) return;
    _attempted = true;
    try {
      regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
      );
      bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    } on Object {
      regular = null;
      bold = null;
    }
  }
}

/// Builds the management report PDF bytes for [data].
Future<Uint8List> buildManagementReportPdf(ManagementReportData data) async {
  await _PdfFonts.ensure();
  final theme = _PdfFonts.regular == null
      ? pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        )
      : pw.ThemeData.withFont(
          base: _PdfFonts.regular!,
          bold: _PdfFonts.bold ?? _PdfFonts.regular,
        );

  /// ₹ renders only inside the embedded Inter fonts; fall back to 'Rs. '.
  String money(int paise) {
    final formatted = Money.formatPaise(paise);
    return _PdfFonts.regular == null
        ? formatted.replaceAll('₹', 'Rs. ')
        : formatted;
  }

  final fromLabel = DateFormat('d MMM yyyy').format(data.fromLocal);
  final toLabel = DateFormat('d MMM yyyy').format(data.toLocal);
  final generatedAt = DateFormat(
    'd MMM yyyy, HH:mm',
  ).format(DateTime.now().toLocal());

  final doc = pw.Document(
    title: '${data.shopName} — Management Report',
    author: 'BrewFlow POS',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: theme,
      header: (context) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
          ),
        ),
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              data.shopName,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Management Report',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Divider(color: PdfColors.grey300, height: 0.8),
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated $generatedAt',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ],
      ),
      build: (context) => [
        pw.SizedBox(height: 6),
        pw.Text(
          'Management Report',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${data.shopName} · ${data.businessLabel}',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'From $fromLabel to $toLabel',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 16),
        ..._salesSection(data, money),
        ..._customerOutstandingSection(data, money),
        ..._expenseSection(data, money),
        ..._staffSection(data, money),
        ..._closingSection(data, money),
      ],
    ),
  );
  return doc.save();
}

List<pw.Widget> _salesSection(
  ManagementReportData data,
  String Function(int) money,
) {
  return [
    _sectionTitle('Sales Summary'),
    if (data.salesTotalPaise == 0) _muted('No sales recorded in this range.'),
    _summaryLine('Total Sales', money(data.salesTotalPaise), emphasize: true),
    _summaryLine('Total Cash', money(data.salesCashPaise)),
    _summaryLine('Total UPI', money(data.salesUpiPaise)),
    pw.SizedBox(height: 16),
  ];
}

List<pw.Widget> _customerOutstandingSection(
  ManagementReportData data,
  String Function(int) money,
) {
  final rows = [
    for (final row in data.customerOutstandingRows)
      [row.name, _textOrDash(row.phone), money(row.outstandingPaise)],
  ];
  return [
    _sectionTitle('Customer Outstanding'),
    if (rows.isEmpty)
      _muted('No customer outstanding balance.')
    else
      ..._chunkedTable(
        ['Customer', 'Phone', 'Outstanding'],
        rows,
        alignments: const [
          pw.Alignment.centerLeft,
          pw.Alignment.centerLeft,
          pw.Alignment.centerRight,
        ],
      ),
    pw.SizedBox(height: 8),
    _summaryLine(
      'Total Customer Outstanding',
      money(data.customerOutstandingTotalPaise),
      emphasize: true,
    ),
    pw.SizedBox(height: 16),
  ];
}

List<pw.Widget> _expenseSection(
  ManagementReportData data,
  String Function(int) money,
) {
  final rows = [
    for (final expense in data.expenseRows)
      [
        DateFormat('d MMM yyyy').format(expense.date),
        expense.name,
        money(expense.amountPaise),
        expense.paymentLabel,
      ],
  ];
  return [
    _sectionTitle('Expense Summary (${data.expenseRows.length})'),
    if (rows.isEmpty)
      _muted('No expenses recorded in this range.')
    else ...[
      ..._chunkedTable(
        ['Date', 'Expense', 'Amount', 'Payment Status/Method'],
        rows,
        alignments: const [
          pw.Alignment.centerLeft,
          pw.Alignment.centerLeft,
          pw.Alignment.centerRight,
          pw.Alignment.centerLeft,
        ],
      ),
      pw.SizedBox(height: 8),
    ],
    _summaryLine(
      'Total Expense',
      money(data.expenseTotalPaise),
      emphasize: true,
    ),
    _summaryLine('Total Cash', money(data.expenseCashPaise)),
    _summaryLine('Total UPI', money(data.expenseUpiPaise)),
    if (data.expenseBankPaise > 0)
      _summaryLine('Total Bank', money(data.expenseBankPaise)),
    _summaryLine('Total Not Paid', money(data.expenseNotPaidPaise)),
    pw.SizedBox(height: 16),
  ];
}

List<pw.Widget> _staffSection(
  ManagementReportData data,
  String Function(int) money,
) {
  final rows = [
    for (final staff in data.staffRows)
      [
        staff.name,
        formatHoursMinutes(staff.totalMinutes),
        money(staff.salaryPaise),
        money(staff.advancePaise),
      ],
  ];
  return [
    _sectionTitle('Staff Salary Details'),
    if (rows.isEmpty)
      _muted('No staff salary data recorded in this range.')
    else
      ..._chunkedTable(
        ['Staff', 'Total Working Hours', 'Total Salary', 'Total Advance'],
        rows,
        alignments: const [
          pw.Alignment.centerLeft,
          pw.Alignment.centerRight,
          pw.Alignment.centerRight,
          pw.Alignment.centerRight,
        ],
      ),
    pw.SizedBox(height: 16),
  ];
}

List<pw.Widget> _closingSection(
  ManagementReportData data,
  String Function(int) money,
) {
  final closingRows = [
    for (final closing in data.closings)
      [
        DateFormat('d MMM yyyy').format(closing.businessDate),
        money(closing.totalCashPaise),
        money(closing.totalUpiPaise),
        money(closing.totalSalesPaise),
        money(closing.totalExpensePaise),
        money(closing.cashLeftInBoxPaise),
        money(closing.cashTakenOutPaise),
        _textOrDash(closing.takenOutBy),
      ],
  ];
  final takenByRows = [
    for (final row in data.takenByRows)
      [row.name, '${row.daysTaken}', money(row.totalPaise)],
  ];
  return [
    _sectionTitle('Daily Closing Summary'),
    if (closingRows.isEmpty)
      _muted('No closing records in this range.')
    else
      ..._chunkedTable(
        const [
          'Date',
          'Cash',
          'UPI',
          'Sales',
          'Expense',
          'Cash Left',
          'Cash Taken',
          'Taken By',
        ],
        closingRows,
        alignments: const [
          pw.Alignment.centerLeft,
          pw.Alignment.centerRight,
          pw.Alignment.centerRight,
          pw.Alignment.centerRight,
          pw.Alignment.centerRight,
          pw.Alignment.centerRight,
          pw.Alignment.centerRight,
          pw.Alignment.centerLeft,
        ],
        chunkSize: 12,
      ),
    pw.SizedBox(height: 10),
    pw.Text(
      'Cash taken from the box — by staff',
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 4),
    if (takenByRows.isEmpty)
      _muted('No cash taken out recorded in this range.')
    else
      ..._chunkedTable(
        ['Staff', 'Days Taken', 'Total Taken'],
        takenByRows,
        alignments: const [
          pw.Alignment.centerLeft,
          pw.Alignment.centerRight,
          pw.Alignment.centerRight,
        ],
        chunkSize: 12,
      ),
  ];
}

pw.Widget _sectionTitle(String title) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 6),
  child: pw.Text(
    title,
    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
  ),
);

pw.Widget _muted(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Text(
    text,
    style: const pw.TextStyle(
      fontSize: 9.5,
      color: PdfColors.grey600,
      fontStyle: pw.FontStyle.italic,
    ),
  ),
);

pw.Widget _summaryLine(String label, String value, {bool emphasize = false}) {
  final labelStyle = pw.TextStyle(
    fontSize: 10,
    color: PdfColors.grey800,
    fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  final valueStyle = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label, style: labelStyle)),
        pw.Text(value, style: valueStyle),
      ],
    ),
  );
}

/// Splits a large table into chunks so the PDF engine always gets
/// page-fittable widgets and the header repeats per chunk.
List<pw.Widget> _chunkedTable(
  List<String> headers,
  List<List<String>> rows, {
  List<pw.Alignment>? alignments,
  int chunkSize = 16,
}) {
  final widgets = <pw.Widget>[];
  for (var start = 0; start < rows.length; start += chunkSize) {
    final end = (start + chunkSize) < rows.length
        ? start + chunkSize
        : rows.length;
    widgets.add(
      _table(headers, rows.sublist(start, end), alignments: alignments),
    );
    if (end < rows.length) {
      widgets.add(pw.SizedBox(height: 10));
    }
  }
  return widgets;
}

pw.Widget _table(
  List<String> headers,
  List<List<String>> rows, {
  List<pw.Alignment>? alignments,
}) {
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerCount: 1,
    cellAlignments: {
      for (var column = 0; column < headers.length; column++)
        column: (alignments != null && column < alignments.length)
            ? alignments[column]
            : pw.Alignment.centerLeft,
    },
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 8.5),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    headerPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
    rowDecoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
    ),
  );
}

String _textOrDash(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? '—' : trimmed;
}

/// Human-safe default export name for the management report (local time):
/// `jiggartea_bill_management_report_YYYYMMDD_HHMMSS.pdf`.
String defaultManagementReportFileName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = time.toLocal();
  final stamp =
      '${local.year}'
      '${two(local.month)}'
      '${two(local.day)}'
      '_'
      '${two(local.hour)}'
      '${two(local.minute)}'
      '${two(local.second)}';
  return 'jiggartea_bill_management_report_$stamp.pdf';
}
