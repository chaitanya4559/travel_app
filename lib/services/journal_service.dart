// FINALIZED CODE

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:travelapp/models/journal_entry.dart';
import 'package:http/http.dart' as http;

class JournalService {
  final Box<JournalEntry> _journalBox =
      Hive.box<JournalEntry>('journal_entries');
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  final String? _googleApiKey = dotenv.env['GOOGLE_API_KEY'];

  String? get _userId => _supabaseClient.auth.currentUser?.id;

  /// Saves the entry locally and then automatically triggers a background sync.
  Future<void> saveEntry(JournalEntry entry) async {
    entry.isSynced = false;
    await _journalBox.put(entry.id, entry);
    debugPrint("Entry '${entry.title}' saved locally. Triggering sync.");
    syncEntries();
  }

  /// Adopts a consistent offline-first deletion pattern.
  Future<void> deleteEntry(String id) async {
    final entry = getEntryById(id);
    if (entry == null) return;

    entry.markedForDeletion = true;
    entry.isSynced = false;
    await entry.save();
    debugPrint("Entry '${entry.title}' marked for deletion. Triggering sync.");
    syncEntries();
  }

  List<JournalEntry> getEntries() =>
      _journalBox.values.where((e) => !e.markedForDeletion).toList();
  JournalEntry? getEntryById(String id) => _journalBox.get(id);

  /// Fetch entries from Supabase and sync with local Hive box
  Future<void> fetchAndStoreEntries() async {
    if (_userId == null) return;
    try {
      final response = await _supabaseClient
          .from('journal_entries')
          .select()
          .eq('user_id', _userId!);

      final remoteIds = response.map((e) => e['id'] as String).toSet();
      final localEntries =
          Map.fromEntries(_journalBox.values.map((e) => MapEntry(e.id, e)));

      for (var entryData in response) {
        final entry = JournalEntry(
            id: entryData['id'],
            title: entryData['title'],
            description: entryData['description'],
            photoPaths: List<String>.from(entryData['photo_paths'] ?? []),
            date: entryData['date'],
            location: entryData['location'] ?? 'Unknown Location',
            tags: List<String>.from(entryData['tags'] ?? []),
            isSynced: true,
            latitude: (entryData['latitude'] ?? 0.0).toDouble(),
            longitude: (entryData['longitude'] ?? 0.0).toDouble(),
            voiceNotePath: entryData['voice_note_path'] ?? '',
            transcription: entryData['transcription'] ?? '');
        await _journalBox.put(entry.id, entry);
      }

      for (var localId in localEntries.keys) {
        if (!remoteIds.contains(localId) && localEntries[localId]!.isSynced) {
          await _journalBox.delete(localId);
        }
      }
      debugPrint("Data fetched and stored locally.");
    } on SocketException {
      debugPrint("No internet. Cannot fetch entries.");
    } catch (e) {
      debugPrint('Error fetching from Supabase: $e');
    }
  }

