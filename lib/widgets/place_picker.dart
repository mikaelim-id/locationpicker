import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:locationpicker/entities/entities.dart';
import 'package:locationpicker/entities/localization_item.dart';
import 'package:locationpicker/widgets/widgets.dart';

import '../uuid.dart';

/// Default camera target used until a real location is resolved.
const LatLng _kDefaultCenter = LatLng(5.6037, 0.1870);

/// Size of the circular back button; the search pill matches this height.
const double _kControlSize = 48.0;

/// The visible lifecycle of the bottom selection card.
enum _CardState { initial, dragging, resolving, resolved, error }

/// A modern, ride-hailing style place picker.
///
/// The map pans under a fixed center pin and the address resolves whenever the
/// camera comes to rest. A floating search surface offers Places autocomplete,
/// and a persistent bottom card confirms the selection. Tapping the map is also
/// supported as a secondary way to drop the pin.
///
/// Built on
/// [google_maps_flutter](https://github.com/flutter/plugins/tree/master/packages/google_maps_flutter)
/// and the [Google Places API](https://developers.google.com/places/web-service/intro).
///
/// The API key provided should have `Maps SDK for Android`, `Maps SDK for iOS`
/// and `Places API` enabled for it.
class PlacePicker extends StatefulWidget {
  /// API key generated from Google Cloud Console. You can get an API key
  /// [here](https://cloud.google.com/maps-platform/)
  final String apiKey;

  /// Host used for the Places/Geocoding HTTP calls. Defaults to
  /// `maps.googleapis.com`; only honored on web.
  final String? hostUrl;

  /// Location to be displayed when screen is showed. If this is set, the map
  /// does not pan to the user's current location.
  final LatLng? displayLocation;

  /// All user-facing strings, for localization.
  final LocalizationItem localizationItem;

  /// Restrict autocomplete results to up to 5 countries.
  final List<String>? countries;

  /// Optional Google Maps JSON style applied in dark mode. Pass an empty string
  /// to disable the bundled dark style.
  final String? mapStyleDark;

  /// Optional Google Maps JSON style applied in light mode.
  final String? mapStyleLight;

  PlacePicker(
    this.apiKey, {
    String? hostUrl,
    this.displayLocation,
    LocalizationItem? localizationItem,
    this.countries,
    this.mapStyleDark,
    this.mapStyleLight,
  })  : localizationItem = localizationItem ?? LocalizationItem(),
        hostUrl =
            (!kIsWeb || hostUrl == null) ? 'maps.googleapis.com' : hostUrl;

  @override
  State<StatefulWidget> createState() => PlacePickerState();
}

