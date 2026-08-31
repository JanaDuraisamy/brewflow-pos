import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_breakpoints.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_shadows.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/core/sharing/share_service.dart';
import 'package:brewflow_pos/features/printing/data/unverified_printer_service.dart';
import 'package:brewflow_pos/features/billing/domain/receipt_document.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/product_thumbnail.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Point of Sale Page
///
/// Browse and search sellable products, build a cart, pick a payment method
/// (CASH / UPI / BANK) and complete the sale. Wide screens show a product
/// grid next to the cart; narrow screens switch between the two. After a
/// successful checkout a receipt summary dialog appears and the counter stays
/// in the POS workflow with a fresh cart. All figures come from the live
/// inventory repository — never invented.
/// ---------------------------------------------------------------------------

final class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

final class _PosPageState extends ConsumerState<PosPage> {
  PaymentMethod? _payment;
  PaymentStatus _paymentStatus = PaymentStatus.paid;
  bool _checkingOut = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _addToCart(Product product, {ProductVariant? variant}) {
    try {
      ref.read(cartProvider.notifier).add(product, variant: variant);
    } on BillingFailure catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _checkout() async {
    setState(() => _checkingOut = true);
    CompletedSale? completed;
    try {
      completed = await ref
          .read(cartProvider.notifier)
          .checkout(_payment, paymentStatus: _paymentStatus);
    } on BillingFailure catch (error) {
      if (mounted) {
        _showMessage('Sale not completed. ${error.message}');
      }
    } finally {
      if (mounted) {
        setState(() => _checkingOut = false);
      }
    }
    if (completed == null || !mounted) return;
    await _showReceipt(completed);
  }

  Future<void> _showReceipt(CompletedSale completed) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ReceiptDialog(completed: completed),
    );
  }

  /// Opens the customer picker and links the chosen customer to the cart.
  Future<void> _pickCustomer() async {
    final customer = await showDialog<Customer>(
      context: context,
      builder: (context) => const _CustomerPickerDialog(),
    );
    if (customer == null || !mounted) return;
    ref.read(cartProvider.notifier).selectCustomer(customer.id);
  }

  /// Parks the current cart as a held bill. Pure in-memory move — no sale, no
  /// stock change, no receipt consumed. A no-op when the cart is empty.
  void _holdBill() {
    final bill = ref
        .read(heldBillsProvider.notifier)
        .holdCurrentBill(
          paymentStatus: _paymentStatus,
          paymentMethod: _payment,
        );
    if (bill == null) return;
    _showMessage('Bill held. Resume it anytime from Held Bills.');
  }

  /// Opens the held-bills sheet (same POS screen, cart stays untouched).
  Future<void> _openHeldBills() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          _HeldBillsSheet(onResume: _confirmResume, onDelete: _confirmDelete),
    );
  }

  /// Confirms resuming [bill] when the current cart is not empty, then
  /// restores it and re-applies its payment choices. Returns true when the
  /// bill was actually resumed (the caller closes the sheet).
  Future<bool> _confirmResume(HeldBill bill) async {
    if (ref.read(cartProvider).isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Resume held bill?'),
          content: const Text('Current bill will be replaced. Continue?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return false;
    }
    final resumed = ref
        .read(heldBillsProvider.notifier)
        .resumeHeldBill(bill.id);
    if (resumed == null || !mounted) return false;
    setState(() {
      _payment = resumed.paymentMethod;
      _paymentStatus = resumed.paymentStatus;
    });
    return true;
  }

  /// Confirms deleting [bill] (removes only that bill; products and stock are
  /// untouched because holding never reserved anything). Returns true when
  /// the bill was actually deleted.
  Future<bool> _confirmDelete(int displayNumber, HeldBill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete held bill #$displayNumber?'),
        content: const Text(
          'The held bill is removed without touching products or stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    ref.read(heldBillsProvider.notifier).deleteHeldBill(bill.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final heldBills = ref.watch(heldBillsProvider);
    final products = ref.watch(posProductsProvider);
    final categories = ref.watch(categoriesProvider);
    final membershipEnabled =
        ref.watch(shopSettingsProvider).value?.membershipEnabled ??
        ShopSettings.defaultMembershipEnabled;

    Customer? selectedCustomer;
    final selectedId = cart.selectedCustomerId;
    if (selectedId != null) {
      for (final customer
          in ref.watch(posCustomersProvider).value ?? const <Customer>[]) {
        if (customer.id == selectedId) {
          selectedCustomer = customer;
          break;
        }
      }
    }

    return Padding(
      padding: AppInsets.screen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Billing & POS',
            subtitle: 'Sell products and complete sales at the counter.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _ShelfFilter(categories: categories.value ?? const []),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ProductShelf(
                          products: products,
                          cart: cart,
                          onAdd: _addToCart,
                          onRetry: () => ref.invalidate(posProductsProvider),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      SizedBox(
                        width: 400,
                        child: _CartPanel(
                          cart: cart,
                          selectedCustomer: selectedCustomer,
                          payment: _payment,
                          paymentStatus: _paymentStatus,
                          checkingOut: _checkingOut,
                          onPickCustomer: _pickCustomer,
                          onClearCustomer: () => ref
                              .read(cartProvider.notifier)
                              .selectCustomer(null),
                          onPaymentChanged: (method) =>
                              setState(() => _payment = method),
                          onPaymentStatusChanged: (status) =>
                              setState(() => _paymentStatus = status),
                          onToggleMemberPricing: () => ref
                              .read(cartProvider.notifier)
                              .toggleMemberPricing(),
                          onComplete: _checkout,
                          membershipEnabled: membershipEnabled,
                          heldCount: heldBills.length,
                          onHold: _holdBill,
                          onOpenHeldBills: _openHeldBills,
                        ),
                      ),
                    ],
                  );
                }
                return _NarrowLayout(
                  products: products,
                  cart: cart,
                  selectedCustomer: selectedCustomer,
                  payment: _payment,
                  paymentStatus: _paymentStatus,
                  checkingOut: _checkingOut,
                  onAdd: _addToCart,
                  onRetry: () => ref.invalidate(posProductsProvider),
                  onPickCustomer: _pickCustomer,
                  onClearCustomer: () =>
                      ref.read(cartProvider.notifier).selectCustomer(null),
                  onPaymentChanged: (method) =>
                      setState(() => _payment = method),
                  onPaymentStatusChanged: (status) =>
                      setState(() => _paymentStatus = status),
                  onToggleMemberPricing: () =>
                      ref.read(cartProvider.notifier).toggleMemberPricing(),
                  onComplete: _checkout,
                  membershipEnabled: membershipEnabled,
                  heldCount: heldBills.length,
                  onHold: _holdBill,
                  onOpenHeldBills: _openHeldBills,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final class _ShelfFilter extends ConsumerStatefulWidget {
  const _ShelfFilter({required this.categories});

  final List<Category> categories;

  @override
  ConsumerState<_ShelfFilter> createState() => _ShelfFilterState();
}

final class _ShelfFilterState extends ConsumerState<_ShelfFilter> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(posFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(posFilterProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final search = SizedBox(
          width: compact ? double.infinity : 320,
          child: SearchField(
            controller: _search,
            hintText: 'Search by name or SKU',
            onChanged: (value) =>
                ref.read(posFilterProvider.notifier).setQuery(value),
          ),
        );
        final chips = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFilterChip(
              label: 'All categories',
              selected: filter.categoryId == null,
              onSelected: (selected) {
                if (selected) {
                  ref.read(posFilterProvider.notifier).setCategory(null);
                }
              },
            ),
            for (final category in widget.categories) ...[
              const SizedBox(width: AppSpacing.sm),
              AppFilterChip(
                label: category.name,
                selected: filter.categoryId == category.id,
                onSelected: (selected) => ref
                    .read(posFilterProvider.notifier)
                    .setCategory(selected ? category.id : null),
              ),
            ],
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              search,
              const SizedBox(height: AppSpacing.md),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: chips,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 320, child: search),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: chips,
              ),
            ),
          ],
        );
      },
    );
  }
}

