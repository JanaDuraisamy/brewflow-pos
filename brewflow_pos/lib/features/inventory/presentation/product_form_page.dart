import 'dart:io';

import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_picker.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_store.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/product_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/widgets.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Form Page
///
/// Create or edit a product. Prices are entered in rupees and converted to
/// exact paise; stock accepts digits only (negative quantities are blocked by
/// the input format, the repository and the database CHECK constraint).
/// Pushed from the inventory page, so it carries its own scaffold.
///
/// The form is a SingleChildScrollView (never a lazy list) so every field —
/// including every variant card — stays mounted and validates on submit.
/// ---------------------------------------------------------------------------

final class ProductFormPage extends ConsumerStatefulWidget {
  const ProductFormPage({super.key, this.product});

  /// The product being edited; null when creating a new one.
  final Product? product;

  @override
  ConsumerState<ProductFormPage> createState() => ProductFormPageState();
}

/// Mutable editor state for one variant row. Owns its text controllers (they
/// survive rebuilds and lazy disposal); the parent list holds one instance
/// per variant in the form.
final class _VariantEditor {
  _VariantEditor({
    this.id,
    String name = '',
    String sku = '',
    String selling = '',
    String cost = '',
    String stock = '0',
    this.lowStockMode = LowStockMode.useDefault,
    String threshold = '',
    this.membershipEnabled = false,
    String memberPrice = '',
    this.isActive = true,
  }) : nameC = TextEditingController(text: name),
       skuC = TextEditingController(text: sku),
       sellingC = TextEditingController(text: selling),
       costC = TextEditingController(text: cost),
       stockC = TextEditingController(text: stock),
       thresholdC = TextEditingController(text: threshold),
       memberPriceC = TextEditingController(text: memberPrice);

  /// Id of an existing variant this editor updates; null for a new variant
  /// (whose stock field is its opening stock).
  final String? id;

  final TextEditingController nameC;
  final TextEditingController skuC;
  final TextEditingController sellingC;
  final TextEditingController costC;
  final TextEditingController stockC;
  final TextEditingController thresholdC;
  final TextEditingController memberPriceC;

  LowStockMode lowStockMode;
  bool membershipEnabled;
  bool isActive;

  bool get isNew => id == null;

  String? get sku => _normalized(skuC.text);

  /// Builds the repository input from the controllers. Safe to call only
  /// after the form has validated (every field is always mounted).
  ProductVariantInput buildInput() => ProductVariantInput(
    id: id,
    name: nameC.text.trim(),
    sku: sku,
    sellingPricePaise: Money.parseRupeesToPaise(sellingC.text)!,
    costPricePaise: _priceOrNull(costC.text),
    stockQuantity: isNew ? int.parse(stockC.text.trim()) : 0,
    lowStockMode: lowStockMode,
    lowStockThreshold: lowStockMode == LowStockMode.custom
        ? int.tryParse(thresholdC.text.trim())
        : null,
    membershipEnabled: membershipEnabled,
    memberPricePaise: membershipEnabled
        ? Money.parseRupeesToPaise(memberPriceC.text)
        : null,
    isActive: isActive,
  );

  void dispose() {
    nameC.dispose();
    skuC.dispose();
    sellingC.dispose();
    costC.dispose();
    stockC.dispose();
    thresholdC.dispose();
    memberPriceC.dispose();
  }

  static int? _priceOrNull(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return Money.parseRupeesToPaise(trimmed);
  }

