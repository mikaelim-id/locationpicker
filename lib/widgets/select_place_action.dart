import 'package:flutter/material.dart';

/// The persistent bottom card that shows the currently selected location and a
/// primary action to confirm it.
///
/// The legacy positional API ([locationName], [onTap], [tapToSelectActionText])
/// is preserved. Newer named parameters opt into the richer card: a caption, a
/// secondary address line, loading shimmer, an enabled/disabled confirm button
/// and an inline retry affordance.
class SelectPlaceAction extends StatelessWidget {
  final String locationName;
  final String tapToSelectActionText;
  final VoidCallback onTap;

  /// Secondary, muted address line (e.g. the formatted address).
  final String? subtitle;

  /// Small uppercase caption above the address. Falls back to
  /// [tapToSelectActionText].
  final String? caption;

  /// Label for the confirm button. Falls back to [tapToSelectActionText].
  final String? confirmText;

  /// When true the address area shows shimmer placeholders and the confirm
  /// button shows a spinner.
  final bool isLoading;

  /// Whether the confirm button is tappable.
  final bool isEnabled;

  /// Dims the address (used while the map is being dragged) without changing
  /// layout, so the card never jumps.
  final bool dimmed;

  /// When provided, an inline retry button is shown next to the caption.
  final VoidCallback? onRetry;
  final String? retryText;

  SelectPlaceAction(
    this.locationName,
    this.onTap,
    this.tapToSelectActionText, {
    this.subtitle,
    this.caption,
    this.confirmText,
    this.isLoading = false,
    this.isEnabled = true,
    this.dimmed = false,
    this.onRetry,
    this.retryText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final surface = isDark
        ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.05), cs.surface)
        : cs.surface;
    final captionColor = cs.onSurface.withValues(alpha: isDark ? 0.60 : 0.62);
    final subtitleColor = cs.onSurface.withValues(alpha: isDark ? 0.70 : 0.60);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: isDark
            ? Border(
                top: BorderSide(
                    color: cs.onSurface.withValues(alpha: 0.08), width: 1))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.12),
            offset: const Offset(0, -2),
            blurRadius: 24,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // One live region over caption + address so every state change
            // (finding/dragging/error/resolved) is announced by screen readers.
            Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (caption ?? tapToSelectActionText).toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: captionColor,
                          ),
                        ),
                      ),
                      if (onRetry != null)
                        _RetryButton(
                          label: retryText ?? 'Retry',
                          color: cs.primary,
                          onTap: onRetry!,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: reduceMotion ? 0 : 160),
                      child: isLoading
                          ? Semantics(
                              key: const ValueKey('loading'),
                              label: caption ?? tapToSelectActionText,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ShimmerBar(
                                      widthFactor: 0.6,
                                      height: 18,
                                      reduceMotion: reduceMotion),
                                  const SizedBox(height: 10),
                                  _ShimmerBar(
                                      widthFactor: 0.85,
                                      height: 13,
                                      reduceMotion: reduceMotion),
                                ],
                              ),
                            )
                          : Opacity(
                              key: const ValueKey('content'),
                              opacity: dimmed ? 0.55 : 1.0,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    locationName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      height: 1.25,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  if (subtitle != null &&
                                      subtitle!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      subtitle!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.3,
                                        color: subtitleColor,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ConfirmButton(
              label: confirmText ?? tapToSelectActionText,
              enabled: isEnabled && !isLoading,
              loading: isLoading,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width primary button with press feedback and a loading state.
class _ConfirmButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  const _ConfirmButton({
    required this.label,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  @override
  State<_ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<_ConfirmButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final onPrimary =
        ThemeData.estimateBrightnessForColor(cs.primary) == Brightness.dark
            ? Colors.white
            : Colors.black;
    final bg = widget.enabled
        ? cs.primary
        : Color.alphaBlend(cs.primary.withValues(alpha: 0.38), cs.surface);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: Duration(milliseconds: reduceMotion ? 0 : 90),
        curve: Curves.easeOut,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            splashColor: onPrimary.withValues(alpha: 0.12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: reduceMotion ? 0 : 150),
                child: widget.loading
                    ? SizedBox(
                        key: const ValueKey('spinner'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(onPrimary),
                        ),
                      )
                    : Text(
                        widget.label,
                        key: const ValueKey('label'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: onPrimary,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RetryButton(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightweight self-contained shimmer placeholder (no extra dependency).
class _ShimmerBar extends StatefulWidget {
  final double widthFactor;
  final double height;
  final bool reduceMotion;

  const _ShimmerBar({
    required this.widthFactor,
    required this.height,
    required this.reduceMotion,
  });

  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.onSurface.withValues(alpha: 0.08);
    final highlight = cs.onSurface.withValues(alpha: 0.16);

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widget.widthFactor,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: widget.reduceMotion
              ? Container(height: widget.height, color: base)
              : AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = _controller.value;
                    return Container(
                      height: widget.height,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1 - 2 * (1 - t), 0),
                          end: Alignment(1 - 2 * (1 - t), 0),
                          colors: [base, highlight, base],
                          stops: const [0.35, 0.5, 0.65],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