final class _NarrowLayout extends StatefulWidget {
  const _NarrowLayout({
    required this.products,
    required this.cart,
    required this.selectedCustomer,
    required this.payment,
    required this.paymentStatus,
    required this.checkingOut,
    required this.onAdd,
    required this.onRetry,
    required this.onPickCustomer,
    required this.onClearCustomer,
    required this.onPaymentChanged,
    required this.onPaymentStatusChanged,
    required this.onToggleMemberPricing,
    required this.onComplete,
    required this.membershipEnabled,
    required this.heldCount,
    required this.onHold,
    required this.onOpenHeldBills,
  });

  final AsyncValue<List<Product>> products;
  final Cart cart;
  final Customer? selectedCustomer;
  final PaymentMethod? payment;
  final PaymentStatus paymentStatus;
  final bool checkingOut;
  final void Function(Product, {ProductVariant? variant}) onAdd;
  final VoidCallback onRetry;
  final VoidCallback onPickCustomer;
  final VoidCallback onClearCustomer;
  final ValueChanged<PaymentMethod?> onPaymentChanged;
  final ValueChanged<PaymentStatus> onPaymentStatusChanged;
  final VoidCallback onToggleMemberPricing;
  final VoidCallback onComplete;
  final bool membershipEnabled;
  final int heldCount;
  final VoidCallback onHold;
  final VoidCallback onOpenHeldBills;

  @override
  State<_NarrowLayout> createState() => _NarrowLayoutState();
}

final class _NarrowLayoutState extends State<_NarrowLayout> {
  bool _showCart = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.cart.chargedTotalPaise;
    final phone = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    return Column(
      children: [
        // Phone cart summary: persistent shelf-side affordance with item
        // count AND live total, so the counter never has to switch views just
        // to know what the bill looks like. Hidden while the cart itself is
        // open (it would be redundant and steal vertical space).
        if (!_showCart)
          InkWell(
            borderRadius: AppBorderRadius.md,
            onTap: () => setState(() => _showCart = true),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: phone ? AppSpacing.md : AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: context.appColors.surfaceVariant,
                borderRadius: AppBorderRadius.md,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: phone ? 20 : 18,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.cart.isEmpty
                          ? 'Cart is empty — tap to add items'
                          : '${widget.cart.itemCount} in cart',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.cart.isNotEmpty)
                    Text(
                      total == null ? '—' : Money.formatPaise(total),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (widget.cart.isNotEmpty) SizedBox(width: AppSpacing.sm),
                  Text(
                    'Open cart',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
                ],
              ),
            ),
          ),
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Products')),
                  ButtonSegment(value: true, label: Text('Cart')),
                ],
                selected: {_showCart},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _showCart = selection.first),
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        Expanded(
          child: _showCart
              ? _CartPanel(
                  cart: widget.cart,
                  selectedCustomer: widget.selectedCustomer,
                  payment: widget.payment,
                  paymentStatus: widget.paymentStatus,
                  checkingOut: widget.checkingOut,
                  onPickCustomer: widget.onPickCustomer,
                  onClearCustomer: widget.onClearCustomer,
                  onPaymentChanged: widget.onPaymentChanged,
                  onPaymentStatusChanged: widget.onPaymentStatusChanged,
                  onToggleMemberPricing: widget.onToggleMemberPricing,
                  membershipEnabled: widget.membershipEnabled,
                  onComplete: widget.onComplete,
                  heldCount: widget.heldCount,
                  onHold: widget.onHold,
                  onOpenHeldBills: widget.onOpenHeldBills,
                  phone: phone,
                )
              : _ProductShelf(
                  products: widget.products,
                  cart: widget.cart,
                  onAdd: widget.onAdd,
                  onRetry: widget.onRetry,
                  phone: phone,
                ),
        ),
      ],
    );
  }
}

