// ignore_for_file: unused_element_parameter

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';

class OffersPage extends ConsumerWidget {
  const OffersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessSwitcherProvider);
    final offersAsync = ref.watch(offersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offers'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            child: SegmentedButton<BusinessContext>(
              segments: const [
                ButtonSegment(value: BusinessContext.cafe, label: Text('Cafe')),
                ButtonSegment(
                  value: BusinessContext.foodTruck,
                  label: Text('Food Truck'),
                ),
              ],
              selected: {
                business == BusinessContext.all
                    ? BusinessContext.cafe
                    : business,
              },
              onSelectionChanged: (s) =>
                  ref.read(businessSwitcherProvider.notifier).select(s.first),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.local_offer_outlined),
        label: const Text('New Offer'),
      ),
      body: offersAsync.when(
        loading: () => const LoadingState(message: 'Loading offers…'),
        error: (e, _) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(offersProvider),
        ),
        data: (offers) {
          if (offers.isEmpty) {
            return EmptyState(
              icon: Icons.local_offer_outlined,
              title: 'No offers yet',
              message:
                  'Create a percentage, combo or Buy X Get Y offer for ${business.label}.',
            );
          }
          return ListView.separated(
            padding: AppInsets.screen,
            itemCount: offers.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final o = offers[i];
              return ListTile(
                title: Text(
                  o.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${o.type.wire} · ${o.isActive ? "Active" : "Inactive"}${o.isCurrentlyActive ? "" : " (scheduled)"}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: o.isActive,
                      onChanged: (_) =>
                          ref.read(offersControllerProvider).toggleActive(o),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(context, ref, o),
                    ),
                  ],
                ),
                onTap: () => _showEditDialog(context, ref, o),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final shopId = await _dialogShopId(ref);
    if (shopId == null || !context.mounted) return;
    final result = await showDialog<_OfferDraft>(
      context: context,
      builder: (_) => _OfferDialog(shopId: shopId),
    );
    if (result == null) return;
    try {
      await ref
          .read(offersControllerProvider)
          .create(
            name: result.name,
            type: result.type,
            configJson: jsonEncode(result.config),
            startAt: result.startAt,
            endAt: result.endAt,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Offer created')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    Offer o,
  ) async {
    final shopId = await _dialogShopId(ref);
    if (shopId == null || !context.mounted) return;
    final result = await showDialog<_OfferDraft>(
      context: context,
      builder: (_) => _OfferDialog(shopId: shopId, initial: o),
    );
    if (result == null) return;
    try {
      await ref
          .read(offersControllerProvider)
          .update(
            Offer(
              id: o.id,
              shopId: o.shopId,
              name: result.name,
              type: result.type,
              configJson: jsonEncode(result.config),
              isActive: o.isActive,
              startAt: result.startAt,
              endAt: result.endAt,
              createdAt: o.createdAt,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Offer updated')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Offer o,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete offer?'),
        content: Text('Delete "${o.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(offersControllerProvider).delete(o.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Offer deleted')));
      }
    }
  }

  /// Resolves the single shop the offer dialog should scope products to.
  /// The dialog always targets one writable business: the current selection,
  /// falling back to Cafe when in the read-only "All" view (mirroring the
  /// segmented control's Cafe fallback above).
  Future<String?> _dialogShopId(WidgetRef ref) async {
    try {
      final business = ref.read(businessSwitcherProvider);
      final target = business == BusinessContext.all
          ? BusinessContext.cafe
          : business;
      return await ref
          .read(businessSwitcherProvider.notifier)
          .shopIdFor(target);
    } catch (_) {
      return null;
    }
  }
}

class _OfferDraft {
  _OfferDraft({
    required this.name,
    required this.type,
    required this.config,
    this.startAt,
    this.endAt,
  });
  final String name;
  final OfferType type;
  final Map<String, dynamic> config;
  final DateTime? startAt;
  final DateTime? endAt;
}

