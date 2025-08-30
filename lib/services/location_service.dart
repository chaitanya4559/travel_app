// FINALIZED CODE

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:exif/exif.dart';

class LocationService {
  /// Fetches the current device's GPS position.
  Future<Position?> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    return await Geolocator.getCurrentPosition();
  }

  /// Converts latitude and longitude into a human-readable address.
  Future<String> getAddressFromCoordinates(double lat, double lon) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final place = placemarks[0];
        return "${place.locality}, ${place.administrativeArea}";
      }
      return 'Address not found';
    } catch (e) {
      return 'Lat: ${lat.toStringAsFixed(2)}, Lon: ${lon.toStringAsFixed(2)}';
    }
  }

  /// Extracts GPS data from an image's EXIF metadata and returns a readable address.
  Future<String?> getAddressFromExif(String filePath) async {
    try {
      final fileBytes = await File(filePath).readAsBytes();
      final exifData = await readExifFromBytes(fileBytes);

      final gpsLatitudeTag = exifData['GPS GPSLatitude'];
      final gpsLongitudeTag = exifData['GPS GPSLongitude'];
      final gpsLatitudeRefTag = exifData['GPS GPSLatitudeRef'];
      final gpsLongitudeRefTag = exifData['GPS GPSLongitudeRef'];

      if (gpsLatitudeTag != null &&
          gpsLongitudeTag != null &&
          gpsLatitudeRefTag != null &&
          gpsLongitudeRefTag != null) {
        double lat;
        double lon;

        final latValues = gpsLatitudeTag.values.toList().cast<Ratio>();
        final lonValues = gpsLongitudeTag.values.toList().cast<Ratio>();

        if (latValues.length == 1 && lonValues.length == 1) {
          lat = latValues.first.toDouble();
          lon = lonValues.first.toDouble();
        } else if (latValues.length == 3 && lonValues.length == 3) {
          lat = _dmsToDD(latValues);
          lon = _dmsToDD(lonValues);
        } else {
          return null;
        }

        if (lat.isNaN || lon.isNaN || !lat.isFinite || !lon.isFinite) {
          return null;
        }

        final latRef = gpsLatitudeRefTag.printable;
        final lonRef = gpsLongitudeRefTag.printable;

        final finalLat = (latRef == 'S') ? -lat : lat;
        final finalLon = (lonRef == 'W') ? -lon : lon;

        return await getAddressFromCoordinates(finalLat, finalLon);
      }
      return null;
    } catch (e) {
      debugPrint('Error reading EXIF data: $e');
      return null;
    }
  }

  /// ✅ UPDATED: Helper to convert DMS to DD, now with a safety check for zero denominators.
  double _dmsToDD(List<Ratio> dms) {
    try {
      if (dms.length != 3) return double.nan;

      // Safety check for invalid data that causes NaN errors.
      if (dms[0].denominator == 0 ||
          dms[1].denominator == 0 ||
          dms[2].denominator == 0) {
        debugPrint(
            "Invalid EXIF data: DMS component has a denominator of zero.");
        return double.nan;
      }

      final degrees = dms[0].toDouble();
      final minutes = dms[1].toDouble();
      final seconds = dms[2].toDouble();

      if (!degrees.isFinite || !minutes.isFinite || !seconds.isFinite) {
        return double.nan;
      }

      return degrees + (minutes / 60) + (seconds / 3600);
    } catch (e) {
      debugPrint("Error in _dmsToDD conversion: $e");
      return double.nan;
    }
  }
}
