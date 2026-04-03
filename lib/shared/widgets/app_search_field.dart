import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class AppSearchField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final TextEditingController? controller;
  final String? initialValue;
  final FocusNode? focusNode;

  const AppSearchField({
    super.key,
    this.hintText = 'Search...',
    required this.onChanged,
    this.onClear,
    this.controller,
    this.initialValue,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon:
            (controller?.text.isNotEmpty ?? initialValue?.isNotEmpty ?? false)
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onClear ?? () => controller?.clear(),
                  )
                : null,
        filled: true,
        fillColor: isDark ? AppTheme.inputBgDark : AppTheme.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusInput),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: AppTheme.spacingSm,
        ),
      ),
    );
  }
}
