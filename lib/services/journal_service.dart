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

  // Add or update an entry locally
  Future<void> saveEntry(JournalEntry entry) async {
    entry.isSynced = false;
    await _journalBox.put(entry.id, entry);
  }

  // Handles both online and offline deletion
  Future<void> deleteEntry(String id) async {
    final entry = getEntryById(id);
    if (entry == null) return;

    try {
      // Try to delete from Supabase immediately if online
      await _supabaseClient.from('journal_entries').delete().match({'id': id});

      // Also delete any associated storage files
      if (entry.voiceNotePath.isNotEmpty &&
          entry.voiceNotePath.startsWith('http')) {
        await _deleteFileFromStorage(entry.voiceNotePath, 'voice-notes');
      }
      for (var url in entry.photoPaths.where((p) => p.startsWith('http'))) {
        await _deleteFileFromStorage(url, 'photos');
      }
      
      // Always delete from local storage after successful remote deletion
      await _journalBox.delete(id);

    } on SocketException {
      debugPrint('No internet. Marking entry for deletion to sync later.');
      // If offline, mark for deletion and save locally.
      entry.markedForDeletion = true;
      entry.isSynced = false; // Ensure it gets picked up by the sync process
      await entry.save();
    } catch (e) {
      debugPrint('Error deleting entry from Supabase: $e. Deleting locally.');
      // If any other error occurs, still delete locally to ensure UI consistency.
      await _journalBox.delete(id);
    }
  }

  List<JournalEntry> getEntries() => _journalBox.values.where((e) => !e.markedForDeletion).toList();
  JournalEntry? getEntryById(String id) => _journalBox.get(id);

  // Fetch entries from Supabase and sync with local Hive box
  Future<void> fetchAndStoreEntries() async {
    if (_userId == null) return;
    try {
      final response = await _supabaseClient
          .from('journal_entries')
          .select()
          .eq('user_id', _userId!);

      final remoteIds = response.map((e) => e['id'] as String).toSet();
      final localEntries = Map.fromEntries(_journalBox.values.map((e) => MapEntry(e.id, e)));

      // Add/update entries from remote
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
      
      // Remove local entries that are no longer on the server (unless they are new and unsynced)
      for(var localId in localEntries.keys){
        if(!remoteIds.contains(localId) && localEntries[localId]!.isSynced){
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

  // Sync all local changes (creations, updates, deletions) to Supabase
  Future<void> syncEntries() async {
    if (_userId == null) return;
    
    // 1. Handle Deletions
    final entriesToDelete = _journalBox.values.where((e) => e.markedForDeletion).toList();
    if (entriesToDelete.isNotEmpty) {
      try {
        final idsToDelete = entriesToDelete.map((e) => e.id).toList();
        await _supabaseClient.from('journal_entries').delete().inFilter('id', idsToDelete);
        for (var entry in entriesToDelete) {
          // Delete associated files from storage
          if (entry.voiceNotePath.isNotEmpty && entry.voiceNotePath.startsWith('http')) {
            await _deleteFileFromStorage(entry.voiceNotePath, 'voice-notes');
          }
          for (var url in entry.photoPaths.where((p) => p.startsWith('http'))) {
            await _deleteFileFromStorage(url, 'photos');
          }
          await _journalBox.delete(entry.id); // Clean up from local DB
        }
        debugPrint('Synced ${entriesToDelete.length} deletions.');
      } on SocketException {
         debugPrint('No internet. Deletion sync stopped.');
         return; 
      } catch(e) {
        debugPrint('Error syncing deletions: $e');
      }
    }
    
    // 2. Handle Creations/Updates
    final unsyncedEntries = _journalBox.values.where((e) => !e.isSynced && !e.markedForDeletion).toList();
    if (unsyncedEntries.isEmpty) {
      debugPrint('All entries are synced.');
      return;
    }

    for (var entry in unsyncedEntries) {
      try {
        // Upload files and get public URLs
        List<String> photoUrls = [];
        for (var path in entry.photoPaths) {
          if (File(path).existsSync()) {
            final url = await _uploadFile(path, 'photos');
            if (url != null) photoUrls.add(url);
          } else {
            photoUrls.add(path); // Assume it's already a URL
          }
        }
        entry.photoPaths = photoUrls;

        if (entry.voiceNotePath.isNotEmpty &&
            File(entry.voiceNotePath).existsSync()) {
          entry.voiceNotePath =
              await _uploadFile(entry.voiceNotePath, 'voice-notes') ?? '';
        }

        // Generate AI tags if needed
        if (entry.tags.isEmpty && entry.photoPaths.isNotEmpty) {
          final firstPhoto = entry.photoPaths.first;
          // For simplicity, we assume if it's a URL, tags were generated or not needed.
          // AI tagging is best for new, local images.
          if (!firstPhoto.startsWith('http') && File(firstPhoto).existsSync()) {
             entry.tags = await getAITagsForImage(firstPhoto);
          }
        }

        // Upsert entry data to Supabase
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
        return; // Stop sync process if offline
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
      // Correctly parse the file path from the full public URL
      final Uri uri = Uri.parse(url);
      final path = uri.pathSegments.sublist(uri.pathSegments.indexOf(bucketName) + 1).join('/');
      await _supabaseClient.storage.from(bucketName).remove([path]);
    } catch (e) {
      debugPrint('Error deleting file from storage: $e');
    }
  }

  Future<List<String>> getAITagsForImage(String imagePath) async {
    if (_googleApiKey == null ||
        _googleApiKey == 'YOUR_GOOGLE_CLOUD_API_KEY_HERE') {
      debugPrint("Warning: Google API key is not set. Using mock tags.");
      return ['mock', 'travel', 'photo'];
    }

    final file = File(imagePath);
    if (!await file.exists()) return [];

    final imageBytes = await file.readAsBytes();
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
      final response = await http.post(url,
          headers: {"Content-Type": "application/json"}, body: body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['responses'][0]['labelAnnotations'] == null) return [];
        final labels = data['responses'][0]['labelAnnotations'] as List;
        return labels.map((label) => label['description'] as String).toList();
      } else {
        debugPrint('Google API Error: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('HTTP request for AI tags failed: $e');
      return [];
    }
  }
}