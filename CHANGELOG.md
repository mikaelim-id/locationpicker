## [0.11.0] - 24 Jun 2026
Complete UI/UX redesign — fully backward compatible.

- Fixed center-pin interaction: pan the map under a single map pin that lifts
  while dragging and resolves the address on camera idle (debounced, with a
  small-move skip and stale-response guards). Tap-to-place is retained.
- Floating glass search pill opening an in-tree results panel (replaces the old
  overlay) with place-type icons, two-line rows and highlighted matches.
- Persistent bottom card with a full address, a clear Confirm button, loading
  shimmer and inline retry on geocode failure.
- Themed my-location button, dark Google Map style at night, adaptive status
  bar, reduce-motion support, larger tap targets and screen-reader announcements.
- New optional `LocalizationItem` strings and optional `mapStyleDark` /
  `mapStyleLight` parameters. Public API and `LocationResult` unchanged.

## [0.10.0]
Added `hostUrl` option and map tap suppression fix.

## [0.9.18] - 2 Nov 2020
Upgraded http package

## [0.9.17] - 2 Nov 2020
Added custom localization support

## [0.9.16] - 2 Nov 2020
Bump google_maps_flutter version up

## [0.9.15] - 17 Sep 2020
Merge geocode reverse fix. (I reset my PC, .14 is jumped)

## [0.9.13] - 15 Apr 2020
Code clean up. Refactor.

## [0.9.12] - 12 Apr 2020
Update instructions for installation

## [0.9.11] - 9 Dec 2019.

Dark Theme support

## [0.9.10] - 3 Dec 2019.

Pass custom initial location or previously selected location.

## [0.9.9] - 5 Aug 2019.

Added place id and formatted address to results

## [0.9.8] - 29 Jun 2019.

Hide keyboard on suggestion selection. Refactoring.

## [0.9.7] - 10 Jun 2019.

Consistent UI. Made installation guidelines more clearer.

## [0.9.6] - 9 Jun 2019.

Fixed fatal typo

## [0.9.5] - 9 Jun 2019.

Fixed issue where autocomplete overlay still remain after widget has been
disposed until whole app is restarted.

## [0.9.4] - 8 Jun 2019.

Working on library health.

## [0.9.3] - 8 Jun 2019.

Fixed issue with delayed call to searchPlace

`searchPlace` was being called (sometimes) after the widget has unmounted.
This could have been due to some delay caused by the debouncer proceeding after
the widget has unmounted

## [0.9.2] - 8 Jun 2019.

Fixed issue where `setState` from http response callbacks was being called
after widget was disposed/unmounted

## [0.9.1] - 1 Jun 2019.

Updated guidelines to include missing configurations

## [0.9.0] - 1 Jun 2019.

Prepared for usage.

## [0.0.2] - 1 Jun 2019.

Fixes to package publication health. Added example.

## [0.0.1] - 1 Jun 2019.

Initial release.
