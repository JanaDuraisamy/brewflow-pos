// ignore_for_file: unused_element_parameter

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
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
    final result = await showDialog<_OfferDraft>(
      context: context,
      builder: (_) => const _OfferDialog(),
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
    final result = await showDialog<_OfferDraft>(
      context: context,
      builder: (_) => _OfferDialog(initial: o),
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

class _OfferDialog extends StatefulWidget {
  const _OfferDialog({this.initial});
  final Offer? initial;
  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  OfferType _type = OfferType.percentage;
  final _percent = TextEditingController();
  final _comboPrice = TextEditingController();
  final _productIds = TextEditingController();
  final _buyQty = TextEditingController(text: '2');
  final _getQty = TextEditingController(text: '1');
  final _productId = TextEditingController();

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
          _productIds.text = ((m['productIds'] as List?) ?? []).join(',');
        }
        if (_type == OfferType.buyXGetY) {
          _productId.text = m['productId'] ?? '';
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
    _productIds.dispose();
    _buyQty.dispose();
    _getQty.dispose();
    _productId.dispose();
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
                  TextFormField(
                    controller: _productIds,
                    decoration: const InputDecoration(
                      labelText: 'Product IDs (comma separated)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_type == OfferType.buyXGetY) ...[
                  TextFormField(
                    controller: _productId,
                    decoration: const InputDecoration(
                      labelText: 'Product ID *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
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
                  'productIds': _productIds.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                  'comboPricePaise': int.parse(_comboPrice.text),
                };
                break;
              case OfferType.buyXGetY:
                cfg = {
                  'productId': _productId.text.trim(),
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