final class _ProductShelf extends ConsumerWidget {
  const _ProductShelf({
    required this.products,
    required this.cart,
    required this.onAdd,
    required this.onRetry,
    this.phone = false,
  });

  final AsyncValue<List<Product>> products;
  final Cart cart;
  final void Function(Product, {ProductVariant? variant}) onAdd;
  final VoidCallback onRetry;

  /// True on phone-width shelves (< 600dp) so cards can switch to the
  /// phone-first selling layout without touching the desktop grid.
  final bool phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(posFilterProvider);
    final hasFilters = filtered.query.isNotEmpty || filtered.categoryId != null;
    return products.when(
      skipLoadingOnRefresh: true,
      loading: () => const LoadingState(message: 'Loading products…'),
      error: (error, stackTrace) =>
          ErrorState(message: billingErrorMessage(error), onRetry: onRetry),
      data: (items) => items.isEmpty
          ? EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Nothing on the shelf',
              message: hasFilters
                  ? 'No products with stock match your search or filter. '
                        'Try a different search.'
                  : 'No products with stock yet. Add products in Inventory '
                        'to start selling.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isPhone = constraints.maxWidth < 600;
                return GridView.builder(
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isPhone ? 280 : 300,
                    mainAxisExtent: isPhone ? 192 : 176,
                    crossAxisSpacing: isPhone ? AppSpacing.lg : AppSpacing.md,
                    mainAxisSpacing: isPhone ? AppSpacing.lg : AppSpacing.md,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final product = items[index];
                    return _ProductCard(
                      product: product,
                      phone: phone,
                      quantityInCart: _cartQuantityOf(cart, product),
                      onAdd: () => onAdd(product),
                      onPickVariant: (variant) =>
                          onAdd(product, variant: variant),
                    );
                  },
                );
              },
            ),
    );
  }

  /// Pieces of [product] in the cart: product lines plus every variant line.
  static int _cartQuantityOf(Cart cart, Product product) {
    var total = cart.quantityOf(product.id);
    for (final variant in product.variants) {
      total += cart.quantityOf(variant.id);
    }
    return total;
  }
}

final class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.quantityInCart,
    required this.onAdd,
    required this.onPickVariant,
    this.phone = false,
  });

  final Product product;
  final int quantityInCart;
  final VoidCallback onAdd;
  final ValueChanged<ProductVariant> onPickVariant;

  /// Phone layout: clean name → price → SKU/stock hierarchy with a full-width
  /// Add button, sized to fit the compact two-column shelf grid.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final variants = [
      for (final variant in product.variants)
        if (variant.isActive) variant,
    ];
    final hasVariants = variants.isNotEmpty;
    final primary = hasVariants ? variants.first : null;
    final untracked = product.stockUnit == StockUnit.none;
    final stock = hasVariants
        ? variants.fold(0, (sum, variant) => sum + variant.stockQuantity)
        : product.stockQuantity;
    final sku = primary?.sku ?? product.sku;
    final remaining = untracked ? 1 : stock - quantityInCart;
    final soldOut = !untracked && remaining <= 0;
    final price = Money.formatPaise(
      primary?.sellingPricePaise ?? product.sellingPricePaise,
    );
    final meta = [
      if (hasVariants) '${variants.length} variants',
      if (sku != null) 'SKU $sku',
      if (untracked) 'Made to order' else 'Stock $stock',
    ].join(' · ');

    void addAction() {
      if (!hasVariants) {
        onAdd();
        return;
      }
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => _VariantPickerSheet(
          product: product,
          variants: variants,
          onSelect: onPickVariant,
        ),
      );
    }

    if (phone) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: context.appColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.lg,
          side: BorderSide(color: context.appColors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (quantityInCart > 0) ...[
                    SizedBox(width: AppSpacing.xs),
                    _QuantityBadge(quantity: quantityInCart),
                  ],
                ],
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                price,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: stock == 0
                      ? AppColors.outOfStock
                      : context.appColors.textSecondary,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: soldOut ? null : addAction,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size.fromHeight(40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppBorderRadius.md,
                  ),
                ),
                child: soldOut ? const Text('Sold out') : const Text('Add'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: context.appColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.lg,
        side: BorderSide(color: context.appColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (product.imagePath != null) ...[
            ProductThumbnail(imagePath: product.imagePath, size: 56),
            SizedBox(height: AppSpacing.sm),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (quantityInCart > 0) ...[
                SizedBox(width: AppSpacing.xs),
                _QuantityBadge(quantity: quantityInCart),
              ],
            ],
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: stock == 0
                  ? AppColors.outOfStock
                  : context.appColors.textSecondary,
            ),
          ),
          Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton(
                onPressed: soldOut ? null : addAction,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                ),
                child: soldOut ? const Text('Sold out') : const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet variant chooser shown when adding a variant product: lists
