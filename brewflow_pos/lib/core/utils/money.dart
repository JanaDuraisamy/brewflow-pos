/// ---------------------------------------------------------------------------
/// BrewFlow POS — Money Utilities
///
/// Money is always stored as exact integer minor units (paise); floating
/// point is never used for currency. This file owns the safe conversions
/// between user input (rupees text) and paise, plus display formatting.
/// ---------------------------------------------------------------------------
library;

final class Money {
  Money._();

  /// Upper bound: ₹99,999,999.99 — far above any POS sensible price.
  static const int maxPaise = 9999999999;

  static final RegExp _rupeesPattern = RegExp(r'^\d{1,8}(\.\d{1,2})?$');

  /// Parses rupees input text ('149.50', '12', '0.05') into integer paise.
  ///
  /// Returns null for empty, malformed, negative or out-of-range input so
  /// callers (form validators) always end up with a safe value.
  static int? parseRupeesToPaise(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || !_rupeesPattern.hasMatch(trimmed)) {
      return null;
    }
    final parts = trimmed.split('.');
    final rupees = int.parse(parts.first);
    final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
    final paise = rupees * 100 + int.parse(fraction);
    if (paise > maxPaise) return null;
    return paise;
  }

  /// Rupees text for prefilling an input field from stored paise.
  static String paiseToRupeesInput(int paise) {
    final fraction = (paise % 100).toString().padLeft(2, '0');
    return '${paise ~/ 100}.$fraction';
  }

  /// Multiplies a unit price in paise by a whole quantity, rejecting inputs
  /// and results outside the safe range.
  ///
  /// Returns null when [paise] is negative, [quantity] is not positive, or
  /// the product would exceed [maxPaise] (integer overflow is impossible in
  /// Dart, but the POS ceiling must not be crossed).
  static int? multiplyPaise(int paise, int quantity) {
    if (paise < 0 || paise > maxPaise) return null;
    if (quantity <= 0 || quantity > maxPaise) return null;
    final product = paise * quantity;
    if (product > maxPaise) return null;
    return product;
  }

  /// Sums paise values, rejecting any sum above [maxPaise] with null so
  /// callers never surface an unbounded cart total.
  static int? sumPaise(Iterable<int> values) {
    var total = 0;
    for (final value in values) {
      if (value < 0 || value > maxPaise) return null;
      total += value;
      if (total > maxPaise) return null;
    }
    return total;
  }

  /// Formats paise as Indian-grouped currency text, e.g. '₹1,23,456.78'.
  static String formatPaise(int paise) {
    final fraction = (paise % 100).toString().padLeft(2, '0');
    return '₹${_groupIndian((paise ~/ 100).toString())}.$fraction';
  }

  static String _groupIndian(String digits) {
    if (digits.length <= 3) {
      return digits;
    }
    final tail = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[tail];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) {
      parts.insert(0, rest);
    }
    return parts.join(',');
  }
}