  static String? _normalized(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

final class ProductFormPageState extends ConsumerState<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name = TextEditingController(
    text: widget.product?.name ?? '',
  );

  late final TextEditingController _sku = TextEditingController(
    text: widget.product?.sku ?? '',
  );

  late final TextEditingController _selling = TextEditingController(
    text: widget.product == null
        ? ''
        : Money.paiseToRupeesInput(widget.product!.sellingPricePaise),
  );

  late final TextEditingController _cost = TextEditingController(
    text: widget.product?.costPricePaise == null
        ? ''
        : Money.paiseToRupeesInput(widget.product!.costPricePaise!),
  );

  late final TextEditingController _stock = TextEditingController(
    text: (widget.product?.stockQuantity ?? 0).toString(),
  );

  late final TextEditingController _threshold = TextEditingController(
    text: widget.product?.lowStockThreshold?.toString() ?? '',
  );

  late final TextEditingController _memberPrice = TextEditingController(
    text: widget.product?.memberPricePaise == null
        ? ''
        : Money.paiseToRupeesInput(widget.product!.memberPricePaise!),
  );

  late String? _categoryId = widget.product?.categoryId;
  late StockUnit _stockUnit = widget.product?.stockUnit ?? StockUnit.count;
  late LowStockMode _lowStockMode =
      widget.product?.lowStockMode ?? LowStockMode.useDefault;
  late bool _membershipEnabled = widget.product?.membershipEnabled ?? false;
  late bool _isActive = widget.product?.isActive ?? true;
  final List<_VariantEditor> _variants = [];
  String? _skuError;
  bool _saving = false;

  /// Image picked from the gallery this session; null until the user picks
  /// one. Previewed from the picker cache and copied into persistent storage
  /// only when the form is saved.
  File? _pickedImage;

  /// Set when the user asks to remove the current image; the stored file is
  /// deleted only after the product update commits.
  bool _removeImage = false;

  bool get _editing => widget.product != null;

  /// Whether the form currently carries at least one variant.
  bool get _hasVariants => _variants.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product != null) {
      for (final variant in product.variants) {
        _variants.add(
          _VariantEditor(
            id: variant.id,
            name: variant.name,
            sku: variant.sku ?? '',
            selling: Money.paiseToRupeesInput(variant.sellingPricePaise),
            cost: variant.costPricePaise == null
                ? ''
                : Money.paiseToRupeesInput(variant.costPricePaise!),
            stock: variant.stockQuantity.toString(),
            lowStockMode: variant.lowStockMode,
            threshold: variant.lowStockThreshold?.toString() ?? '',
            membershipEnabled: variant.membershipEnabled,
            memberPrice: variant.memberPricePaise == null
                ? ''
                : Money.paiseToRupeesInput(variant.memberPricePaise!),
            isActive: variant.isActive,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _selling.dispose();
    _cost.dispose();
    _stock.dispose();
    _threshold.dispose();
    _memberPrice.dispose();
    for (final variant in _variants) {
      variant.dispose();
    }
    super.dispose();
  }

  void _addVariant() {
    setState(() => _variants.add(_VariantEditor()));
  }

  void _removeVariant(_VariantEditor variant) {
    setState(() {
      _variants.remove(variant);
      variant.dispose();
    });
  }

  Future<void> _pickImage() async {
    final picked = await ref.read(productImagePickerProvider).pickGallery();
    if (picked == null || !mounted) {
      // Cancelled picker: keep whatever is currently shown.
      return;
    }
    setState(() {
      _pickedImage = picked.file;
      _removeImage = false;
    });
  }

  /// Resolves the image [Product.imagePath] that should be persisted: the
  /// replacement when the user picked one, null when they removed it, or the
  /// existing reference untouched. Throws when the new image could not be
  /// copied — the save is aborted and the existing reference is preserved.
  Future<String?> _resolveImagePath() async {
    final previous = widget.product?.imagePath;
    if (_removeImage) {
      return null;
    }
    if (_pickedImage == null) {
      return previous;
    }
    final store = await ref.read(productImageStoreProvider.future);
    return store.saveFrom(_pickedImage!);
  }

  /// Cleans up the previous image file after the product record committed to
  /// a new (or no) image. Failures are logged, never surfaced: an orphaned
  /// file is harmless and must not block the user flow.
  Future<void> _cleanupOldImage(String? previousPath, String? nextPath) async {
    if (previousPath == null || previousPath == nextPath) {
      return;
    }
    final store = await ref.read(productImageStoreProvider.future);
    try {
      await store.delete(previousPath);
    } on Object catch (error, stackTrace) {
      AppLog.error(
        'Failed to delete replaced product image',
        tag: 'Inventory',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _skuError = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final sku = _sku.text.trim();
    final variantSkus = [
      for (final variant in _variants)
        if (variant.sku != null) variant.sku!,
    ];
    final seen = <String>{};
    if (sku.isNotEmpty && !seen.add(sku.toLowerCase())) {
      setState(() => _skuError = 'A product with this SKU already exists.');
      return;
    }
    for (final variantSku in variantSkus) {
      final lower = variantSku.toLowerCase();
      if (!seen.add(lower)) {
        _showMessage('A variant with this SKU already exists.');
        return;
      }
    }
    try {
      final controller = ref.read(productsProvider.notifier);
      for (final unique in seen) {
        final exists = await controller.skuExists(
          unique,
          exceptId: widget.product?.id,
        );
        if (exists) {
          if (sku.isNotEmpty && unique == sku.toLowerCase()) {
            setState(
              () => _skuError = 'A product with this SKU already exists.',
            );
          } else {
            _showMessage('A variant with this SKU already exists.');
          }
          return;
        }
      }
    } on Object catch (error) {
      _showMessage(inventoryErrorMessage(error));
      return;
    }

    setState(() => _saving = true);
    try {
      String? imagePath;
      try {
        imagePath = await _resolveImagePath();
      } on Object {
        _showMessage('Could not save the product image. Please try again.');
        setState(() => _saving = false);
        return;
      }
      final sellingPaise = Money.parseRupeesToPaise(_selling.text)!;
      final costText = _cost.text.trim();
      final costPaise = costText.isEmpty
          ? null
          : Money.parseRupeesToPaise(costText);
      final lowStockThreshold = _lowStockMode == LowStockMode.custom
          ? int.tryParse(_threshold.text.trim())
          : null;
      final memberPricePaise = _membershipEnabled
          ? Money.parseRupeesToPaise(_memberPrice.text)
          : null;
      final variants = [for (final variant in _variants) variant.buildInput()];
      final controller = ref.read(productsProvider.notifier);
      if (_editing) {
        await controller.updateProduct(
          id: widget.product!.id,
          categoryId: _categoryId!,
          name: _name.text.trim(),
          sku: sku,
          sellingPricePaise: sellingPaise,
          costPricePaise: costPaise,
          // Stock is managed only through stock operations (openings,
          // purchases, sales and adjustments); editing a product never
          // changes it, so the read-only field cannot alter the quantity.
          stockQuantity: widget.product!.stockQuantity,
          imagePath: imagePath,
          stockUnit: _stockUnit,
          lowStockMode: _lowStockMode,
          lowStockThreshold: lowStockThreshold,
          membershipEnabled: _membershipEnabled,
          memberPricePaise: memberPricePaise,
          isActive: _isActive,
          variants: variants,
        );
      } else {
        await controller.create(
          categoryId: _categoryId!,
          name: _name.text.trim(),
          sku: sku,
          sellingPricePaise: sellingPaise,
          costPricePaise: costPaise,
          stockQuantity: int.parse(_stock.text.trim()),
          imagePath: imagePath,
          stockUnit: _stockUnit,
          lowStockMode: _lowStockMode,
          lowStockThreshold: lowStockThreshold,
          membershipEnabled: _membershipEnabled,
          memberPricePaise: memberPricePaise,
          isActive: _isActive,
          variants: variants,
        );
      }
      await _cleanupOldImage(widget.product?.imagePath, imagePath);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_editing ? 'Product updated.' : 'Product added.'),
        ),
      );
      if (mounted) {
        context.pop();
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(inventoryErrorMessage(error))),
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Product' : 'New Product')),
      body: categories.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _CategoriesErrorState(
          message: inventoryErrorMessage(error),
          onRetry: () => ref.invalidate(categoriesProvider),
        ),
        data: (items) =>
            items.isEmpty ? const _NoCategoriesState() : _buildForm(items),
      ),
    );
  }

  Widget _buildForm(List<Category> categories) {
    final textTheme = Theme.of(context).textTheme;
    // One tall, always-mounted sliver for the fields (validators and inline
    // errors keep working off-screen) plus a separate sliver for the action
    // buttons, which only mounts once scrolled near (tests rely on that).
    return Form(
      key: _formKey,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: AppInsets.screen,
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _editing
                        ? 'Update the details below.'
                        : 'Fill in the product details below.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ProductImageSection(
                    imagePath: widget.product?.imagePath,
                    pickedImage: _pickedImage,
                    removing: _removeImage,
                    enabled: !_saving,
                    onPick: _pickImage,
                    onRemove: () => setState(() {
                      _pickedImage = null;
                      _removeImage = true;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Product name *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Product name is required.'
                        : null,
                  ),
                  SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _sku,
                    decoration: InputDecoration(
                      labelText: 'SKU (optional)',
                      errorText: _skuError,
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppBorderRadius.md,
                        borderSide: BorderSide(
                          color: context.appColors.divider,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DropdownButtonFormField<String>(
                    initialValue: categories.any((c) => c.id == _categoryId)
                        ? _categoryId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Category *',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select a category'),
                    items: [
                      for (final category in categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _categoryId = value),
                    validator: (value) =>
                        value == null ? 'Select a category.' : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _selling,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Selling price (₹) *',
                      hintText: 'e.g. 149.50',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        Money.parseRupeesToPaise(value ?? '') == null
                        ? 'Enter a valid price (e.g. 149.50)'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cost price (₹)',
                      hintText: 'Optional',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return null;
                      }
                      return Money.parseRupeesToPaise(text) == null
                          ? 'Enter a valid price (e.g. 149.50)'
                          : null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _stock,
                    enabled: !_editing,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Stock quantity *',
                      border: const OutlineInputBorder(),
                      helperText: _editing
                          ? 'Managed through stock operations — use a stock '
                                'adjustment to correct levels.'
                          : _hasVariants
                          ? 'Stock is entered per variant below.'
                          : null,
                    ),
                    validator: (value) =>
                        int.tryParse(value?.trim() ?? '') == null
                        ? 'Enter a valid quantity.'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: AppInsets.zero,
                    title: const Text('Active product'),
                    subtitle: const Text(
                      'Hides the product from new sales when off.',
                    ),
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _StockUnitSection(
                    stockUnit: _stockUnit,
                    onChanged: (value) => setState(() => _stockUnit = value),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _LowStockSection(
                    mode: _lowStockMode,
                    thresholdController: _threshold,
                    onModeChanged: (mode) =>
                        setState(() => _lowStockMode = mode),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _MembershipSection(
                    enabled: _membershipEnabled,
                    priceController: _memberPrice,
                    onChanged: (enabled) =>
                        setState(() => _membershipEnabled = enabled),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _VariantsSection(
                    variants: _variants,
                    onAdd: _addVariant,
                    onRemove: _removeVariant,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: AppInsets.screen,
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => context.pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_editing ? 'Save Changes' : 'Save Product'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Product photo picker block: preview + choose/replace + remove actions.
/// The picked file is only previewed here; it is copied into persistent
/// storage when the form saves.
final class _ProductImageSection extends StatelessWidget {
  const _ProductImageSection({
    required this.imagePath,
    required this.pickedImage,
    required this.removing,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  /// Currently stored relative image path (edit mode).
  final String? imagePath;

  /// Image picked this session, if any (takes preview priority).
  final File? pickedImage;

  /// Whether the user asked to remove the image.
  final bool removing;

  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  bool get _hasImage => pickedImage != null || (imagePath != null && !removing);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Product Image',
      subtitle: 'Optional photo shown across inventory and the POS.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: AppBorderRadius.md,
            child: SizedBox(
              width: 72,
              height: 72,
              child: pickedImage != null
                  ? Image.file(pickedImage!, fit: BoxFit.cover)
                  : ProductThumbnail(
                      imagePath: removing ? null : imagePath,
                      size: 72,
                    ),
            ),
          ),
          SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: enabled ? onPick : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_hasImage ? 'Change Image' : 'Choose Image'),
                ),
                if (_hasImage)
                  TextButton.icon(
                    onPressed: enabled ? onRemove : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove Image'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                  ),
                if (removing)
                  Text(
                    'The stored image will be removed when you save.',
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
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

/// Stock-counting unit for the product; feeds the whole inventory display.
final class _StockUnitSection extends StatelessWidget {
  const _StockUnitSection({required this.stockUnit, required this.onChanged});

  final StockUnit stockUnit;
  final ValueChanged<StockUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Stock Unit',
      subtitle: 'How this product is counted across the shop.',
      child: DropdownButtonFormField<StockUnit>(
        initialValue: stockUnit,
        decoration: const InputDecoration(
          labelText: 'Stock unit',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final unit in StockUnit.values)
            DropdownMenuItem(value: unit, child: Text(unit.label)),
        ],
        onChanged: (value) => onChanged(value!),
      ),
    );
  }
}

final class _LowStockSection extends StatelessWidget {
  const _LowStockSection({
    required this.mode,
    required this.thresholdController,
    required this.onModeChanged,
  });

  final LowStockMode mode;
  final TextEditingController thresholdController;
  final ValueChanged<LowStockMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Low Stock Alert',
      subtitle: 'Flags items running low before they run out.',
      child: Column(
        children: [
          DropdownButtonFormField<LowStockMode>(
            initialValue: mode,
            decoration: const InputDecoration(
              labelText: 'Alert mode',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: LowStockMode.useDefault,
                child: Text('Use the shop default'),
              ),
              DropdownMenuItem(
                value: LowStockMode.custom,
                child: Text('Set a custom level'),
              ),
              DropdownMenuItem(
                value: LowStockMode.off,
                child: Text('No alert'),
              ),
            ],
            onChanged: (value) => onModeChanged(value!),
          ),
          if (mode == LowStockMode.custom) ...[
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: thresholdController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Low stock level *',
                border: OutlineInputBorder(),
                helperText:
                    'Stock at or below this level counts as low. '
                    'The shop default is used when nothing is set here.',
              ),
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                if (parsed == null || parsed <= 0) {
                  return 'Enter a number above 0.';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }
}

final class _MembershipSection extends StatelessWidget {
  const _MembershipSection({
    required this.enabled,
    required this.priceController,
    required this.onChanged,
  });

  final bool enabled;
  final TextEditingController priceController;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Membership',
      subtitle: 'Sell to members at a special price.',
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: AppInsets.zero,
            title: const Text('Member pricing'),
            subtitle: const Text('Members pay the member price when enabled.'),
            value: enabled,
            onChanged: onChanged,
          ),
          if (enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Member price (₹) *',
                hintText: 'e.g. 129.00',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  Money.parseRupeesToPaise(value ?? '') == null
                  ? 'Enter a valid member price (e.g. 149.50)'
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

final class _VariantsSection extends StatelessWidget {
  const _VariantsSection({
    required this.variants,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_VariantEditor> variants;
  final VoidCallback onAdd;
  final ValueChanged<_VariantEditor> onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Variants',
      subtitle:
          'Sell one product in multiple options — each with its own SKU, '
          'prices and stock.',
      trailing: TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add Variant'),
      ),
      child: variants.isEmpty
          ? Text(
              'No variants yet. Variants are useful for sizes, flavours or '
              'packs sold under one product name.',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            )
          : Column(
              children: [
                for (final (index, variant) in variants.indexed) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.md),
                  _VariantEditorCard(
                    index: index,
                    variant: variant,
                    onChanged: () {},
                    onRemove: () => onRemove(variant),
                  ),
                ],
              ],
            ),
    );
  }
}

/// One editable variant row inside the form. Stateless: all state (including
/// the text controllers) lives in the parent-owned [_VariantEditor], so the
/// card can be rebuilt or scrolled away without losing input.
final class _VariantEditorCard extends StatelessWidget {
  const _VariantEditorCard({
    required this.index,
    required this.variant,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _VariantEditor variant;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Variant ${index + 1}',
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remove variant',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (!variant.isNew) ...[
            SizedBox(height: AppSpacing.xs),
            Text(
              'Removing deactivates this variant and keeps its history.',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: variant.nameC,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Variant name *',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Variant name is required.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: variant.skuC,
            decoration: const InputDecoration(
              labelText: 'SKU (optional)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: variant.sellingC,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Selling price (₹) *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => onChanged(),
                  validator: (value) =>
                      Money.parseRupeesToPaise(value ?? '') == null
                      ? 'Enter a valid variant price (e.g. 149.50)'
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  controller: variant.costC,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cost price (₹)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => onChanged(),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return null;
                    }
                    return Money.parseRupeesToPaise(text) == null
                        ? 'Enter a valid variant price (e.g. 149.50)'
                        : null;
                  },
                ),
              ),
            ],
          ),
          if (variant.isNew) ...[
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: variant.stockC,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Opening stock *',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
              validator: (value) => int.tryParse(value?.trim() ?? '') == null
                  ? 'Enter a valid quantity.'
                  : null,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: variant.stockC,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Current stock',
                border: OutlineInputBorder(),
                helperText:
                    'Managed through stock operations — use a stock '
                    'adjustment to correct levels.',
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<LowStockMode>(
            initialValue: variant.lowStockMode,
            decoration: const InputDecoration(
              labelText: 'Low stock alert',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: LowStockMode.useDefault,
                child: Text('Use the product default'),
              ),
              DropdownMenuItem(
                value: LowStockMode.custom,
                child: Text('Set a custom level'),
              ),
              DropdownMenuItem(
                value: LowStockMode.off,
                child: Text('No alert'),
              ),
            ],
            onChanged: (value) {
              variant.lowStockMode = value!;
              onChanged();
            },
          ),
          if (variant.lowStockMode == LowStockMode.custom) ...[
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: variant.thresholdC,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Low stock level *',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                if (parsed == null || parsed <= 0) {
                  return 'Enter a number above 0.';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            contentPadding: AppInsets.zero,
            title: const Text('Member pricing'),
            value: variant.membershipEnabled,
            onChanged: (value) {
              variant.membershipEnabled = value;
              onChanged();
            },
          ),
          if (variant.membershipEnabled) ...[
            TextFormField(
              controller: variant.memberPriceC,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Member price (₹) *',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
              validator: (value) =>
                  Money.parseRupeesToPaise(value ?? '') == null
                  ? 'Enter a valid member price (e.g. 149.50)'
                  : null,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            contentPadding: AppInsets.zero,
            title: const Text('Active variant'),
            subtitle: const Text('Hides the variant from new sales when off.'),
            value: variant.isActive,
            onChanged: (value) {
              variant.isActive = value;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

final class _CategoriesErrorState extends StatelessWidget {
  const _CategoriesErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: AppSpacing.ultra,
              color: AppColors.error,
            ),
            SizedBox(height: AppSpacing.lg),
            Text(
              'Could not load categories',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _NoCategoriesState extends StatelessWidget {
  const _NoCategoriesState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.category_outlined,
              size: AppSpacing.ultra,
              color: AppColors.primary,
            ),
            SizedBox(height: AppSpacing.lg),
            Text(
              'No categories yet',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              'Add a category before creating products.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.inventoryCategories),
              icon: const Icon(Icons.add),
              label: const Text('Add Category'),
            ),
          ],
        ),
      ),
    );
  }
}
