# Flutter Place Picker [![Pub](https://img.shields.io/pub/v/place_picker.svg)](https://pub.dev/packages/place_picker)

The missing location picker made in Flutter for Flutter. A modern, ride-hailing
style picker with full light/dark theming and custom localization support.

### What's new in the redesign

A ground-up UI/UX revamp — every existing capability and the public API are
preserved:

- **Fixed center pin** — pan the map under a custom-painted pin that lifts on
  drag and settles with a success pulse; the address resolves automatically when
  the map comes to rest (debounced, with stale-response guards). Tapping the map
  still works as a secondary way to drop the pin.
- **Floating search** — a glass search pill that opens an in-tree results panel
  with place-type icons, two-line rows and highlighted matches.
- **Persistent confirm card** — shows the selected name + full address with a
  clear primary **Confirm** button, shimmer while resolving, and an inline retry
  on failure.
- **Polished chrome** — themed my-location button, a dark Google Map style at
  night, status-bar adaptation, reduce-motion support, large tap targets and
  screen-reader announcements.

⚠️ Please note: This library will <b>NOT</b> be affected by the deprecation of Place Picker as [indicated here](https://developers.google.com/places/android-sdk/placepicker).

🍭 Remember to enable `Places API`, `Maps SDK for Android`, `Maps SDK for iOS` and `Geocoding API` for your API key.

## Usage

To use this plugin, add `place_picker` as a [dependency in your pubspec.yaml file](https://flutter.io/platform-plugins/).

## Getting Started

This package relies on [google_maps_flutter](https://github.com/flutter/plugins/tree/master/packages/google_maps_flutter) to display the map. Follow these guidelines to add your API key to the Android and iOS packages.

Get an API key at <https://cloud.google.com/maps-platform/> if you haven't already.

### Android

Specify your API key in the application manifest `android/app/src/main/AndroidManifest.xml` and add `ACCESS_FINE_LOCATION` permission:

```xml
<manifest ...

  <!-- Add this permission -->
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

  <application ...
    <!-- Add your api key here -->
    <meta-data android:name="com.google.android.geo.API_KEY"
               android:value="YOUR KEY HERE"/>
    <activity ..../>
  </application>
</manifest>
```

Update your gradle.properties file with this:

```groovy
android.enableJetifier=true
android.useAndroidX=true
org.gradle.jvmargs=-Xmx1536M
```

Please also make sure that you have those dependencies in your build.gradle:

```groovy
  // parent level build.gradle (android/build.gradle)
  dependencies {
      classpath 'com.android.tools.build:gradle:3.3.0'
      classpath 'com.google.gms:google-services:4.2.0'
  }
  ...

  // app level build.gradle (android/app/build.gradle)
  compileSdkVersion 28
```

### iOS

Specify your API key in the application delegate `ios/Runner/AppDelegate.m`:

```objectivec
#include "AppDelegate.h"
#include "GeneratedPluginRegistrant.h"
#import "GoogleMaps/GoogleMaps.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [GMSServices provideAPIKey:@"YOUR KEY HERE"];
  [GeneratedPluginRegistrant registerWithRegistry:self];
  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}
@end
```

Or in your swift code, specify your API key in the application delegate `ios/Runner/AppDelegate.swift`:

```swift
import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("YOUR KEY HERE")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

Opt-in to the embedded views preview by adding a boolean property to the app's `Info.plist` file
with the key `io.flutter.embedded_views_preview` and the value `YES`.

![info.plist](https://i.ibb.co/hWN3Y75/plist.png "Place inside the dict values")

Also add these to the dict values in `Info.plist` for location request to work on iOS
![info.plist](https://i.ibb.co/2Y3X2jY/locationperm.png)

## Sample Usage

Import the package into your code

```dart
import 'package:locationpicker/place_picker.dart';
```

Create a method like below, and call it in `onTap` of a button or InkWell. A `LocationResult` is returned
when the user confirms a place (or `null` if they back out), carrying the name, full address and lat/lng of the
selected place. Pass an optional `LatLng displayLocation` to start the map at a specific location — useful when
showing a previously selected place.

```dart
void showPlacePicker() async {
    final LocationResult? result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlacePicker(
          "YOUR_API_KEY",
          displayLocation: customLocation, // optional
        ),
      ),
    );

    if (result != null) {
      // Handle the result in your way
      print('${result.name} — ${result.formattedAddress}');
    }
}
```

All on-screen text is customizable for localization via the optional `localizationItem` argument
(`searchHint`, `confirmLocation`, `selectedLocationLabel`, `moveMapHint`, and the rest). Results can be
restricted to up to five countries with `countries: ['us', 'ca']`.