class _OfferDialog extends ConsumerStatefulWidget {
  const _OfferDialog({required this.shopId, this.initial});
  final String shopId;
  final Offer? initial;
  @override
  ConsumerState<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends ConsumerState<_OfferDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  OfferType _type = OfferType.percentage;
  final _percent = TextEditingController();
  final _comboPrice = TextEditingController();
  final _buyQty = TextEditingController(text: '2');
  final _getQty = TextEditingController(text: '1');

  /// Product ids selected for the current offer type. Internal only — the UI
  /// never exposes raw ids, only product name + price via [_ProductSelector].
  Set<String> _selectedProductIds = <String>{};

  /// Inline validation message for the product selector (kept null until the
  /// owner submits without a required selection for the active offer type).
  String? _selectionError;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _type = widget.initial!.type;
      try {
        final m =
            jsonDecode(widget.initial!.configJson) as Map<String, dynamic>;
        if (_type == OfferType.percentage) {
          _percent.text = (m['percent'] ?? '').toString();
        }
        if (_type == OfferType.combo) {
          _comboPrice.text = (m['comboPricePaise'] ?? '').toString();
          _selectedProductIds = ((m['productIds'] as List?) ?? [])
              .cast<String>()
              .toSet();
        }
        if (_type == OfferType.buyXGetY) {
          final id = m['productId'];
          if (id is String && id.isNotEmpty) {
            _selectedProductIds = <String>{id};
          }
          _buyQty.text = (m['buyQty'] ?? '2').toString();
          _getQty.text = (m['getQty'] ?? '1').toString();
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    _comboPrice.dispose();
    _buyQty.dispose();
    _getQty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'New Offer' : 'Edit Offer'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<OfferType>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: OfferType.percentage,
                      child: Text('Percentage'),
                    ),
                    DropdownMenuItem(
                      value: OfferType.combo,
                      child: Text('Combo'),
                    ),
                    DropdownMenuItem(
                      value: OfferType.buyXGetY,
                      child: Text('Buy X Get Y'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_type == OfferType.percentage)
                  TextFormField(
                    controller: _percent,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Percent (1-100) *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1 || n > 100) return '1-100';
                      return null;
                    },
                  ),
                if (_type == OfferType.combo) ...[
                  TextFormField(
                    controller: _comboPrice,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Combo price (paise) *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        int.tryParse(v ?? '') == null ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ProductSelector(
                    shopId: widget.shopId,
                    title: 'Combo products *',
                    hint:
                        'Search and select the products included in this combo',
                    initialSelected: _selectedProductIds,
                    selected: _selectedProductIds,
                    onChanged: (ids) {
                      setState(() {
                        _selectedProductIds = ids;
                        _selectionError = null;
                      });
                    },
                    errorText: _selectionError,
                  ),
                ],
                if (_type == OfferType.buyXGetY) ...[
                  _ProductSelector(
                    shopId: widget.shopId,
                    title: 'Product *',
                    hint: 'Search and select the product for Buy X Get Y',
                    single: true,
                    initialSelected: _selectedProductIds,
                    selected: _selectedProductIds,
                    onChanged: (ids) {
                      setState(() {
                        _selectedProductIds = ids;
                        _selectionError = null;
                      });
                    },
                    errorText: _selectionError,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _buyQty,
                          decoration: const InputDecoration(
                            labelText: 'Buy Qty',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _getQty,
                          decoration: const InputDecoration(
                            labelText: 'Get Qty',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Offers are managed per-business and sync to the correct tablet. POS application is next phase — original price preserved, discount calculation deferred.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            if (_type == OfferType.combo && _selectedProductIds.isEmpty) {
              setState(() => _selectionError = 'Select at least one product.');
              return;
            }
            if (_type == OfferType.buyXGetY && _selectedProductIds.isEmpty) {
              setState(() => _selectionError = 'Select a product.');
              return;
            }
            late Map<String, dynamic> cfg;
            switch (_type) {
              case OfferType.percentage:
                cfg = {
                  'percent': int.parse(_percent.text),
                  'productIds': <String>[],
                };
                break;
              case OfferType.combo:
                cfg = {
                  'productIds': _selectedProductIds.toList(),
                  'comboPricePaise': int.parse(_comboPrice.text),
                };
                break;
              case OfferType.buyXGetY:
                cfg = {
                  'productId': _selectedProductIds.isEmpty
                      ? ''
                      : _selectedProductIds.first,
                  'buyQty': int.parse(_buyQty.text),
                  'getQty': int.parse(_getQty.text),
                };
                break;
            }
            Navigator.pop(
              context,
              _OfferDraft(name: _name.text.trim(), type: _type, config: cfg),
            );
          },
          child: Text(widget.initial == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

/// Products for the current shop, used to build the searchable selector.
/// Resolved through the repository (overridable in tests) and scoped to the
/// single business the offer targets so Cafe shows Cafe products only and
/// Food Truck shows Food Truck products only.
final _dialogProductsProvider = FutureProvider.autoDispose
    .family<List<Product>, String>((ref, shopId) {
      return ref.read(inventoryRepositoryProvider).products(shopIds: [shopId]);
    });

/// Searchable, business-scoped product selector used inside the offer dialog.
///
/// Shows product name + price only and never exposes raw product ids to the
/// user. Selected products appear as removable chips. Supports a single
/// selection (Buy X Get Y) or multi selection (Combo), storing internal ids
/// via [onChanged] exactly as the calculator expects.
class _ProductSelector extends ConsumerStatefulWidget {
  const _ProductSelector({
    required this.shopId,
    required this.title,
    required this.hint,
    required this.initialSelected,
    required this.selected,
    required this.onChanged,
    this.single = false,
    this.errorText,
  });

  final String shopId;
  final String title;
  final String hint;
  final Set<String> initialSelected;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool single;
  final String? errorText;

  @override
  ConsumerState<_ProductSelector> createState() => _ProductSelectorState();
}

class _ProductSelectorState extends ConsumerState<_ProductSelector> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(
      () => setState(() => _query = _search.text.toLowerCase()),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(Product product) {
    final current = {...widget.selected};
    if (widget.single) {
      setState(() => widget.onChanged({product.id}));
      return;
    }
    if (current.contains(product.id)) {
      current.remove(product.id);
    } else {
      current.add(product.id);
    }
    widget.onChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(_dialogProductsProvider(widget.shopId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        productsAsync.when(
          data: (products) => _buildBody(context, products),
          loading: () => const Padding(
            padding: AppInsets.sm,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => Padding(
            padding: AppInsets.sm,
            child: Text(
              'Products could not be loaded.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, List<Product> all) {
    final active = all.where((p) => p.isActive).toList();
    final visible = _query.isEmpty
        ? active
        : active.where((p) => p.name.toLowerCase().contains(_query)).toList();

    final selectedChips = widget.selected.isEmpty
        ? SizedBox.shrink()
        : Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final id in widget.selected)
                _chipFor(_productById(active, id)),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SearchField(
                controller: _search,
                hintText: widget.hint,
                onChanged: (_) {},
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          active.isEmpty
                              ? 'No products in this business yet.'
                              : 'No products match your search.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = visible[i];
                          final isSelected = widget.selected.contains(p.id);
                          return InkWell(
                            onTap: () => _toggle(p),
                            child: Padding(
                              padding: AppInsets.sm,
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 20,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Text(
                                    Money.formatPaise(p.sellingPricePaise),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        selectedChips,
        if (widget.errorText != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.errorText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Product? _productById(List<Product> products, String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Widget _chipFor(Product? product) {
    final label = product?.name ?? 'Unknown product';
    return InputChip(
      label: Text(label),
      onDeleted: () {
        final next = {...widget.selected}..remove(product?.id);
        widget.onChanged(next);
      },
    );
  }
}