/// the sellable variants and pops with the chosen one.
final class _VariantPickerSheet extends StatelessWidget {
  const _VariantPickerSheet({
    required this.product,
    required this.variants,
    required this.onSelect,
  });

  final Product product;
  final List<ProductVariant> variants;
  final ValueChanged<ProductVariant> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final untracked = product.stockUnit == StockUnit.none;
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
              'Choose ${product.name}',
              style: textTheme.titleMedium?.copyWith(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (var i = 0; i < variants.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              enabled: untracked || variants[i].stockQuantity > 0,
              title: Text(
                variants[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                [
                  if (variants[i].sku != null) 'SKU ${variants[i].sku}',
                  if (untracked)
                    'Made to order'
                  else
                    'Stock ${variants[i].stockQuantity}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              trailing: !untracked && variants[i].stockQuantity <= 0
                  ? Text(
                      'Sold out',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.outOfStock,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Money.formatPaise(variants[i].sellingPricePaise),
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (variants[i].memberPricePaise != null)
                          Text(
                            'Member ${Money.formatPaise(variants[i].memberPricePaise!)}',
                            style: textTheme.bodySmall?.copyWith(
                              color: context.appColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
              onTap: () {
                Navigator.of(context).pop();
                onSelect(variants[i]);
              },
            ),
          ],
        ],
      ),
    );
  }
}

final class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 12,
            color: AppColors.primary,
          ),
          SizedBox(width: AppSpacing.xs),
          Text(
            '$quantity',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cart-level customer attachment: shows the linked customer (or "Walk-in"),
/// opens the picker on tap and clears back to a walk-in via the close icon.
final class _CustomerSelector extends StatelessWidget {
  const _CustomerSelector({
    required this.customer,
    required this.onPick,
    required this.onClear,
  });

  final Customer? customer;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer',
          style: textTheme.titleSmall?.copyWith(
            color: context.appColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        Material(
          color: context.appColors.surfaceVariant,
          borderRadius: AppBorderRadius.md,
          child: InkWell(
            onTap: onPick,
            borderRadius: AppBorderRadius.md,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 18,
                    color: context.appColors.textSecondary,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      customer?.name ?? 'Walk-in',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: customer == null
                            ? context.appColors.textSecondary
                            : context.appColors.textPrimary,
                        fontWeight: customer == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (customer == null)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: context.appColors.textSecondary,
                    )
                  else
                    IconButton(
                      tooltip: 'Remove customer',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 16,
                      icon: const Icon(Icons.close),
                      color: context.appColors.textSecondary,
                      onPressed: onClear,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.selectedCustomer,
    required this.payment,
    required this.paymentStatus,
    required this.checkingOut,
    required this.onPickCustomer,
    required this.onClearCustomer,
    required this.onPaymentChanged,
    required this.onPaymentStatusChanged,
    required this.onToggleMemberPricing,
    required this.onComplete,
    required this.membershipEnabled,
    required this.heldCount,
    required this.onHold,
    required this.onOpenHeldBills,
    this.phone = false,
  });

  final Cart cart;
  final Customer? selectedCustomer;
  final PaymentMethod? payment;
  final PaymentStatus paymentStatus;
  final bool checkingOut;
  final VoidCallback onPickCustomer;
  final VoidCallback onClearCustomer;
  final ValueChanged<PaymentMethod?> onPaymentChanged;
  final ValueChanged<PaymentStatus> onPaymentStatusChanged;
  final VoidCallback onToggleMemberPricing;
  final VoidCallback onComplete;
  final bool membershipEnabled;
  final int heldCount;
  final VoidCallback onHold;
  final VoidCallback onOpenHeldBills;

  /// Phone layout: taller Complete Sale and large-touch quantity controls.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtotal = cart.subtotalPaise;
    final total = cart.chargedTotalPaise;
    final hasMemberPrices =
        membershipEnabled &&
        cart.lines.any((line) => line.memberPricePaise != null);
    final notPaid = paymentStatus == PaymentStatus.notPaid;
    final canComplete =
        cart.isNotEmpty &&
        !checkingOut &&
        (notPaid ? selectedCustomer != null : payment != null);

    return AppCard(
      padding: AppInsets.card,
      shadows: AppShadows.md,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Layout contract (any viewport height):
          //  - header block is capped (internally scrollable only on very
          //    short viewports),
          //  - cart items scroll independently in the Expanded middle,
          //  - subtotal/total stay pinned,
          //  - payment pickers flex and scroll internally only when height
          //    runs out,
          //  - Complete Sale / Hold / Held Bills are always pinned to the
          //    bottom so billing actions can never scroll out of view.
          final lines = cart.isEmpty
              ? const _EmptyCartHint()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final line in cart.lines)
                      _CartLineTile(line: line, phone: phone),
                  ],
                );
          final headerBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Current Sale',
                      style: textTheme.titleMedium?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (cart.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.softGreen,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '${cart.itemCount} in cart',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _CustomerSelector(
                customer: selectedCustomer,
                onPick: onPickCustomer,
                onClear: onClearCustomer,
              ),
              if (hasMemberPrices) ...[
                SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Member pricing',
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(
                      value: cart.memberPricing,
                      onChanged: (_) => onToggleMemberPricing(),
                    ),
                  ],
                ),
              ],
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Header: capped on short panels, internally scrollable ----
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.38,
                ),
                child: SingleChildScrollView(child: headerBlock),
              ),
              const SizedBox(height: AppSpacing.md),

              // ---- Scrollable middle: cart lines + payment controls
              // together. On tall screens everything fits without scrolling;
              // on narrow phones the cashier scrolls to reach payment
              // pickers. Action buttons below stay pinned so Complete Sale
              // is always reachable. ----
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      lines,
                      const Divider(height: AppSpacing.xl),
                      _SummaryRow(
                        label: cart.isEmpty
                            ? 'Subtotal'
                            : 'Subtotal (${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'})',
                        amount: subtotal == null
                            ? '—'
                            : Money.formatPaise(subtotal),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _SummaryRow(
                        label: 'Total',
                        amount: total == null ? '—' : Money.formatPaise(total),
                        emphasized: true,
                      ),
                      if (notPaid && selectedCustomer != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _SummaryRow(
                          label: 'Due Added',
                          amount: total == null
                              ? '—'
                              : Money.formatPaise(total),
                          emphasized: true,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _PaymentStatusPicker(
                        selected: paymentStatus,
                        onChanged: onPaymentStatusChanged,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (notPaid)
                        if (selectedCustomer == null)
                          _NotPaidCustomerHint()
                        else
                          const SizedBox.shrink()
                      else
                        _PaymentPicker(
                          selected: payment,
                          onChanged: onPaymentChanged,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ---- Pinned actions (always visible) ----
              FilledButton(
                onPressed: canComplete ? onComplete : null,
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(phone ? 56 : 48),
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: context.appColors.surfaceVariant,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: context.appColors.textDisabled,
                ),
                child: checkingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined),
                          SizedBox(width: AppSpacing.sm),
                          Text('Complete Sale'),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Hold Bill',
                      icon: Icons.pause_circle_outline,
                      minHeight: 44,
                      onPressed: cart.isNotEmpty && !checkingOut
                          ? onHold
                          : null,
                    ),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: SecondaryButton(
                      label: heldCount == 0
                          ? 'Held Bills'
                          : 'Held Bills ($heldCount)',
                      icon: Icons.inventory_2_outlined,
                      minHeight: 44,
                      onPressed: onOpenHeldBills,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One cart line with quantity controls, resolving mutations through the
/// cart controller and mapping failures to snackbar messages.
final class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line, this.phone = false});

  final CartLine line;

  /// Phone layout: quantity controls get large 40dp touch targets and the
  /// line stacks its info above its actions so names stay readable.
  final bool phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final cartNotifier = ref.read(cartProvider.notifier);
    final memberPricing = ref.watch(cartProvider).memberPricing;

    void run(void Function() action) {
      try {
        action();
      } on BillingFailure catch (error) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    }

    final name = Text(
      line.variantName == null
          ? line.productName
          : '${line.productName} — ${line.variantName}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.bodyMedium?.copyWith(
        color: context.appColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    final unitTotal = Text(
      '${Money.formatPaise(line.chargedUnitPricePaise(memberPricing))} × ${line.quantity}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.bodySmall?.copyWith(
        color: context.appColors.textSecondary,
      ),
    );
    final lineTotal = Text(
      Money.formatPaise(line.lineTotalPaise),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.bodyMedium?.copyWith(
        color: context.appColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );

    final removeButton = IconButton(
      tooltip: 'Remove line',
      visualDensity: phone ? VisualDensity.standard : VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: phone
          ? const BoxConstraints(minWidth: 40, minHeight: 40)
          : const BoxConstraints(),
      iconSize: phone ? 20 : 16,
      icon: const Icon(Icons.delete_outline),
      color: context.appColors.textSecondary,
      // keyId, never productId: a variant line's stock entity is the
      // variant, so mutations must target exactly that line.
      onPressed: () {
        final removed = line;
        cartNotifier.remove(removed.keyId);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Removed ${removed.productName}'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  ref.read(cartProvider.notifier).restoreLine(removed);
                },
              ),
            ),
          );
      },
    );

    final decrementButton = IconButton(
      tooltip: 'Decrease quantity',
      visualDensity: phone ? VisualDensity.standard : VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: phone
          ? const BoxConstraints(minWidth: 40, minHeight: 40)
          : const BoxConstraints(),
      iconSize: phone ? 22 : 16,
      icon: const Icon(Icons.remove_circle_outline),
      color: context.appColors.textPrimary,
      onPressed: () => run(() => cartNotifier.decrement(line.keyId)),
    );

    final incrementButton = IconButton(
      tooltip: 'Increase quantity',
      visualDensity: phone ? VisualDensity.standard : VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: phone
          ? const BoxConstraints(minWidth: 40, minHeight: 40)
          : const BoxConstraints(),
      iconSize: phone ? 22 : 16,
      icon: const Icon(Icons.add_circle_outline),
      color: AppColors.primary,
      onPressed: () => run(() => cartNotifier.increment(line.keyId)),
    );

    if (phone) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      name,
                      SizedBox(height: AppSpacing.xs),
                      unitTotal,
                    ],
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                lineTotal,
              ],
            ),
            SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                removeButton,
                const Spacer(),
                decrementButton,
                SizedBox(width: AppSpacing.sm),
                incrementButton,
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                SizedBox(height: AppSpacing.xs),
                unitTotal,
              ],
            ),
          ),
          SizedBox(width: AppSpacing.xs),
          Flexible(child: lineTotal),
          SizedBox(width: AppSpacing.xs),
          removeButton,
          decrementButton,
          incrementButton,
        ],
      ),
    );
  }
}

