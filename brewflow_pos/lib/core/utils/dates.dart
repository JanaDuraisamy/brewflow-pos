/// ---------------------------------------------------------------------------
/// BrewFlow POS — Date & Time Display
///
/// The single place that turns UTC instants into display text. Storage and
/// comparisons always use UTC (see the sales schema); conversion to local
/// time happens only here, at the presentation edge. Formats use intl's
/// built-in default locale data, so no async locale initialization is
/// required anywhere in the app.
/// ---------------------------------------------------------------------------
library;

import 'package:intl/intl.dart';

/// 'd MMM yyyy, h:mm a', e.g. '10 Aug 2026, 9:47 AM'.
String formatDateTime(DateTime utc) =>
    DateFormat('d MMM yyyy, h:mm a').format(utc.toLocal());

/// 'd MMM yyyy', e.g. '10 Aug 2026'.
String formatDate(DateTime utc) =>
    DateFormat('d MMM yyyy').format(utc.toLocal());