/// Place picker state
class PlacePickerState extends State<PlacePicker>
    with TickerProviderStateMixin {
  final Completer<GoogleMapController> mapController = Completer();

  /// Result returned after user completes selection.
  LocationResult? locationResult;

  /// Session token required for autocomplete API call.
  String sessionToken = Uuid().generateV4();

  String previousSearchTerm = '';

  /// When a search suggestion is tapped, the GoogleMap platform view beneath
  /// the autocomplete panel can also receive the same tap and fire
  /// [GoogleMap.onTap] (a known Android texture-layer hybrid-composition touch
  /// leak). That leaked tap would reverse-geocode the tapped coordinate and
  /// overwrite the place the user actually selected, panning the map away.
  /// The leaked tap is delivered asynchronously via the platform channel, so it
  /// always arrives just after the synchronous suggestion tap — this flag lets
  /// us swallow exactly that one tap. It is cleared the moment the leaked tap is
  /// consumed, and on a short timer as a safety net so it can never eat a later,
  /// deliberate map tap on platforms where no leak occurs (e.g. iOS).
  bool suppressMapTap = false;

  /// [GoogleMap.onCameraIdle] also fires after a *programmatic* `animateCamera`
  /// (initial position, my-location, search-select, tap-to-place). In those
  /// cases the address has already been resolved by a richer code path, so the
  /// idle reverse-geocode must be skipped or it would clobber that result.
  ///
  /// Rather than a one-shot flag (which a user drag could steal mid-animation),
  /// we remember the *target* of the programmatic move. The settling idle only
  /// skips geocoding when it comes to rest near this target; if the user grabs
  /// the map and ends somewhere else, that real location still resolves. Cleared
  /// once consumed and on a safety-net timer.
  LatLng? _programmaticTarget;

  Timer? _tapSuppressionSafety;
  Timer? _idleSuppressionSafety;
  Timer? _idleDebounce;

  /// Latest camera target reported by [GoogleMap.onCameraMove].
  LatLng? _lastCameraTarget;

  /// Target of the last successful reverse-geocode (for the small-move guard).
  LatLng? _lastResolvedTarget;

  /// Set once the user manually pans the map, so the initial auto-pan to the
  /// device location never yanks the camera away from a spot they chose.
  bool _userHasMovedMap = false;

  /// The suggestion whose details fetch failed, so [_retry] retries the right
  /// operation instead of reverse-geocoding an unrelated point.
  AutoCompleteItem? _lastFailedSelect;

  /// Monotonic id used to drop stale reverse-geocode responses.
  int _geocodeRequestId = 0;

  _CardState _cardState = _CardState.initial;

  // --- Search panel ---
  bool _searchActive = false;
  bool _searchLoading = false;
  bool _searchEmpty = false;
  List<RichSuggestion> _suggestions = [];
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _locating = false;

  // --- Pin animation (lift while dragging) ---
  late final AnimationController _pinController =
      AnimationController.unbounded(vsync: this, value: 0);

  PlacePickerState();

  @override
  void initState() {
    super.initState();
    _lastCameraTarget = widget.displayLocation;
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void dispose() {
    _tapSuppressionSafety?.cancel();
    _idleSuppressionSafety?.cancel();
    _idleDebounce?.cancel();
    _pinController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Duration _anim(Duration base) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : base;

  // ---------------------------------------------------------------------------
  // Map lifecycle
  // ---------------------------------------------------------------------------

  void onMapCreated(GoogleMapController controller) {
    mapController.complete(controller);
    moveToCurrentUserLocation();
  }

  void _onMapTap(LatLng latLng) {
    // Swallow the tap that leaks through from selecting a search suggestion
    // (see [suppressMapTap]); otherwise the map would jump to the tapped point.
    if (suppressMapTap) {
      suppressMapTap = false;
      return;
    }
    if (_searchActive) {
      _closeSearch();
      return;
    }
    FocusScope.of(context).unfocus();
    moveToLocation(latLng);
  }

  void _onCameraMoveStarted() {
    _idleDebounce?.cancel();
    // A programmatic move resolves its own address; don't show the drag UI.
    if (_programmaticTarget != null) return;
    _userHasMovedMap = true;
    if (_searchActive) _closeSearch();
    _liftPin();
    if (_cardState == _CardState.resolved || _cardState == _CardState.error) {
      setState(() => _cardState = _CardState.dragging);
    }
  }

  void _onCameraMove(CameraPosition position) {
    _lastCameraTarget = position.target;
  }

  void _onCameraIdle() {
    _dropPin();

    final expected = _programmaticTarget;
    _programmaticTarget = null;
    _idleSuppressionSafety?.cancel();

    final target = _lastCameraTarget;
    if (target == null) return;

    // A programmatic move that settled where intended already has its address;
    // skip the redundant geocode. If the user interrupted it and ended up
    // elsewhere, fall through and resolve the real resting point.
    if (expected != null && _distanceMeters(target, expected) < 15) {
      return;
    }

    // Skip a network round-trip for tiny nudges around the resolved point, but
    // snap the returned coordinate to the visible pin so they never diverge.
    if (_lastResolvedTarget != null &&
        _distanceMeters(target, _lastResolvedTarget!) < 15 &&
        locationResult != null) {
      setState(() {
        locationResult!.latLng = target;
        _lastResolvedTarget = target;
        _cardState = _CardState.resolved;
      });
      return;
    }

    setState(() => _cardState = _CardState.resolving);
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: 350), () {
      reverseGeocodeLatLng(target);
    });
  }

  // ---------------------------------------------------------------------------
  // Pin motion
  // ---------------------------------------------------------------------------

  void _liftPin() {
    _pinController.animateTo(1.0,
        duration: _anim(const Duration(milliseconds: 160)),
        curve: Curves.easeOutCubic);
  }

  void _dropPin() {
    _pinController.animateTo(0.0,
        duration: _anim(const Duration(milliseconds: 240)),
        curve: Curves.easeOutBack);
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  void _openSearch() {
    final wasActive = _searchActive;
    if (!wasActive) setState(() => _searchActive = true);
    // Only on the first open: tapping the field leaks a tap through to the
    // GoogleMap platform view beneath it (the same Android hybrid-composition
    // touch leak documented on [suppressMapTap]). That leaked GoogleMap.onTap
    // fires just after this, sees the search as active and runs _closeSearch()
    // -> unfocus(), dismissing the keyboard before the user can type. Swallow
    // that one leaked tap so the field keeps focus. Re-arming on every tap
    // (e.g. re-focusing an already-open field) would keep resetting the 500ms
    // safety window and could later swallow a deliberate map tap.
    if (!wasActive) {
      suppressMapTap = true;
      _armTapSuppressionSafety();
    }
    // Belt-and-suspenders: focus explicitly. TextField's implicit tap-to-focus
    // is unreliable when an overlay sits above a platform view.
    if (!_searchFocus.hasFocus) _searchFocus.requestFocus();
  }

  void _closeSearch() {
    FocusScope.of(context).unfocus();
    if (_searchActive || _suggestions.isNotEmpty) {
      setState(() {
        _searchActive = false;
        _suggestions = [];
        _searchEmpty = false;
        _searchLoading = false;
      });
    }
  }

  /// Begins the search process and fetches the autocomplete list.
  void searchPlace(String place) {
    // On keyboard dismissal the search was being triggered again; cap that.
    if (place == previousSearchTerm) return;
    previousSearchTerm = place;

    if (place.isEmpty) {
      // Clearing the field must not force the panel open (it's opened by
      // focusing the field via onTap instead).
      setState(() {
        _suggestions = [];
        _searchEmpty = false;
        _searchLoading = false;
      });
      return;
    }

    setState(() {
      _searchActive = true;
      _searchLoading = true;
      _searchEmpty = false;
    });

    autoCompleteSearch(place);
  }

  /// Fetches the place autocomplete list with the query [place].
  void autoCompleteSearch(String place) async {
    try {
      final query = place.replaceAll(' ', '+');
      final countries = widget.countries;

      // You can filter by up to 5 countries (Places autocomplete docs).
      final regionParam = countries?.isNotEmpty == true
          ? "&components=country:${countries!.sublist(0, min(countries.length, 5)).join('|country:')}"
          : '';

      var endpoint =
          "https://${widget.hostUrl}/maps/api/place/autocomplete/json?"
          "key=${widget.apiKey}&"
          "language=${widget.localizationItem.languageCode}&"
          "input={$query}$regionParam&sessiontoken=$sessionToken";

      if (locationResult != null) {
        endpoint += "&location=${locationResult?.latLng?.latitude},"
            "${locationResult?.latLng?.longitude}";
      }

      final response = await http.get(Uri.parse(endpoint));
      if (response.statusCode != 200) throw Error();

      final responseJson = jsonDecode(response.body);
      if (responseJson['predictions'] == null) throw Error();

      final List<dynamic> predictions = responseJson['predictions'];

      // Ignore a response that arrived after the user changed/cleared the query.
      if (place != previousSearchTerm) return;

      if (predictions.isEmpty) {
        setState(() {
          _suggestions = [];
          _searchEmpty = true;
          _searchLoading = false;
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
          () => _onSuggestionTapped(aci),
          secondaryText: secondary,
          leadingIcon: _iconForTypes(types),
          showDivider: i != predictions.length - 1,
        ));
      }

      setState(() {
        _suggestions = suggestions;
        _searchEmpty = false;
        _searchLoading = false;
      });
    } catch (e) {
      debugPrint('autoCompleteSearch error: $e');
      setState(() {
        _suggestions = [];
        _searchEmpty = true;
        _searchLoading = false;
      });
    }
  }

  void _onSuggestionTapped(AutoCompleteItem aci) {
    // Block the map's leaked onTap for this selection (see [suppressMapTap]).
    suppressMapTap = true;
    _armTapSuppressionSafety();
    _closeSearch();
    // Reset the field so reopening search starts clean (and a later clear can't
    // re-open the panel). Reset the guard first so the clear listener no-ops.
    previousSearchTerm = '';
    _searchController.clear();
    decodeAndSelectPlace(aci);
  }

  /// Fetches the lat,lng of a selected suggestion and moves there with the rich
  /// Place Details payload.
  void decodeAndSelectPlace(AutoCompleteItem place) async {
    final reqId = ++_geocodeRequestId;
    _idleDebounce?.cancel();
    setState(() => _cardState = _CardState.resolving);
    LatLng? selectedLatLng;
    try {
      final url = Uri.parse(
          "https://${widget.hostUrl}/maps/api/place/details/json?key=${widget.apiKey}&"
          "language=${widget.localizationItem.languageCode}&"
          "placeid=${place.id}");

      final response = await http.get(url);
      if (response.statusCode != 200) throw Error();

      final responseJson = jsonDecode(response.body);
      if (responseJson['result'] == null) throw Error();
      if (reqId != _geocodeRequestId) return;

      final result = responseJson['result'];
      final location = result['geometry']['location'];
      final latLng = LatLng(location['lat'], location['lng']);
      selectedLatLng = latLng;

      _programmaticTarget = latLng;
      _armIdleSuppressionSafety();
      mapController.future.then((controller) {
        controller.animateCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: latLng, zoom: 15.0)));
      });

      setState(() {
        String locality = '',
            postalCode = '',
            country = '',
            administrativeAreaLevel1 = '',
            administrativeAreaLevel2 = '',
            subLocalityLevel1 = '',
            subLocalityLevel2 = '';
        if (result['address_components'] is List<dynamic> &&
            result['address_components'].length > 0) {
          for (var comp in result['address_components']) {
            final types = comp['types'] as List<dynamic>;
            final shortName =
                (comp['short_name'] ?? comp['long_name'] ?? '').toString();
            if (types.contains('sublocality_level_1')) {
              subLocalityLevel1 = shortName;
            } else if (types.contains('sublocality_level_2')) {
              subLocalityLevel2 = shortName;
            } else if (types.contains('locality')) {
              locality = shortName;
            } else if (types.contains('administrative_area_level_2')) {
              administrativeAreaLevel2 = shortName;
            } else if (types.contains('administrative_area_level_1')) {
              administrativeAreaLevel1 = shortName;
            } else if (types.contains('country')) {
              country = shortName;
            } else if (types.contains('postal_code')) {
              postalCode = shortName;
            }
          }
        }
        locality = locality != '' ? locality : administrativeAreaLevel1;
        final city = locality;
        locationResult = LocationResult()
          ..name = place.text
          ..locality = locality
          ..latLng = latLng
          ..formattedAddress = result['formatted_address']
          ..placeId = result['place_id']
          ..postalCode = postalCode
          ..country = AddressComponent(name: country, shortName: country)
          ..administrativeAreaLevel1 = AddressComponent(
              name: administrativeAreaLevel1,
              shortName: administrativeAreaLevel1)
          ..administrativeAreaLevel2 = AddressComponent(
              name: administrativeAreaLevel2,
              shortName: administrativeAreaLevel2)
          ..city = AddressComponent(name: city, shortName: city)
          ..subLocalityLevel1 = AddressComponent(
              name: subLocalityLevel1, shortName: subLocalityLevel1)
          ..subLocalityLevel2 = AddressComponent(
              name: subLocalityLevel2, shortName: subLocalityLevel2);
        _lastResolvedTarget = latLng;
        _cardState = _CardState.resolved;
      });
      _lastFailedSelect = null;
      HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint('decodeAndSelectPlace error: $e');
      if (reqId != _geocodeRequestId) return;
      setState(() {
        if (selectedLatLng != null) {
          // We have coordinates but couldn't build the rich result — keep the
          // user un-stuck with a confirmable minimal result at that point.
          locationResult = _fallbackResult(selectedLatLng);
          _lastResolvedTarget = selectedLatLng;
          _lastFailedSelect = null;
        } else {
          // Failed before we had coordinates; let Retry re-run this selection.
          _lastFailedSelect = place;
        }
        _cardState = _CardState.error;
      });
    }
  }

  /// Minimal, fully-initialised result for points we couldn't fully geocode, so
  /// the user is never trapped and Confirm still returns valid coordinates.
  LocationResult _fallbackResult(LatLng latLng) {
    AddressComponent empty() => AddressComponent(name: '', shortName: '');
    return LocationResult()
      ..name = widget.localizationItem.unnamedLocation
      ..locality = ''
      ..latLng = latLng
      ..formattedAddress = ''
      ..postalCode = ''
      ..country = empty()
      ..administrativeAreaLevel1 = empty()
      ..administrativeAreaLevel2 = empty()
      ..city = empty()
      ..subLocalityLevel1 = empty()
      ..subLocalityLevel2 = empty();
  }

  // ---------------------------------------------------------------------------
  // Geocoding
  // ---------------------------------------------------------------------------

  String getLocationName() {
    if (locationResult == null) {
      return widget.localizationItem.unnamedLocation;
    }
    final name = locationResult?.name ?? '';
    final locality = locationResult?.locality ?? '';
    if (name.isEmpty) return widget.localizationItem.unnamedLocation;
    if (locality.isEmpty || name.contains(locality)) return name;
    return '$name, $locality';
  }

  /// Reverse geocodes [latLng] into a full [LocationResult].
  void reverseGeocodeLatLng(LatLng latLng) async {
    final reqId = ++_geocodeRequestId;
    // This is a point geocode, not a suggestion; a pending select-retry is now
    // obsolete so Retry targets this point instead.
    _lastFailedSelect = null;
    if (_cardState != _CardState.resolving) {
      setState(() => _cardState = _CardState.resolving);
    }
    try {
      final url = Uri.parse("https://${widget.hostUrl}/maps/api/geocode/json?"
          "latlng=${latLng.latitude},${latLng.longitude}&"
          "language=${widget.localizationItem.languageCode}&"
          "key=${widget.apiKey}");

      final response = await http.get(url);
      if (response.statusCode != 200) throw Error();

      final responseJson = jsonDecode(response.body);
      final results = responseJson['results'] as List?;
      if (reqId != _geocodeRequestId) return;

      // ZERO_RESULTS (e.g. an unaddressable point like open water) returns an
      // empty list with HTTP 200. Resolve it as an unnamed location so the user
      // can still confirm, rather than dead-ending in an error/retry loop.
      if (results == null || results.isEmpty) {
        setState(() {
          locationResult = _fallbackResult(latLng);
          _lastResolvedTarget = latLng;
          _cardState = _CardState.resolved;
        });
        return;
      }

      final result = results[0];

      setState(() {
        String name = '',
            locality = '',
            postalCode = '',
            country = '',
            administrativeAreaLevel1 = '',
            administrativeAreaLevel2 = '',
            subLocalityLevel1 = '',
            subLocalityLevel2 = '';
        bool isOnStreet = false;
        if (result['address_components'] is List<dynamic> &&
            result['address_components'].length > 0) {
          for (var i = 0; i < result['address_components'].length; i++) {
            var tmp = result['address_components'][i];
            var types = tmp['types'] as List<dynamic>;
            var shortName =
                (tmp['short_name'] ?? tmp['long_name'] ?? '').toString();
            if (i == 0) {
              // [street_number]
              name = shortName;
              isOnStreet = types.contains('street_number');
            } else if (i == 1 && isOnStreet) {
              if (types.contains('route')) {
                name += ", $shortName";
              }
            } else {
              if (types.contains('sublocality_level_1')) {
                subLocalityLevel1 = shortName;
              } else if (types.contains('sublocality_level_2')) {
                subLocalityLevel2 = shortName;
              } else if (types.contains('locality')) {
                locality = shortName;
              } else if (types.contains('administrative_area_level_2')) {
                administrativeAreaLevel2 = shortName;
              } else if (types.contains('administrative_area_level_1')) {
                administrativeAreaLevel1 = shortName;
              } else if (types.contains('country')) {
                country = shortName;
              } else if (types.contains('postal_code')) {
                postalCode = shortName;
              }
            }
          }
        }
        locality = locality != '' ? locality : administrativeAreaLevel1;
        final city = locality;
        locationResult = LocationResult()
          ..name = name
          ..locality = locality
          ..latLng = latLng
          ..formattedAddress = result['formatted_address']
          ..placeId = result['place_id']
          ..postalCode = postalCode
          ..country = AddressComponent(name: country, shortName: country)
          ..administrativeAreaLevel1 = AddressComponent(
              name: administrativeAreaLevel1,
              shortName: administrativeAreaLevel1)
          ..administrativeAreaLevel2 = AddressComponent(
              name: administrativeAreaLevel2,
              shortName: administrativeAreaLevel2)
          ..city = AddressComponent(name: city, shortName: city)
          ..subLocalityLevel1 = AddressComponent(
              name: subLocalityLevel1, shortName: subLocalityLevel1)
          ..subLocalityLevel2 = AddressComponent(
              name: subLocalityLevel2, shortName: subLocalityLevel2);
        _lastResolvedTarget = latLng;
        _cardState = _CardState.resolved;
      });
      HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint('reverseGeocodeLatLng error: $e');
      if (reqId != _geocodeRequestId) return;
      // Keep the user un-stuck: allow confirming with a minimal result.
      setState(() {
        locationResult = _fallbackResult(latLng);
        _cardState = _CardState.error;
      });
    }
  }

  /// Animates the camera to [latLng] and resolves the address there.
  void moveToLocation(LatLng latLng) {
    _programmaticTarget = latLng;
    _idleDebounce?.cancel();
    _armIdleSuppressionSafety();
    mapController.future.then((controller) {
      controller.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 15.0)));
    });
    reverseGeocodeLatLng(latLng);
  }

  void moveToCurrentUserLocation() {
    if (widget.displayLocation != null) {
      moveToLocation(widget.displayLocation!);
      return;
    }

    Location().getLocation().then((locationData) {
      // Don't yank the camera if the user already panned to a spot themselves.
      if (_userHasMovedMap) return;
      final target = LatLng(locationData.latitude!, locationData.longitude!);
      moveToLocation(target);
    }).catchError((error) {
      debugPrint('getLocation error: $error');
      if (_userHasMovedMap) return;
      // Couldn't get the device location; resolve whatever the map shows.
      reverseGeocodeLatLng(_lastCameraTarget ?? _kDefaultCenter);
    });
  }

  void _goToMyLocation() {
    setState(() => _locating = true);
    Location().getLocation().then((locationData) {
      if (!mounted) return;
      setState(() => _locating = false);
      moveToLocation(LatLng(locationData.latitude!, locationData.longitude!));
    }).catchError((error) {
      debugPrint('getLocation error: $error');
      if (!mounted) return;
      setState(() => _locating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't access your location")),
      );
    });
  }

  void _confirm() {
    if (locationResult != null) {
      Navigator.of(context).pop(locationResult);
    }
  }

  void _retry() {
    setState(() => _cardState = _CardState.resolving);
    final failed = _lastFailedSelect;
    if (failed != null) {
      // The error came from a suggestion selection; retry that, not a point.
      decodeAndSelectPlace(failed);
      return;
    }
    final target =
        _lastCameraTarget ?? widget.displayLocation ?? _kDefaultCenter;
    reverseGeocodeLatLng(target);
  }

  void _armTapSuppressionSafety() {
    _tapSuppressionSafety?.cancel();
    _tapSuppressionSafety =
        Timer(const Duration(milliseconds: 500), () => suppressMapTap = false);
  }

  void _armIdleSuppressionSafety() {
    _idleSuppressionSafety?.cancel();
    _idleSuppressionSafety = Timer(
        const Duration(milliseconds: 500), () => _programmaticTarget = null);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final loc = widget.localizationItem;
    final canPop = Navigator.canPop(context);
    // Respect horizontal safe-area insets (notch / curved edge in landscape).
    final padL = media.padding.left;
    final padR = media.padding.right;

    final sheetSurface = isDark
        ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.05), cs.surface)
        : cs.surface;

    final String? mapStyle = isDark
        ? (widget.mapStyleDark ?? _kDarkMapStyle)
        : (widget.mapStyleLight);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              statusBarBrightness: Brightness.dark)
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              statusBarBrightness: Brightness.light),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: <Widget>[
            // 1. Map
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: widget.displayLocation ?? _kDefaultCenter,
                  zoom: 15,
                ),
                myLocationButtonEnabled: false,
                myLocationEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                onMapCreated: onMapCreated,
                onTap: _onMapTap,
                onCameraMoveStarted: _onCameraMoveStarted,
                onCameraMove: _onCameraMove,
                onCameraIdle: _onCameraIdle,
                style:
                    (mapStyle != null && mapStyle.isNotEmpty) ? mapStyle : null,
              ),
            ),

            // 2. Center pin
            _buildPin(cs, isDark),

            // 3. My-location FAB + bottom selection card
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: 16 + padR, bottom: 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _CircleButton(
                        size: 56,
                        semanticLabel: 'Use my current location',
                        onTap: _goToMyLocation,
                        child: AnimatedSwitcher(
                          duration: _anim(const Duration(milliseconds: 150)),
                          child: _locating
                              ? SizedBox(
                                  key: const ValueKey('locating'),
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(cs.primary),
                                  ),
                                )
                              : Icon(Icons.my_location,
                                  key: const ValueKey('icon'),
                                  color: cs.primary,
                                  size: 24),
                        ),
                      ),
                    ),
                  ),
                  SelectPlaceAction(
                    getLocationName(),
                    _confirm,
                    loc.tapToSelectLocation,
                    subtitle: locationResult?.formattedAddress,
                    caption: _captionForState(loc),
                    confirmText: loc.confirmLocation,
                    isLoading: _cardState == _CardState.initial ||
                        _cardState == _CardState.resolving,
                    isEnabled: (_cardState == _CardState.resolved ||
                            _cardState == _CardState.error) &&
                        locationResult != null,
                    dimmed: _cardState == _CardState.dragging,
                    onRetry: _cardState == _CardState.error ? _retry : null,
                    retryText: loc.tryAgain,
                  ),
                ],
              ),
            ),

            // 4. Close button (only when there's something to pop)
            if (canPop)
              Positioned(
                top: media.padding.top + 8,
                left: 16 + padL,
                child: _CircleButton(
                  size: _kControlSize,
                  semanticLabel: 'Go back',
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Icon(Icons.arrow_back, color: cs.onSurface, size: 22),
                ),
              ),

            // 5. Scrim while searching. Keyed so that inserting it into the
            // Stack does not shift the (also keyed) search layer's position:
            // without keys, this Positioned would reconcile against the search
            // Positioned, recreating the TextField subtree and dropping its
            // focus the instant the first tap lands — the "needs two taps to
            // type" bug.
            if (_searchActive)
              Positioned.fill(
                key: const ValueKey('search-scrim'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeSearch,
                  child: Container(
                    color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.25),
                  ),
                ),
              ),

            // 6. Search pill + results panel (always on top). The pill is inset
            // to clear the close button; the panel below stays full width.
            // Keyed so it is preserved (not rebuilt) when the scrim above is
            // inserted/removed — see the scrim's note.
            Positioned(
              key: const ValueKey('search-layer'),
              top: media.padding.top + 8,
              left: 16 + padL,
              right: 16 + padR,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding:
                        EdgeInsets.only(left: canPop ? _kControlSize + 8 : 0),
                    child: _buildSearchPill(cs, isDark, sheetSurface, loc),
                  ),
                  if (_searchActive) ...[
                    const SizedBox(height: 8),
                    _buildSearchPanel(cs, isDark, sheetSurface, media, loc),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _captionForState(LocalizationItem loc) {
    switch (_cardState) {
      case _CardState.initial:
      case _CardState.resolving:
        return loc.findingPlace;
      case _CardState.dragging:
        return loc.moveMapHint;
      case _CardState.error:
        return loc.addressError;
      case _CardState.resolved:
        return loc.selectedLocationLabel;
    }
  }

  Widget _buildPin(ColorScheme cs, bool isDark) {
    const pinSize = 44.0;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: _pinController,
            builder: (context, child) {
              final lift = _pinController.value.clamp(0.0, 1.4);
              return Transform.translate(
                // Anchor the pin's tip to the map centre; lift while dragging.
                offset: Offset(0, -pinSize / 2 - lift * 8),
                child: child,
              );
            },
            child: Semantics(
              label: 'Selected location pin, centered on the map',
              child: Icon(
                Icons.location_on,
                size: pinSize,
                color: cs.primary,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchPill(
      ColorScheme cs, bool isDark, Color surface, LocalizationItem loc) {
    return Container(
      // Match the height of the circular back button.
      constraints: const BoxConstraints(minHeight: _kControlSize),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? Border.all(color: cs.onSurface.withValues(alpha: 0.08))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.10),
            offset: const Offset(0, 2),
            blurRadius: 12,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // While search is closed we show a non-editable placeholder, not a live
        // TextField. A TextField that sits permanently over the GoogleMap
        // platform view only ever focuses through the contended touch path,
        // which Android drops on the first tap (you'd have to tap twice before
        // the cursor/keyboard appears). Tapping the placeholder activates search,
        // which mounts the real field fresh with `autofocus: true` so it focuses
        // programmatically on mount instead of via that tap path — one tap.
        child: _searchActive
            ? SearchInput(
                searchPlace,
                bare: true,
                autofocus: true,
                hintText: loc.searchHint,
                controller: _searchController,
                focusNode: _searchFocus,
                onTap: _openSearch,
                onCleared: () => searchPlace(''),
              )
            : _SearchPillPlaceholder(
                hintText: loc.searchHint,
                iconColor: cs.onSurface.withValues(alpha: isDark ? 0.60 : 0.55),
                hintColor: cs.onSurface.withValues(alpha: isDark ? 0.55 : 0.60),
                onTap: _openSearch,
              ),
      ),
    );
  }

  Widget _buildSearchPanel(ColorScheme cs, bool isDark, Color surface,
      MediaQueryData media, LocalizationItem loc) {
    final maxHeight = min(
      media.size.height * 0.6,
      media.size.height - media.padding.top - media.viewInsets.bottom - 140,
    ).clamp(140.0, media.size.height);

    Widget child;
    if (_searchLoading) {
      // Fill the available height with skeletons but never overflow it.
      final rows = ((maxHeight - 3) / 64).floor().clamp(1, 5);
      child = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: cs.primary.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
            for (int i = 0; i < rows; i++) _SkeletonRow(isLast: i == rows - 1),
          ],
        ),
      );
    } else if (_searchEmpty) {
      child = SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
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
      );
    } else {
      child = ListView(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom > 0 ? 8 : 0),
        shrinkWrap: true,
        children: _suggestions,
      );
    }

    // Shadow lives on the outer Container (outside any clip) while the rounded
    // ClipRRect clips the scrolling content to the panel's corners.
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight.toDouble()),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: cs.onSurface.withValues(alpha: 0.08))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
            offset: const Offset(0, 8),
            blurRadius: 28,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
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

