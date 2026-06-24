import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:locationpicker/entities/entities.dart';
import 'package:locationpicker/entities/localization_item.dart';
import 'package:locationpicker/widgets/rich_suggestion.dart';
import 'package:locationpicker/widgets/search_input.dart';

/// Full-screen Places autocomplete search route.
///
/// This lives on its own route with **no GoogleMap in the widget tree**, which
/// is deliberate: a `TextField` that shares a route with the GoogleMap platform
/// view only ever focuses through Android's contended touch path, which drops
/// the first tap — the user had to tap the field several times before the cursor
/// and keyboard appeared. On a map-free route the field autofocuses on mount and
/// the keyboard shows immediately on open.
///
/// Returns the chosen [AutoCompleteItem] via `Navigator.pop`, or `null` when the
/// user backs out without selecting anything.
class PlaceSearchPage extends StatefulWidget {
  final String apiKey;
  final String hostUrl;
  final String sessionToken;
  final LocalizationItem localizationItem;

  /// Restrict autocomplete results to up to 5 countries.
  final List<String>? countries;

  /// Optional bias point so nearby results rank higher.
  final LatLng? locationBias;

  const PlaceSearchPage({
    super.key,
    required this.apiKey,
    required this.hostUrl,
    required this.sessionToken,
    required this.localizationItem,
    this.countries,
    this.locationBias,
  });

  @override
  State<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<PlaceSearchPage> {
  final TextEditingController _controller = TextEditingController();

  /// Latest query the user typed; used to drop stale responses.
  String _term = '';
  bool _loading = false;
  bool _empty = false;
  List<RichSuggestion> _suggestions = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Called by [SearchInput] after its internal debounce.
  void _onQuery(String place) {
    if (place.isEmpty) {
      _term = '';
      setState(() {
        _suggestions = [];
        _empty = false;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _empty = false;
    });
    _fetch(place);
  }

  Future<void> _fetch(String place) async {
    _term = place;
    try {
      final query = place.replaceAll(' ', '+');
      final countries = widget.countries;

      // You can filter by up to 5 countries (Places autocomplete docs).
      final regionParam = countries?.isNotEmpty == true
          ? "&components=country:${countries!.sublist(0, min(countries.length, 5)).join('|country:')}"
          : '';

      var endpoint = "https://${widget.hostUrl}/maps/api/place/autocomplete/json?"
          "key=${widget.apiKey}&"
          "language=${widget.localizationItem.languageCode}&"
          "input={$query}$regionParam&sessiontoken=${widget.sessionToken}";

      final bias = widget.locationBias;
      if (bias != null) {
        endpoint += "&location=${bias.latitude},${bias.longitude}";
      }

      final response = await http.get(Uri.parse(endpoint));
      if (response.statusCode != 200) throw Error();

      final responseJson = jsonDecode(response.body);
      if (responseJson['predictions'] == null) throw Error();

      final List<dynamic> predictions = responseJson['predictions'];

      // Drop a response that arrived after the user changed/cleared the query.
      if (place != _term || !mounted) return;

      if (predictions.isEmpty) {
        setState(() {
          _suggestions = [];
          _empty = true;
          _loading = false;
        });
        return;
      }

      final List<RichSuggestion> suggestions = [];
      for (var i = 0; i < predictions.length; i++) {
        final t = predictions[i];
        final description = (t['description'] ?? '') as String;
        final commaIndex = description.indexOf(',');
        final secondary = commaIndex == -1
            ? null
            : description.substring(commaIndex + 1).trim();
        final types = (t['types'] as List?)?.cast<String>();

        final matched = (t['matched_substrings'] as List?);
        final first =
            (matched != null && matched.isNotEmpty) ? matched.first : null;

        final aci = AutoCompleteItem()
          ..id = t['place_id']
          ..text = description
          ..offset = (first?['offset'] as int?) ?? 0
          ..length = (first?['length'] as int?) ?? 0
          ..types = types;

        suggestions.add(RichSuggestion(
          aci,
          () => Navigator.of(context).pop(aci),
          secondaryText: secondary,
          leadingIcon: _iconForTypes(types),
          showDivider: i != predictions.length - 1,
        ));
      }

      setState(() {
        _suggestions = suggestions;
        _empty = false;
        _loading = false;
      });
    } catch (e) {
      debugPrint('PlaceSearchPage autocomplete error: $e');
      if (place != _term || !mounted) return;
      setState(() {
        _suggestions = [];
        _empty = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final loc = widget.localizationItem;

    final surface = isDark
        ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.05), cs.surface)
        : cs.surface;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Search bar: back affordance + the autofocusing field.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  _CircleIconButton(
                    icon: Icons.arrow_back,
                    semanticLabel: 'Go back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: isDark
                            ? Border.all(
                                color: cs.onSurface.withValues(alpha: 0.08))
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.30 : 0.06),
                            offset: const Offset(0, 2),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        // autofocus: the field is on a map-free route, so this
                        // reliably focuses and shows the keyboard on open.
                        child: SearchInput(
                          _onQuery,
                          bare: true,
                          autofocus: true,
                          hintText: loc.searchHint,
                          controller: _controller,
                          onCleared: () => _onQuery(''),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildResults(cs, isDark, media, loc)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(
      ColorScheme cs, bool isDark, MediaQueryData media, LocalizationItem loc) {
    if (_loading) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          LinearProgressIndicator(
            minHeight: 3,
            backgroundColor: cs.primary.withValues(alpha: 0.10),
            valueColor: AlwaysStoppedAnimation(cs.primary),
          ),
          for (int i = 0; i < 5; i++) _SkeletonRow(isLast: i == 4),
        ],
      );
    }

    if (_empty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off,
                    size: 40, color: cs.onSurface.withValues(alpha: 0.30)),
                const SizedBox(height: 12),
                Text(loc.noResultsFound,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(loc.noResultsHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.60))),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: media.padding.bottom + 8),
      children: _suggestions,
    );
  }

  IconData _iconForTypes(List<String>? types) {
    if (types == null) return Icons.location_on;
    if (types.contains('airport')) return Icons.flight;
    if (types.contains('lodging')) return Icons.hotel;
    if (types.contains('restaurant') ||
        types.contains('food') ||
        types.contains('cafe')) {
      return Icons.restaurant;
    }
    if (types.contains('transit_station') ||
        types.contains('subway_station') ||
        types.contains('train_station') ||
        types.contains('bus_station')) {
      return Icons.directions_transit;
    }
    if (types.contains('street_address') || types.contains('route')) {
      return Icons.route;
    }
    if (types.contains('locality') ||
        types.contains('administrative_area_level_1') ||
        types.contains('political')) {
      return Icons.location_city;
    }
    if (types.contains('establishment') ||
        types.contains('point_of_interest')) {
      return Icons.place;
    }
    return Icons.location_on;
  }
}

/// Small circular icon button used for the back affordance on the search bar.
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: cs.onSurface, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Static placeholder row shown while autocomplete results load.
class _SkeletonRow extends StatelessWidget {
  final bool isLast;
  const _SkeletonRow({required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final block = cs.onSurface.withValues(alpha: 0.08);
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
              color: block, borderRadius: BorderRadius.circular(6)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: block, borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(160, 13),
                const SizedBox(height: 8),
                bar(100, 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
