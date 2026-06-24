import 'dart:async';

import 'package:flutter/material.dart';

/// Search input field used by the place picker.
///
/// Shows a leading search glyph, the text field and an animated clear button.
/// By default it draws its own rounded container; pass [bare] when an outer
/// surface (such as the floating search pill) already provides the chrome.
class SearchInput extends StatefulWidget {
  final ValueChanged<String> onSearchInput;

  /// Placeholder text. Defaults to a generic "Search place".
  final String? hintText;

  /// Whether the field should request focus on mount.
  final bool autofocus;

  /// Called when the clear button empties the field.
  final VoidCallback? onCleared;

  /// Called when the field is tapped (used to open the results panel).
  final VoidCallback? onTap;

  /// Supply to share the controller with the parent (e.g. to clear it).
  final TextEditingController? controller;

  /// Optional external focus node.
  final FocusNode? focusNode;

  /// When true, the widget draws no background/border of its own so a parent
  /// surface can own the visual chrome.
  final bool bare;

  SearchInput(
    this.onSearchInput, {
    this.hintText,
    this.autofocus = false,
    this.onCleared,
    this.onTap,
    this.controller,
    this.focusNode,
    this.bare = false,
  });

  @override
  State<StatefulWidget> createState() => SearchInputState();
}

class SearchInputState extends State<SearchInput> {
  late final TextEditingController editController;
  late final bool _ownsController;

  Timer? debouncer;

  bool hasSearchEntry = false;

  SearchInputState();

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    editController = widget.controller ?? TextEditingController();
    hasSearchEntry = editController.text.isNotEmpty;
    editController.addListener(onSearchInputChange);
  }

  @override
  void dispose() {
    debouncer?.cancel();
    editController.removeListener(onSearchInputChange);
    if (_ownsController) {
      editController.dispose();
    }
    super.dispose();
  }

  void onSearchInputChange() {
    final value = editController.text;
    final isEmpty = value.isEmpty;
    if (isEmpty != !hasSearchEntry) {
      setState(() => hasSearchEntry = !isEmpty);
    }

    // Empty input cancels any pending debounce and reports immediately so the
    // caller can clear results without waiting.
    if (isEmpty) {
      debouncer?.cancel();
      widget.onSearchInput(value);
      return;
    }

    if (debouncer?.isActive ?? false) {
      debouncer?.cancel();
    }

    debouncer = Timer(const Duration(milliseconds: 500), () {
      widget.onSearchInput(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = cs.onSurface.withValues(alpha: isDark ? 0.60 : 0.55);
    final hintColor = cs.onSurface.withValues(alpha: isDark ? 0.55 : 0.60);

    final row = Row(
      children: <Widget>[
        Icon(Icons.search, size: 22, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: editController,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onTap: widget.onTap,
            textInputAction: TextInputAction.search,
            style: TextStyle(
              fontSize: 16,
              color: cs.onSurface,
            ),
            cursorColor: cs.primary,
            decoration: InputDecoration(
              isCollapsed: true,
              hintText: widget.hintText ?? 'Search place',
              hintStyle: TextStyle(fontSize: 16, color: hintColor),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: hasSearchEntry
              ? Semantics(
                  button: true,
                  label: 'Clear search',
                  child: InkResponse(
                    key: const ValueKey('clear'),
                    radius: 22,
                    onTap: () {
                      editController.clear();
                      widget.onCleared?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 20, color: iconColor),
                    ),
                  ),
                )
              : const SizedBox(key: ValueKey('empty'), width: 20, height: 20),
        ),
      ],
    );

    if (widget.bare) {
      return row;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).canvasColor,
      ),
      child: row,
    );
  }
}
