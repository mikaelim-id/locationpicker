import 'package:flutter/material.dart';
import 'package:locationpicker/entities/entities.dart';

/// A single autocomplete suggestion row.
///
/// Renders a leading place-type icon chip, the matched portion of the query in
/// bold, and an optional muted secondary line (e.g. the locality).
class RichSuggestion extends StatelessWidget {
  final VoidCallback onTap;
  final AutoCompleteItem autoCompleteItem;

  /// Optional muted second line under the primary text.
  final String? secondaryText;

  /// Leading glyph. Defaults to a location pin.
  final IconData leadingIcon;

  /// Whether to draw a hairline divider under the row.
  final bool showDivider;

  /// Tighter vertical padding for compact lists.
  final bool dense;

  RichSuggestion(
    this.autoCompleteItem,
    this.onTap, {
    this.secondaryText,
    this.leadingIcon = Icons.location_on,
    this.showDivider = true,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSecondary =
        secondaryText != null && secondaryText!.trim().isNotEmpty;

    final primaryText = hasSecondary
        ? _beforeFirstComma(autoCompleteItem.text)
        : autoCompleteItem.text;

    return Semantics(
      button: true,
      label: hasSecondary
          ? '$primaryText, ${secondaryText!}'
          : autoCompleteItem.text,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashColor: cs.primary.withValues(alpha: 0.10),
          highlightColor: cs.primary.withValues(alpha: 0.06),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: dense ? 10 : 13,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color:
                            cs.primary.withValues(alpha: isDark ? 0.18 : 0.09),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(leadingIcon, size: 20, color: cs.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              children: _styledPrimary(context, primaryText),
                            ),
                          ),
                          if (hasSecondary) ...[
                            const SizedBox(height: 2),
                            Text(
                              secondaryText!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface
                                    .withValues(alpha: isDark ? 0.62 : 0.62),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (showDivider)
                Padding(
                  padding: const EdgeInsets.only(left: 68),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: cs.onSurface.withValues(alpha: isDark ? 0.10 : 0.07),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _beforeFirstComma(String text) {
    final i = text.indexOf(',');
    return i == -1 ? text : text.substring(0, i);
  }

  /// Builds the primary line, bolding the matched substring reported by the
  /// Places API. The match range is clamped to the displayed text so a match
  /// that falls in the (now hidden) secondary part doesn't throw.
  List<TextSpan> _styledPrimary(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final base = TextStyle(
      fontSize: 15,
      color: cs.onSurface.withValues(alpha: isDark ? 0.65 : 0.62),
    );
    final highlight = base.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w600,
    );

    final len = text.length;
    final start = autoCompleteItem.offset.clamp(0, len);
    final end =
        (autoCompleteItem.offset + autoCompleteItem.length).clamp(0, len);

    if (start >= end) {
      return [TextSpan(text: text, style: base)];
    }

    return [
      if (start > 0) TextSpan(text: text.substring(0, start), style: base),
      TextSpan(text: text.substring(start, end), style: highlight),
      if (end < len) TextSpan(text: text.substring(end), style: base),
    ];
  }
}