final class _PaymentStatusPicker extends StatelessWidget {
  const _PaymentStatusPicker({required this.selected, required this.onChanged});

  final PaymentStatus selected;
  final ValueChanged<PaymentStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Status',
          style: textTheme.titleSmall?.copyWith(
            color: context.appColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PaymentStatus>(
            segments: const [
              ButtonSegment(value: PaymentStatus.paid, label: Text('Paid')),
              ButtonSegment(
                value: PaymentStatus.notPaid,
                label: Text('Not Paid'),
              ),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
      ],
    );
  }
}

/// Shown when a credit (NOT_PAID) sale has no customer yet: a calm,
/// non-alarming reminder that a customer is required.
final class _NotPaidCustomerHint extends StatelessWidget {
  const _NotPaidCustomerHint();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.appColors.surfaceVariant,
        borderRadius: AppBorderRadius.md,
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 18,
            color: context.appColors.textSecondary,
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Select a customer to save this bill as Not Paid.',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _PaymentPicker extends StatelessWidget {
  const _PaymentPicker({required this.selected, required this.onChanged});

  final PaymentMethod? selected;
  final ValueChanged<PaymentMethod?> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Method',
          style: textTheme.titleSmall?.copyWith(
            color: context.appColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PaymentMethod>(
            segments: const [
              ButtonSegment(value: PaymentMethod.cash, label: Text('Cash')),
              ButtonSegment(value: PaymentMethod.upi, label: Text('UPI')),
              ButtonSegment(value: PaymentMethod.bank, label: Text('Bank')),
            ],
            selected: {?selected},
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                onChanged(selection.isEmpty ? null : selection.first),
          ),
        ),
      ],
    );
  }
}

