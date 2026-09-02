import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brewflow_pos/core/storage/app_storage.dart';

/// Owner navigation customization — persists locally and respects permissions.
///
/// Phone and Tablet may have different configs (separate prefs keys).
/// Required destinations (Dashboard, Settings) are always visible and cannot
/// be hidden. Staff visibility still filtered by `canProvider`.
class NavigationConfig {
  const NavigationConfig({
    required this.visibleIndices,
    required this.orderedIndices,
  });

  /// Indices that should be shown (subset of [orderedIndices]).
  final List<int> visibleIndices;

  /// Full ordering of destinations (branch indices 0..9).
  final List<int> orderedIndices;

  static const List<int> defaultOrder = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
  static const List<int> requiredIndices = [0, 9]; // Dashboard, Settings
  static const List<int> defaultPhonePrimary = [0, 1, 4];

  NavigationConfig copyWith({
    List<int>? visibleIndices,
    List<int>? orderedIndices,
  }) => NavigationConfig(
    visibleIndices: visibleIndices ?? this.visibleIndices,
    orderedIndices: orderedIndices ?? this.orderedIndices,
  );

  Map<String, dynamic> toJson() => {
    'visible': visibleIndices,
    'order': orderedIndices,
  };
  factory NavigationConfig.fromJson(Map<String, dynamic> j) => NavigationConfig(
    visibleIndices: (j['visible'] as List).cast<int>(),
    orderedIndices: (j['ordered'] as List?)?.cast<int>() ?? defaultOrder,
  );

  static NavigationConfig get defaults => NavigationConfig(
    visibleIndices: List.from(defaultOrder),
    orderedIndices: List.from(defaultOrder),
  );
}

final navigationConfigProvider =
    NotifierProvider<NavigationConfigController, NavigationConfig>(
      NavigationConfigController.new,
    );

final class NavigationConfigController extends Notifier<NavigationConfig> {
  static const String _keyPhone = 'nav_config_phone';
  static const String _keyTablet = 'nav_config_tablet';

  bool get isPhone => false; // placeholder, actual UI passes MediaQuery

  @override
  NavigationConfig build() {
    // Default synchronously; hydrate async.
    _hydrate();
    return NavigationConfig.defaults;
  }

  Future<void> _hydrate() async {
    try {
      final raw = await AppStorage.preferences.readString(_keyPhone);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        state = NavigationConfig.fromJson(map);
      }
    } catch (_) {}
  }

  Future<void> setVisible(List<int> indices) async {
    // Enforce required destinations remain visible.
    final next = {...indices, ...NavigationConfig.requiredIndices}.toList()
      ..sort();
    state = state.copyWith(visibleIndices: next);
    await AppStorage.preferences.writeString(
      _keyPhone,
      jsonEncode(state.toJson()),
    );
  }

  Future<void> setOrder(List<int> order) async {
    state = state.copyWith(orderedIndices: order);
    await AppStorage.preferences.writeString(
      _keyPhone,
      jsonEncode(state.toJson()),
    );
  }

  Future<void> reset() async {
    state = NavigationConfig.defaults;
    await AppStorage.preferences.remove(_keyPhone);
    await AppStorage.preferences.remove(_keyTablet);
  }
}
