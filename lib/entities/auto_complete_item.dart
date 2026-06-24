/// Autocomplete results item returned from Google will be deserialized
/// into this model.
class AutoCompleteItem {
  /// The id of the place. This helps to fetch the lat,lng of the place.
  late String id;

  /// The text (name of place) displayed in the autocomplete suggestions list.
  late String text;

  /// Assistive index to begin highlight of matched part of the [text] with
  /// the original query
  late int offset;

  /// Length of matched part of the [text]
  late int length;

  /// Place types reported by the Places API (e.g. `route`, `locality`,
  /// `establishment`). Optional; used to pick a representative leading icon
  /// in the suggestions list. Older callers that never set this keep working.
  List<String>? types;
}
