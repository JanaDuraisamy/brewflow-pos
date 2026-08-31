import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — New Purchase / Receiving Form
///
/// The shop-facing receiving workflow: pick a supplier (or walk-in), add
/// active products, edit quantities and unit costs, watch live totals, then
/// Receive Purchase. The repository remains authoritative — the form only
/// catches obvious input problems, and `receivePurchase` re-validates
/// atomically. On failure the form and cart stay intact for a retry; on
/// success the cart clears, every affected surface refreshes, and the new
/// purchase detail opens.
/// ---------------------------------------------------------------------------

final class PurchaseFormPage extends ConsumerStatefulWidget {
  const PurchaseFormPage({super.key});

  @override
  ConsumerState<PurchaseFormPage> createState() => PurchaseFormPageState();
}

final class PurchaseFormPageState extends ConsumerState<PurchaseFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _notes = TextEditingController();
  final _productSearch = TextEditingController();

  /// Per-line text input, keyed by product id, kept in sync with the cart
  /// lines (created on add, disposed on remove/clear).
  final Map<String, _LineInputs> _lineInputs = {};

  @override
  void dispose() {
    _notes.dispose();
    _productSearch.dispose();
    for (final inputs in _lineInputs.values) {
      inputs.quantity.dispose();
      inputs.cost.dispose();
    }
    super.dispose();
  }

  void _reconcileInputs(List<PurchaseDraftLine> lines) {
    final wanted = {for (final line in lines) line.keyId};
    final removed = _lineInputs.keys
        .where((id) => !wanted.contains(id))
        .toList();
    for (final id in removed) {
      final inputs = _lineInputs.remove(id)!;
      inputs.quantity.dispose();
      inputs.cost.dispose();
    }
    for (final line in lines) {
      _lineInputs.putIfAbsent(
        line.keyId,
        () => _LineInputs(
          quantity: TextEditingController(text: '${line.quantity}'),
          cost: TextEditingController(
            text: Money.paiseToRupeesInput(line.unitCostPaise),
          ),
        ),
      );
    }
  }

  Future<void> _receive() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final notes = _notes.text.trim();
    try {
      final purchase = await ref
          .read(purchaseFormProvider.notifier)
          .submit(notes: notes.isEmpty ? null : notes);
      if (purchase == null || !mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Purchase received successfully. ${purchase.purchaseNumber}',
          ),
        ),
      );
      context.push(AppRoutes.purchaseDetail, extra: purchase);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(purchasesErrorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final form = ref.watch(purchaseFormProvider);
    _reconcileInputs(form.lines);

    return Scaffold(
      appBar: AppBar(title: const Text('New Purchase')),
      body: SingleChildScrollView(
        padding: AppInsets.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Receive stock into your inventory below.',
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SupplierSelector(form: form),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 800;
                final picker = _ProductPicker(
                  searchController: _productSearch,
                  lines: form.lines,
                  submitting: form.submitting,
                );
                final cart = _CartCard(
                  formKey: _formKey,
                  form: form,
                  lineInputs: _lineInputs,
                  notes: _notes,
                  onReceive: _receive,
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      picker,
                      const SizedBox(height: AppSpacing.md),
                      cart,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: picker),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 4, child: cart),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The supplier picker: walk-in (null) or any active supplier. Inactive
/// suppliers are never offered; the repository re-validates the selection.
final class _SupplierSelector extends ConsumerWidget {
  const _SupplierSelector({required this.form});

  final PurchaseFormState form;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final active = ref.watch(activeSuppliersProvider);
    final suppliers = active.value ?? const <Supplier>[];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supplier',
            style: textTheme.titleMedium?.copyWith(
              color: context.appColors.charcoal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Supplier',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: form.supplierId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Walk-in / No Supplier'),
                  ),
                  for (final supplier in suppliers)
                    DropdownMenuItem<String?>(
                      value: supplier.id,
                      child: Text(supplier.name),
                    ),
                ],
                onChanged: form.submitting
                    ? null
                    : (value) => ref
                          .read(purchaseFormProvider.notifier)
                          .setSupplier(value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Active-product picker with a search filter; each row shows name, SKU,
/// current stock and the default cost, with an Add action.
final class _ProductPicker extends ConsumerWidget {
  const _ProductPicker({
    required this.searchController,
    required this.lines,
    required this.submitting,
  });

  final TextEditingController searchController;
  final List<PurchaseDraftLine> lines;
  final bool submitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final products = ref.watch(purchaseProductsProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Products',
            style: textTheme.titleMedium?.copyWith(
              color: context.appColors.charcoal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SearchField(
            controller: searchController,
            hintText: 'Search products',
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 340,
            child: products.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    inventoryErrorMessage(error),
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ),
              ),
              data: (items) => ValueListenableBuilder<TextEditingValue>(
                valueListenable: searchController,
                builder: (context, value, _) {
                  final query = value.text.trim().toLowerCase();
                  final matches = [
                    for (final product in items)
                      if (query.isEmpty ||
                          product.name.toLowerCase().contains(query) ||
                          (product.sku?.toLowerCase().contains(query) ?? false))
                        product,
                  ];
                  if (matches.isEmpty) {
                    return Center(
                      child: Text(
                        query.isEmpty
                            ? 'No products available to receive.'
                            : 'No products match your search.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: matches.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = matches[index];
                      final activeVariants = [
                        for (final variant in product.variants)
                          if (variant.isActive) variant,
                      ];
                      final inCart = activeVariants.isEmpty
                          ? lines.any((line) => line.keyId == product.id)
                          : activeVariants.every(
                              (variant) =>
                                  lines.any((line) => line.keyId == variant.id),
                            );
                      return _ProductPickerRow(
                        product: product,
                        inCart: inCart,
                        submitting: submitting,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ProductPickerRow extends ConsumerWidget {
  const _ProductPickerRow({
    required this.product,
    required this.inCart,
    required this.submitting,
  });

  final Product product;
  final bool inCart;
  final bool submitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final cost = product.costPricePaise;
    final variants = [
      for (final variant in product.variants)
        if (variant.isActive) variant,
    ];
    final hasVariants = variants.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (hasVariants) '${variants.length} variants',
                    if (product.sku != null) 'SKU: ${product.sku}',
                    'Stock: ${product.stockQuantity}',
                    cost == null
                        ? 'Cost: —'
                        : 'Cost: ${Money.formatPaise(cost)}',
                  ].join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (inCart)
            const Icon(
              Icons.check_circle,
              size: 20,
              color: AppColors.primary,
              semanticLabel: 'Already in cart',
            )
          else
            FilledButton(
              key: Key('add-${product.id}'),
              onPressed: submitting
                  ? null
                  : () {
                      if (!hasVariants) {
                        ref
                            .read(purchaseFormProvider.notifier)
                            .addLine(
                              product: product,
                              quantity: 1,
                              unitCostPaise: cost ?? 0,
                            );
                        return;
                      }
                      showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (context) => _VariantReceiveSheet(
                          product: product,
                          variants: variants,
                          submitting: submitting,
                        ),
                      );
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              ),
              child: Text(hasVariants ? 'Variants' : 'Add'),
            ),
        ],
      ),
    );
  }
}

/// Bottom-sheet variant receiver: lists the sellable variants of a variant
/// product, marks the ones already in the cart and adds the chosen one on
/// tap. Stays open so several variants can be added in one pass.
final class _VariantReceiveSheet extends ConsumerWidget {
  const _VariantReceiveSheet({
    required this.product,
    required this.variants,
    required this.submitting,
  });

  final Product product;
  final List<ProductVariant> variants;
  final bool submitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final lines = ref.watch(purchaseFormProvider).lines;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppInsets.screen.left,
              0,
              AppInsets.screen.right,
              AppSpacing.sm,
            ),
            child: Text(
              'Receive ${product.name}',
              style: textTheme.titleMedium?.copyWith(
                color: context.appColors.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (var i = 0; i < variants.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              title: Text(
                variants[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.charcoal,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                [
                  if (variants[i].sku != null) 'SKU: ${variants[i].sku}',
                  'Stock: ${variants[i].stockQuantity}',
                  'Cost: ${Money.formatPaise(variants[i].costPricePaise ?? product.costPricePaise ?? 0)}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              trailing: lines.any((line) => line.keyId == variants[i].id)
                  ? const Icon(
                      Icons.check_circle,
                      size: 20,
                      color: AppColors.primary,
                      semanticLabel: 'Already in cart',
                    )
                  : FilledButton(
                      key: Key('add-${variants[i].id}'),
                      onPressed: submitting
                          ? null
                          : () => ref
                                .read(purchaseFormProvider.notifier)
                                .addLine(
                                  product: product,
                                  variant: variants[i],
                                  quantity: 1,
                                  unitCostPaise:
                                      variants[i].costPricePaise ??
                                      product.costPricePaise ??
                                      0,
                                ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                      ),
                      child: const Text('Add'),
                    ),
              onTap: null,
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppInsets.screen.left,
              AppSpacing.sm,
              AppInsets.screen.right,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The receiving cart: editable lines with live totals, notes and the
/// Receive Purchase action.
final class _CartCard extends ConsumerWidget {
  const _CartCard({
    required this.formKey,
    required this.form,
    required this.lineInputs,
    required this.notes,
    required this.onReceive,
  });

  final GlobalKey<FormState> formKey;
  final PurchaseFormState form;
  final Map<String, _LineInputs> lineInputs;
  final TextEditingController notes;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final lines = form.lines;
    final subtotal =
        Money.sumPaise([
          for (final line in lines)
            Money.multiplyPaise(line.unitCostPaise, line.quantity) ?? 0,
        ]) ??
        0;

    return AppCard(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Items to receive (${lines.length})',
              style: textTheme.titleMedium?.copyWith(
                color: context.appColors.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (lines.isEmpty)
              Text(
                'No items yet. Add products from the list above.',
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              )
            else
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                _CartLine(
                  line: lines[i],
                  inputs: lineInputs[lines[i].keyId],
                  submitting: form.submitting,
                ),
              ],
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text(
                  'Subtotal',
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  Money.formatPaise(subtotal),
                  key: const Key('subtotal-value'),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.charcoal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Text(
                  'Total',
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  Money.formatPaise(subtotal),
                  key: const Key('total-value'),
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: notes,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Optional',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton(
                  onPressed: form.submitting ? null : () => context.pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Receive Purchase',
                  icon: Icons.inventory_2_outlined,
                  loading: form.submitting,
                  onPressed: form.submitting || lines.isEmpty
                      ? null
                      : onReceive,
                  expanded: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One editable cart line: quantity, unit cost, live line total, remove.
final class _CartLine extends ConsumerWidget {
  const _CartLine({
    required this.line,
    required this.inputs,
    required this.submitting,
  });

  final PurchaseDraftLine line;
  final _LineInputs? inputs;
  final bool submitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final lineTotal =
        Money.multiplyPaise(line.unitCostPaise, line.quantity) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.variantName == null
                        ? line.productName
                        : '${line.productName} — ${line.variantName}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.charcoal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (line.sku != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'SKU: ${line.sku}',
                      style: textTheme.bodySmall?.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    'Current stock: ${line.stockQuantity} · Receiving: ${line.quantity}'
                    ' · After receive: ${line.stockQuantity + line.quantity}',
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('remove-${line.keyId}'),
              tooltip: 'Remove line',
              icon: const Icon(Icons.close),
              onPressed: submitting
                  ? null
                  : () => ref
                        .read(purchaseFormProvider.notifier)
                        .removeLine(line.keyId),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: TextFormField(
                key: Key('qty-${line.keyId}'),
                controller: inputs?.quantity,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Qty',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed != null && parsed >= 0) {
                    ref
                        .read(purchaseFormProvider.notifier)
                        .updateQuantity(line.keyId, parsed);
                  }
                },
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed < 1) {
                    return 'Quantity must be at least 1.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                key: Key('cost-${line.keyId}'),
                controller: inputs?.cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Unit cost (₹)',
                  hintText: 'e.g. 149.50',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) {
                  final paise = Money.parseRupeesToPaise(value);
                  if (paise != null) {
                    ref
                        .read(purchaseFormProvider.notifier)
                        .updateCost(line.keyId, paise);
                  }
                },
                validator: (value) {
                  final paise = Money.parseRupeesToPaise(value ?? '');
                  if (paise == null) {
                    return 'Enter a valid cost (e.g. 149.50)';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                Money.formatPaise(lineTotal),
                key: Key('line-total-${line.keyId}'),
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.charcoal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Text inputs backing one cart line.
final class _LineInputs {
  const _LineInputs({required this.quantity, required this.cost});

  final TextEditingController quantity;
  final TextEditingController cost;
}
