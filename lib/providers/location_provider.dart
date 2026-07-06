// lib/providers/location_provider.dart
//
// Reactive location + permission providers built on geolocator.
// Use these instead of calling Geolocator directly from widgets.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Result of a location-permission check.
enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

/// Single-shot permission check (Geolocator-aware).
final locationPermissionProvider =
    FutureProvider<LocationPermissionStatus>((ref) async {
  final serviceOn = await Geolocator.isLocationServiceEnabled();
  if (!serviceOn) return LocationPermissionStatus.serviceDisabled;

  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) {
    p = await Geolocator.requestPermission();
  }
  if (p == LocationPermission.deniedForever) {
    return LocationPermissionStatus.deniedForever;
  }
  if (p == LocationPermission.always || p == LocationPermission.whileInUse) {
    return LocationPermissionStatus.granted;
  }
  return LocationPermissionStatus.denied;
});

/// permission_handler view of the same permission (used in places that
/// already work with `Permission.locationWhenInUse`).
final phLocationPermissionProvider = FutureProvider<ph.PermissionStatus>((ref) {
  return ph.Permission.locationWhenInUse.status;
});

/// One-shot current position. Throws if permission is missing or GPS is off.
final currentPositionProvider = FutureProvider<Position>((ref) async {
  final status = await ref.watch(locationPermissionProvider.future);
  if (status != LocationPermissionStatus.granted) {
    throw Exception(
      status == LocationPermissionStatus.serviceDisabled
          ? 'GPS is off. Enable Location Services.'
          : 'Location permission required.',
    );
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
});

/// Continuous high-accuracy position stream (used by SOS, live session, etc).
/// Permission is verified on first read; if missing, the stream errors.
final positionStreamProvider = StreamProvider<Position>((ref) async* {
  final status = await ref.watch(locationPermissionProvider.future);
  if (status != LocationPermissionStatus.granted) {
    throw StateError('Location permission not granted');
  }
  await for (final pos in Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  )) {
    yield pos;
  }
});