/// Approximate great-circle distance in meters (equirectangular projection),
/// good enough for the small-move geocode guard.
double _distanceMeters(LatLng a, LatLng b) {
  const earth = 6378137.0;
  final dLat = (b.latitude - a.latitude) * pi / 180;
  final dLng = (b.longitude - a.longitude) * pi / 180;
  final meanLat = (a.latitude + b.latitude) / 2 * pi / 180;
  final x = dLng * cos(meanLat);
  return earth * sqrt(x * x + dLat * dLat);
}

/// Static, non-editable stand-in for the search field shown while search is
/// closed. Its row matches an empty [SearchInput] (search glyph, hint, trailing
/// gap) so the pill does not jump when search activates and the real field is
/// mounted in its place. Tapping it activates search; the field that replaces it
/// autofocuses on mount, which is what makes a single tap focus reliably over
/// the GoogleMap platform view.
class _SearchPillPlaceholder extends StatelessWidget {
  final String hintText;
  final Color iconColor;
  final Color hintColor;
  final VoidCallback onTap;

  const _SearchPillPlaceholder({
    required this.hintText,
    required this.iconColor,
    required this.hintColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: 22, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hintText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: hintColor),
            ),
          ),
          const SizedBox(width: 20, height: 20),
        ],
      ),
    );
  }
}

/// Themed circular icon button used for the FAB and close affordance.
class _CircleButton extends StatefulWidget {
  final double size;
  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;

  const _CircleButton({
    required this.size,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
  });

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final surface = isDark
        ? Color.alphaBlend(cs.onSurface.withValues(alpha: 0.05), cs.surface)
        : cs.surface;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: Duration(milliseconds: reduceMotion ? 0 : 120),
        curve: Curves.easeOut,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isDark
                ? Border.all(color: cs.onSurface.withValues(alpha: 0.08))
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.16),
                offset: const Offset(0, 3),
                blurRadius: 8,
              ),
            ],
          ),
          child: Material(
            color: surface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkResponse(
              onTap: widget.onTap,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              containedInkWell: true,
              radius: widget.size / 2,
              child: Center(child: widget.child),
            ),
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

/// A compact dark Google Maps style applied automatically in dark mode.
const String _kDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#212121"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#757575"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#181818"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2c2c2c"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373737"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c3c3c"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#4e4e4e"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d3d"}]}
]
''';