  /// Sync all local changes (creations, updates, deletions) to Supabase
  Future<void> syncEntries() async {
    if (_userId == null) return;

    final entriesToDelete =
        _journalBox.values.where((e) => e.markedForDeletion).toList();
    if (entriesToDelete.isNotEmpty) {
      try {
        final idsToDelete = entriesToDelete.map((e) => e.id).toList();
        await _supabaseClient
            .from('journal_entries')
            .delete()
            .inFilter('id', idsToDelete);
        for (var entry in entriesToDelete) {
          if (entry.voiceNotePath.isNotEmpty &&
              entry.voiceNotePath.startsWith('http')) {
            await _deleteFileFromStorage(entry.voiceNotePath, 'voice-notes');
          }
          for (var url in entry.photoPaths.where((p) => p.startsWith('http'))) {
            await _deleteFileFromStorage(url, 'photos');
          }
          await _journalBox.delete(entry.id);
        }
        debugPrint('Synced ${entriesToDelete.length} deletions.');
      } on SocketException {
        debugPrint('No internet. Deletion sync stopped.');
        return;
      } catch (e) {
        debugPrint('Error syncing deletions: $e');
      }
    }

    final unsyncedEntries = _journalBox.values
        .where((e) => !e.isSynced && !e.markedForDeletion)
        .toList();
    if (unsyncedEntries.isEmpty) {
      debugPrint('All entries are synced.');
      return;
    }

    for (var entry in unsyncedEntries) {
      try {
        List<String> photoUrls = [];
        for (var path in entry.photoPaths) {
          if (File(path).existsSync()) {
            final url = await _uploadFile(path, 'photos');
            if (url != null) photoUrls.add(url);
          } else {
            photoUrls.add(path);
          }
        }
        entry.photoPaths = photoUrls;

        if (entry.voiceNotePath.isNotEmpty &&
            File(entry.voiceNotePath).existsSync()) {
          entry.voiceNotePath =
              await _uploadFile(entry.voiceNotePath, 'voice-notes') ?? '';
        }

        if (entry.tags.isEmpty && entry.photoPaths.isNotEmpty) {
          final firstPhoto = entry.photoPaths.first;
          if (!firstPhoto.startsWith('http') && File(firstPhoto).existsSync()) {
            entry.tags = await getAITagsForImage(firstPhoto);
          }
        }

        await _supabaseClient.from('journal_entries').upsert({
          'id': entry.id,
          'user_id': _userId,
          'title': entry.title,
          'description': entry.description,
          'photo_paths': entry.photoPaths,
          'date': entry.date,
          'tags': entry.tags,
          'latitude': entry.latitude,
          'longitude': entry.longitude,
          'voice_note_path': entry.voiceNotePath,
          'transcription': entry.transcription,
          'location': entry.location
        });

        entry.isSynced = true;
        await entry.save();
        debugPrint('Entry synced: ${entry.title}');
      } on SocketException {
        debugPrint('No internet. Syncing stopped.');
        return;
      } catch (e) {
        debugPrint('Error syncing entry ${entry.id}: $e');
      }
    }
  }

  Future<String?> _uploadFile(String filePath, String bucketName) async {
    if (_userId == null) return null;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final fileName = filePath.split('/').last;
      final path = '$_userId/$fileName';

      await _supabaseClient.storage.from(bucketName).upload(
            path,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      return _supabaseClient.storage.from(bucketName).getPublicUrl(path);
    } catch (e) {
      debugPrint('Error uploading file: $e');
      return null;
    }
  }

  Future<void> _deleteFileFromStorage(String url, String bucketName) async {
    if (_userId == null) return;
    try {
      final Uri uri = Uri.parse(url);
      final path = uri.pathSegments
          .sublist(uri.pathSegments.indexOf(bucketName) + 1)
          .join('/');
      await _supabaseClient.storage.from(bucketName).remove([path]);
    } catch (e) {
      debugPrint('Error deleting file from storage: $e');
    }
  }

  /// Handles both local file paths and remote http URLs.
  Future<List<String>> getAITagsForImage(String imageIdentifier) async {
    if (_googleApiKey == null ||
        _googleApiKey == 'YOUR_GOOGLE_CLOUD_API_KEY_HERE') {
      debugPrint("Warning: Google API key is not set. Using mock tags.");
      return ['mock', 'travel', 'photo'];
    }

    Uint8List imageBytes;

    try {
      if (imageIdentifier.startsWith('http')) {
        final response = await http.get(Uri.parse(imageIdentifier));
        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
        } else {
          throw Exception('Failed to download image from URL: ${response.statusCode}');
        }
      } else {
        final file = File(imageIdentifier);
        if (!await file.exists()) {
          throw Exception('Image file not found at path: $imageIdentifier');
        }
        imageBytes = await file.readAsBytes();
      }
    } catch (e) {
      debugPrint("Error reading image data: $e");
      throw Exception("Could not process the selected image.");
    }
    
    final imageBase64 = base64Encode(imageBytes);
    final url = Uri.parse(
        "https://vision.googleapis.com/v1/images:annotate?key=$_googleApiKey");

    final body = jsonEncode({
      "requests": [
        {
          "image": {"content": imageBase64},
          "features": [
            {"type": "LABEL_DETECTION", "maxResults": 5}
          ]
        }
      ]
    });

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final annotations = data['responses'][0]['labelAnnotations'];

        if (annotations == null) {
          return [];
        }

        final labels = annotations as List;
        return labels.map((label) => label['description'] as String).toList();
      } else {
        final errorBody = jsonDecode(response.body);
        final errorMessage =
            errorBody['error']['message'] ?? 'Unknown API Error';
        throw Exception('Failed to get tags: $errorMessage');
      }
    } catch (e) {
      debugPrint('Error getting AI tags: $e');
      throw Exception('Could not connect to the tag generation service.');
    }
  }
}