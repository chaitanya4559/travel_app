// lib/services/voice_note_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

class VoiceNoteService {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  bool _isRecorderInitialized = false;
  final String? _googleApiKey = dotenv.env['GOOGLE_API_KEY'];
  final Uuid _uuid = const Uuid();

  VoiceNoteService() {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
  }

  Future<void> _initRecorder() async {
    if (_isRecorderInitialized) return;
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _recorder!.openRecorder();
    _isRecorderInitialized = true;
  }

  Future<void> dispose() async {
    await _recorder?.closeRecorder();
    await _player?.closePlayer();
    _recorder = null;
    _player = null;
  }

  Future<String> startRecording() async {
    await _initRecorder();
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/${_uuid.v4()}.aac';
    await _recorder!.startRecorder(toFile: path, codec: Codec.aacADTS);
    return path;
  }

  Future<String?> stopRecording() async {
    return await _recorder!.stopRecorder();
  }

  Future<void> startPlayback(String path) async {
    await _player!.openPlayer();
    await _player!.startPlayer(fromURI: path);
  }

  Future<String> transcribeAudio(String audioPath) async {
    if (_googleApiKey == null ||
        _googleApiKey == 'YOUR_GOOGLE_CLOUD_API_KEY_HERE') {
      debugPrint("Warning: Speech-to-Text API key not set.");
      return "Mock transcription of the voice note.";
    }

    final audioFile = File(audioPath);
    final audioBytes = await audioFile.readAsBytes();
    final audioBase64 = base64Encode(audioBytes);

    final url = Uri.parse(
        "https://speech.googleapis.com/v1/speech:recognize?key=$_googleApiKey");

    final body = jsonEncode({
      "config": {
        "encoding": "AAC",
        "sampleRateHertz": 44100, // Common sample rate
        "languageCode": "en-US",
      },
      "audio": {"content": audioBase64},
    });

    try {
      final response = await http
          .post(url, headers: {"Content-Type": "application/json"}, body: body);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['results'] != null) {
        return data['results'][0]['alternatives'][0]['transcript'] as String;
      } else {
        debugPrint('Google Speech API Error: ${response.body}');
        return "Transcription failed.";
      }
    } catch (e) {
      debugPrint('HTTP request for transcription failed: $e');
      return "Transcription failed due to a network error.";
    }
  }
}