final class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final String amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
              fontWeight: emphasized ? FontWeight.w700 : null,
            ),
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Text(
          amount,
          style: textTheme.bodyMedium?.copyWith(
            color: emphasized
                ? context.appColors.textPrimary
                : context.appColors.textSecondary,
            fontWeight: emphasized ? FontWeight.w800 : null,
          ),
        ),
      ],
    );
  }
}

final class _EmptyCartHint extends StatelessWidget {
  const _EmptyCartHint();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.appColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 30,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              'Your cart is empty',
              style: textTheme.titleMedium?.copyWith(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              'Add products from the shelf to start a sale.',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable picker over active customers; pops with the chosen [Customer].
final class _CustomerPickerDialog extends ConsumerStatefulWidget {
  const _CustomerPickerDialog();

  @override
  ConsumerState<_CustomerPickerDialog> createState() =>
      _CustomerPickerDialogState();
}

final class _CustomerPickerDialogState
    extends ConsumerState<_CustomerPickerDialog> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(posCustomersProvider);
    final query = _query.trim().toLowerCase();
    return AlertDialog(
      title: const Text('Select Customer'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchField(
              controller: _search,
              hintText: 'Search by name or phone',
              onChanged: (value) => setState(() => _query = value),
            ),
            SizedBox(height: AppSpacing.md),
            Expanded(
              child: customers.when(
                skipLoadingOnRefresh: true,
                loading: () => LoadingState(message: 'Loading customers…'),
                error: (error, stackTrace) => ErrorState(
                  message: customersErrorMessage(error),
                  onRetry: () => ref.invalidate(posCustomersProvider),
                ),
                data: (items) {
                  final filtered = query.isEmpty
                      ? items
                      : [
                          for (final customer in items)
                            if (customer.name.toLowerCase().contains(query) ||
                                (customer.phone?.toLowerCase().contains(
                                      query,
                                    ) ??
                                    false))
                              customer,
                        ];
                  if (filtered.isEmpty) {
                    return const _NoCustomersHint();
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final customer = filtered[index];
                      return ListTile(
                        leading: Icon(
                          customer.membershipActive
                              ? Icons.workspace_premium
                              : Icons.person_outline,
                          color: customer.membershipActive
                              ? AppColors.primary
                              : context.appColors.textSecondary,
                        ),
                        title: Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: context.appColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        subtitle: Text(
                          [
                            if (customer.phone != null) customer.phone!,
                            if (customer.membershipActive) 'Member',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.appColors.textSecondary,
                              ),
                        ),
                        // One-tap membership enrolment without leaving the
                        // bill: "Membership add pannunga" is a counter-level
                        // request, so the picker upgrades the profile in
                        // place and returns it; selectCustomer() then
                        // recalculates member pricing immediately.
                        trailing: customer.membershipActive
                            ? null
                            : TextButton(
                                onPressed: () =>
                                    _makeMember(context, ref, customer),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Member +'),
                              ),
                        onTap: () => Navigator.of(context).pop(customer),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _createCustomer(context, ref),
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text('Add Customer'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  /// Upgrades [customer] to an active member in place (no duplicate profile)
  /// and pops with the updated customer so the cart recalculates member
  /// pricing immediately.
  Future<void> _makeMember(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(customersRepositoryProvider)
          .updateCustomer(
            id: customer.id,
            name: customer.name,
            phone: customer.phone,
            email: customer.email,
            address: customer.address,
            isActive: customer.isActive,
            membershipActive: true,
            membershipFeePaise: customer.membershipFeePaise,
          );
    } on CustomersFailure catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } on Exception {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
          ),
        );
      return;
    }
    ref.invalidate(posCustomersProvider);
    if (context.mounted) {
      Navigator.of(context).pop(customer.copyWith(membershipActive: true));
    }
  }

  /// Inline new-customer creation without leaving billing. Pops with the
  /// created customer; the caller links it to the current sale.
  Future<void> _createCustomer(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<Customer>(
      context: context,
      builder: (_) => const _QuickCustomerFormDialog(),
    );
    if (created == null) return;
    ref.invalidate(posCustomersProvider);
    if (context.mounted) Navigator.of(context).pop(created);
  }
}

/// Minimal counter-side customer form: name required, phone optional,
/// membership enrolment optional. Reuses the existing customers repository —
/// no parallel store.
final class _QuickCustomerFormDialog extends ConsumerStatefulWidget {
  const _QuickCustomerFormDialog();

  @override
  ConsumerState<_QuickCustomerFormDialog> createState() =>
      _QuickCustomerFormDialogState();
}

final class _QuickCustomerFormDialogState
    extends ConsumerState<_QuickCustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _member = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final customer = await ref
          .read(customersRepositoryProvider)
          .createCustomer(
            name: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            membershipActive: _member,
          );
      if (!mounted) return;
      Navigator.of(context).pop(customer);
    } on CustomersFailure catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
      if (mounted) setState(() => _saving = false);
    } on Exception {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
          ),
        );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('New Customer'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Name is required'
                  : null,
            ),
            SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Membership',
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: _member,
                  onChanged: (value) => setState(() => _member = value),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

final class _NoCustomersHint extends StatelessWidget {
  const _NoCustomersHint();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.people_outline,
      title: 'No customers yet',
      message:
          'Add customers in the Customers tab to link a sale to their '
          'ledger.',
    );
  }
}

