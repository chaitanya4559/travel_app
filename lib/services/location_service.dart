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

  /// ✅ REWRITTEN: A safer method that checks types before processing.
  Future<String?> getAddressFromExif(String filePath) async {
    try {
      final fileBytes = await File(filePath).readAsBytes();
      final exifData = await readExifFromBytes(fileBytes);

      if (exifData.isEmpty) return null;

      final gpsLatitudeTag = exifData['GPS GPSLatitude'];
      final gpsLongitudeTag = exifData['GPS GPSLongitude'];
      final gpsLatitudeRefTag = exifData['GPS GPSLatitudeRef'];
      final gpsLongitudeRefTag = exifData['GPS GPSLongitudeRef'];

      if (gpsLatitudeTag == null ||
          gpsLongitudeTag == null ||
          gpsLatitudeRefTag == null ||
          gpsLongitudeRefTag == null) {
        return null;
      }

      // Safely get the values without assuming their type yet.
      final latValuesDynamic = gpsLatitudeTag.values;
      final lonValuesDynamic = gpsLongitudeTag.values;

      // First, check if the data is in the expected List<Ratio> format.
      if (latValuesDynamic is! List<Ratio> || lonValuesDynamic is! List<Ratio>) {
        debugPrint(
            "GPS data is not in the expected Ratio format. Found: ${latValuesDynamic.runtimeType}");
        return null;
      }

      // Now that we've checked the type, we can safely cast and use the variables.
      final List<Ratio> latValues = latValuesDynamic as List<Ratio>;
      final List<Ratio> lonValues = lonValuesDynamic as List<Ratio>;

      double lat;
      double lon;

      if (latValues.length == 1 && lonValues.length == 1) {
        lat = latValues.first.toDouble();
        lon = lonValues.first.toDouble();
      } else if (latValues.length == 3 && lonValues.length == 3) {
        lat = _dmsToDD(latValues);
        lon = _dmsToDD(lonValues);
      } else {
        return null;
      }

      if (lat.isNaN || lon.isNaN) {
        return null;
      }

      final latRef = gpsLatitudeRefTag.printable;
      final lonRef = gpsLongitudeRefTag.printable;

      final finalLat = (latRef == 'S') ? -lat : lat;
      final finalLon = (lonRef == 'W') ? -lon : lon;

      return await getAddressFromCoordinates(finalLat, finalLon);
    } catch (e) {
      debugPrint('Error reading EXIF data: $e');
      return null;
    }
  }

  /// Helper to convert Degrees/Minutes/Seconds (DMS) to Decimal Degrees (DD).
  double _dmsToDD(List<Ratio> dms) {
    try {
      if (dms.any((ratio) => ratio.denominator == 0)) {
        return double.nan;
      }

      final degrees = dms[0].toDouble();
      final minutes = dms[1].toDouble();
      final seconds = dms[2].toDouble();

      return degrees + (minutes / 60) + (seconds / 3600);
    } catch (e) {
      return double.nan;
    }
  }
}