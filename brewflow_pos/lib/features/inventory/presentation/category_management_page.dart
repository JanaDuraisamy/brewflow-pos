import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Category Management Page
///
/// Local-first category administration: create, rename, enable/disable and
/// delete (deletion is rejected while products reference the category).
/// Pushed from the inventory page, so it carries its own scaffold.
/// ---------------------------------------------------------------------------

final class CategoryManagementPage extends ConsumerWidget {
  const CategoryManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Category'),
      ),
      body: categories.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(
          message: inventoryErrorMessage(error),
          onRetry: () => ref.invalidate(categoriesProvider),
        ),
        data: (items) => items.isEmpty
            ? _EmptyState(onAddCategory: () => _showCategoryDialog(context))
            : ListView.separated(
                padding: AppInsets.screen,
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final category = items[index];
                  return _CategoryCard(
                    category: category,
                    onToggleActive: (active) async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await ref
                            .read(categoriesProvider.notifier)
                            .setActive(category.id, active);
                      } on Object catch (error) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(inventoryErrorMessage(error))),
                        );
                      }
                    },
                    onRename: () =>
                        _showCategoryDialog(context, category: category),
                    onDelete: () => _confirmDelete(context, ref, category),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          '"${category.name}" will be removed. You can create it again '
          'anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(categoriesProvider.notifier).delete(category.id);
      messenger.showSnackBar(SnackBar(content: Text('Category deleted.')));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(inventoryErrorMessage(error))),
      );
    }
  }

  void _showCategoryDialog(BuildContext context, {Category? category}) {
    showDialog<void>(
      context: context,
      builder: (context) => CategoryNameDialog(category: category),
    );
  }
}

final class CategoryNameDialog extends ConsumerStatefulWidget {
  const CategoryNameDialog({super.key, this.category});

  /// The category being renamed; null when creating a new one.
  final Category? category;

  @override
  ConsumerState<CategoryNameDialog> createState() => CategoryNameDialogState();
}

final class CategoryNameDialogState extends ConsumerState<CategoryNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );

  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Category name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final category = widget.category;
      if (category == null) {
        await ref.read(categoriesProvider.notifier).create(name);
      } else {
        await ref.read(categoriesProvider.notifier).rename(category.id, name);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = inventoryErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'New category' : 'Rename category'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) {
          if (_error != null) {
            setState(() => _error = null);
          }
        },
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: 'Category name',
          errorText: _error,
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppBorderRadius.md,
            borderSide: BorderSide(color: context.appColors.divider),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

final class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.onToggleActive,
    required this.onRename,
    required this.onDelete,
  });

  final Category category;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: context.appColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.lg,
        side: BorderSide(color: context.appColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                category.name,
                style: textTheme.titleSmall?.copyWith(
                  color: context.appColors.textPrimary,
                ),
              ),
            ),
            Switch(value: category.isActive, onChanged: onToggleActive),
            IconButton(
              tooltip: 'Rename category',
              icon: const Icon(Icons.edit_outlined),
              color: context.appColors.textSecondary,
              onPressed: onRename,
            ),
            IconButton(
              tooltip: 'Delete category',
              icon: const Icon(Icons.delete_outline),
              color: AppColors.error,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

final class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddCategory});

  final VoidCallback onAddCategory;

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
              'Add a category to group your products.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAddCategory,
              icon: const Icon(Icons.add),
              label: const Text('Add Category'),
            ),
          ],
        ),
      ),
    );
  }
}
