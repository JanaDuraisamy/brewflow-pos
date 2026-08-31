import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Search Field
///
/// Pill-shaped header search with a clear action. Owns a controller when none
/// is provided; [onChanged] always fires with the live text.
/// ---------------------------------------------------------------------------

final class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    this.controller,
    this.hintText = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

final class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleText);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleText);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleText() {
    setState(() {});
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      onChanged: _handleChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: TextInputAction.search,
      style: textTheme.bodyMedium?.copyWith(color: appColors.charcoal),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: appColors.textSecondary,
        ),
        prefixIcon: Icon(Icons.search, color: appColors.textSecondary),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: appColors.textSecondary,
                ),
                tooltip: 'Clear',
                onPressed: _clear,
              ),
        isDense: true,
        filled: true,
        fillColor: appColors.lightGray,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: AppBorderRadius.pill,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppBorderRadius.pill,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppBorderRadius.pill,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