final class _ReceiptDialog extends ConsumerStatefulWidget {
  const _ReceiptDialog({required this.completed});

  final CompletedSale completed;

  @override
  ConsumerState<_ReceiptDialog> createState() => _ReceiptDialogState();
}

final class _ReceiptDialogState extends ConsumerState<_ReceiptDialog> {
  /// Linked display name resolved at open time; null for walk-in sales or
  /// when the customer can no longer be found (never blocks the receipt).
  String? _customerName;

  /// Guards against duplicate prints: the Print action stays disabled while
  /// a job is in flight, so a double-tap can never submit the receipt twice.
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _resolveCustomer();
  }

  Future<void> _resolveCustomer() async {
    final customerId = widget.completed.sale.customerId;
    if (customerId == null) return;
    final customer = await ref
        .read(customersRepositoryProvider)
        .customerById(customerId);
    if (!mounted || customer == null) return;
    setState(() => _customerName = customer.name);
  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    final sale = widget.completed.sale;
    final shopName =
        ref.read(shopSettingsProvider).value?.shopName ??
        ShopSettings.defaults().shopName;
    final document = ReceiptDocument.fromSale(
      shopName: shopName,
      sale: sale,
      items: widget.completed.items,
      customerName: _customerName,
    );
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(printerServiceProvider).print(document);
    if (!result.isFailure && !mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(result.toString()),
          duration: const Duration(seconds: 4),
        ),
      );
    if (mounted) {
      setState(() => _printing = false);
    }
  }

  Future<void> _share() async {
    final sale = widget.completed.sale;
    final shopName =
        ref.read(shopSettingsProvider).value?.shopName ??
        ShopSettings.defaults().shopName;
    final document = ReceiptDocument.fromSale(
      shopName: shopName,
      sale: sale,
      items: widget.completed.items,
      customerName: _customerName,
    );
    try {
      await ref
          .read(shareServiceProvider)
          .shareText(
            subject: 'Receipt ${sale.receiptNumber}',
            text: document.toPlainText(),
          );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Could not open sharing.')),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sale = widget.completed.sale;
    final notPaid = sale.paymentStatus == PaymentStatus.notPaid;
    return AlertDialog(
      icon: const Icon(
        Icons.check_circle,
        size: AppSpacing.ultra,
        color: AppColors.success,
      ),
      title: const Text('Sale Complete'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Receipt ${sale.receiptNumber}',
            style: textTheme.bodyLarge?.copyWith(
              color: context.appColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            notPaid
                ? '${widget.completed.items.length} item${widget.completed.items.length == 1 ? '' : 's'} '
                      '· ${Money.formatPaise(sale.totalPaise)} · Not paid'
                : '${widget.completed.items.length} item${widget.completed.items.length == 1 ? '' : 's'} '
                      '· ${Money.formatPaise(sale.totalPaise)} · ${_paymentLabel(sale.paymentMethod!)}',
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
          if (notPaid) ...[
            SizedBox(height: AppSpacing.xs),
            Text(
              'Added to Customer Due: ${Money.formatPaise(sale.totalPaise)}',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (widget.completed.items.isNotEmpty) ...[
            SizedBox(height: AppSpacing.md),
            Container(
              width: 360,
              decoration: BoxDecoration(
                color: context.appColors.surfaceVariant,
                borderRadius: AppBorderRadius.md,
              ),
              child: Padding(
                padding: AppInsets.card,
                child: Column(
                  children: [
                    for (var i = 0; i < widget.completed.items.length; i++) ...[
                      if (i > 0) const Divider(height: AppSpacing.md),
                      _ReceiptItemRow(item: widget.completed.items[i]),
                    ],
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: AppSpacing.sm),
          Text(
            'Keep this receipt number for customer reference.',
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        SecondaryButton(
          label: _printing ? 'Printing…' : 'Print',
          icon: Icons.print_outlined,
          onPressed: _printing ? null : _print,
        ),
        SecondaryButton(
          label: 'Share Bill',
          icon: Icons.share_outlined,
          onPressed: _share,
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.add),
          label: const Text('New Sale'),
        ),
      ],
    );
  }

  static String _paymentLabel(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.upi => 'UPI',
    PaymentMethod.bank => 'Bank',
  };
}

/// One persisted line rendered inside the post-sale receipt dialog.
final class _ReceiptItemRow extends StatelessWidget {
  const _ReceiptItemRow({required this.item});

  final SaleItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            item.variantName == null
                ? item.productName
                : '${item.productName} — ${item.variantName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Text(
          '${Money.formatPaise(item.unitPricePaise)} × ${item.quantity}',
          style: textTheme.bodySmall?.copyWith(
            color: context.appColors.textSecondary,
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Text(
          Money.formatPaise(item.lineTotalPaise),
          style: textTheme.bodySmall?.copyWith(
            color: context.appColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet listing bills held at the counter, each with Resume and
/// Delete actions. Holds are pure in-memory state, so nothing here touches
/// the repository.
final class _HeldBillsSheet extends ConsumerWidget {
  const _HeldBillsSheet({required this.onResume, required this.onDelete});

  /// Confirms + resumes a bill; true when it was actually resumed (the sheet
  /// then closes so the restored cart is visible).
  final Future<bool> Function(HeldBill bill) onResume;

  /// Confirms + deletes a bill; true when it was actually deleted (the sheet
  /// stays open so more bills can be managed).
  final Future<bool> Function(int displayNumber, HeldBill bill) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final heldBills = ref.watch(heldBillsProvider);
    final customers = ref.watch(posCustomersProvider).value ?? const [];
    return SafeArea(
      child: Padding(
        padding: AppInsets.screen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Held Bills',
                      style: textTheme.titleMedium?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (heldBills.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.softGreen,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '${heldBills.length} held',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (heldBills.isEmpty)
                const _NoHeldBillsHint()
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: heldBills.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final bill = heldBills[index];
                      final number = index + 1;
                      return _HeldBillTile(
                        bill: bill,
                        displayNumber: number,
                        customerName: _customerNameOf(
                          bill.selectedCustomerId,
                          customers,
                        ),
                        onResume: () async {
                          final resumed = await onResume(bill);
                          if (resumed && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        onDelete: () => onDelete(number, bill),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _customerNameOf(String? customerId, List<Customer> customers) {
    if (customerId == null) return 'Walk-in';
    for (final customer in customers) {
      if (customer.id == customerId) return customer.name;
    }
    return 'Walk-in';
  }
}

/// Compact empty-state hint for the held-bills sheet.
final class _NoHeldBillsHint extends StatelessWidget {
  const _NoHeldBillsHint();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.appColors.surfaceVariant,
        borderRadius: AppBorderRadius.md,
      ),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 18,
            color: context.appColors.textSecondary,
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No held bills yet. Hold a bill from the cart to park it for '
              'later. Held bills are cleared on logout or app restart.',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One held bill row: identity, item count, total, hold time, actions.
final class _HeldBillTile extends StatelessWidget {
  const _HeldBillTile({
    required this.bill,
    required this.displayNumber,
    required this.customerName,
    required this.onResume,
    required this.onDelete,
  });

  final HeldBill bill;
  final int displayNumber;
  final String customerName;
  final VoidCallback onResume;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = bill.totalPaise;
    final variantLines = bill.lines.where((l) => l.variantName != null).length;
    final paidLabel = bill.paymentStatus == PaymentStatus.notPaid
        ? 'Not paid'
        : 'Paid';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#$displayNumber · $customerName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                paidLabel,
                style: textTheme.bodySmall?.copyWith(
                  color: bill.paymentStatus == PaymentStatus.notPaid
                      ? AppColors.warning
                      : context.appColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            '${bill.itemCount} item${bill.itemCount == 1 ? '' : 's'}'
            '${variantLines > 0 ? ' · $variantLines variant line${variantLines == 1 ? '' : 's'}' : ''}'
            ' · ${total == null ? '—' : Money.formatPaise(total)}'
            ' · ${_heldTimeLabel(bill.heldAt)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
              SizedBox(width: AppSpacing.xs),
              FilledButton.tonalIcon(
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Resume'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact relative hold-time label, e.g. 'held just now', 'held 2 min ago',
/// 'held 3 h ago', 'held yesterday'; falls back to the absolute date.
String _heldTimeLabel(DateTime heldAtUtc) {
  final local = heldAtUtc.toLocal();
  final difference = DateTime.now().difference(local);
  if (difference.inMinutes < 1) return 'held just now';
  if (difference.inMinutes < 60) return 'held ${difference.inMinutes} min ago';
  if (difference.inHours < 24) return 'held ${difference.inHours} h ago';
  if (difference.inDays == 1) return 'held yesterday';
  return 'held ${formatDate(heldAtUtc)}';
}
