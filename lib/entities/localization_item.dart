/// Holds every user-facing string used by the picker so the UI can be fully
/// localized. All fields are optional and default to English, so existing
/// callers keep working unchanged.
class LocalizationItem {
  String languageCode;

  /// Reserved for the (exported) [NearbyPlaceItem] list.
  String nearBy;

  /// Shown while a place/address is being resolved.
  String findingPlace;

  /// Title of the empty state when a search returns nothing.
  String noResultsFound;

  /// Fallback name used when a location has no readable label.
  String unnamedLocation;

  /// Legacy caption text. Still used as the bottom-card caption fallback.
  String tapToSelectLocation;

  /// Placeholder text inside the search field.
  String searchHint;

  /// Label for the primary confirm button on the bottom card.
  String confirmLocation;

  /// Caption above the resolved address on the bottom card.
  String selectedLocationLabel;

  /// Caption shown while the user is dragging the map under the pin.
  String moveMapHint;

  /// Caption shown when reverse-geocoding fails.
  String addressError;

  /// Label for the inline retry affordance.
  String tryAgain;

  /// Secondary line of the empty search state.
  String noResultsHint;

  LocalizationItem({
    this.languageCode = 'en_us',
    this.nearBy = 'Nearby Places',
    this.findingPlace = 'Finding place...',
    this.noResultsFound = 'No results found',
    this.unnamedLocation = 'Unnamed location',
    this.tapToSelectLocation = 'Tap to select this location',
    this.searchHint = 'Search for a place',
    this.confirmLocation = 'Confirm location',
    this.selectedLocationLabel = 'Selected location',
    this.moveMapHint = 'Move the map to set location',
    this.addressError = 'Couldn\'t get address',
    this.tryAgain = 'Retry',
    this.noResultsHint = 'Try a different search',
  });
}
