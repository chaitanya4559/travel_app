import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:travelapp/models/journal_entry.dart';
import 'package:travelapp/services/journal_service.dart';
import 'package:travelapp/services/location_service.dart';
import 'package:travelapp/services/voice_note_service.dart';
import 'package:travelapp/ui/widgets/photo_picker.dart';
import 'package:uuid/uuid.dart';

class JournalEntryScreen extends StatefulWidget {
  final String? entryId;
  const JournalEntryScreen({super.key, this.entryId});

  @override
  State<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends State<JournalEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagController = TextEditingController();
  final JournalService _journalService = JournalService();
  final LocationService _locationService = LocationService();
  final VoiceNoteService _voiceNoteService = VoiceNoteService();

  List<String> _photoPaths = [];
  List<String> _manualTags = [];
  String _location = 'Fetching location...';
  double _latitude = 0;
  double _longitude = 0;
  bool _isLoading = false;
  String? _voiceNotePath;
  String _transcription = '';
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    if (widget.entryId != null) {
      _loadEntry();
    } else {
      _fetchLocation();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    _voiceNoteService.dispose();
    super.dispose();
  }

  Future<void> _loadEntry() async {
    setState(() => _isLoading = true);
    final entry = _journalService.getEntryById(widget.entryId!);
    if (entry != null) {
      _titleController.text = entry.title;
      _descriptionController.text = entry.description;
      _photoPaths = List.from(entry.photoPaths);
      _location = entry.location;
      _latitude = entry.latitude;
      _longitude = entry.longitude;
      _voiceNotePath = entry.voiceNotePath;
      _transcription = entry.transcription;
      _manualTags = List.from(entry.tags);
    }
    setState(() => _isLoading = false);
  }

  void _onPhotosSelected(List<String> paths) {
    setState(() => _photoPaths = paths);
  }

  Future<void> _fetchLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _location =
              'Lat: ${position.latitude.toStringAsFixed(2)}, Lon: ${position.longitude.toStringAsFixed(2)}';
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _location = 'Location not available');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
      }
    }
  }

  Future<void> _getAITags() async {
    final localPhotoPath = _photoPaths.firstWhere(
      (p) => !p.startsWith('http'),
      orElse: () => '',
    );

    if (localPhotoPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('AI tags can only be generated for new photos.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final tags = await _journalService.getAITagsForImage(localPhotoPath);
      if (tags.isNotEmpty && mounted) {
        setState(() {
          _manualTags.addAll(tags);
          _manualTags = _manualTags.toSet().toList(); // Remove duplicates
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI tags generated successfully!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No tags found for this image.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to get AI tags: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addManualTag(String tag) {
    if (tag.trim().isNotEmpty) {
      setState(() {
        _manualTags.add(tag.trim());
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _manualTags.remove(tag));
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      final path = await _voiceNoteService.stopRecording();
      if (path != null) {
        final transcription = await _voiceNoteService.transcribeAudio(path);
        setState(() {
          _transcription = transcription;
        });
      }
      setState(() => _isRecording = false);
    } else {
      // Start recording
      final path = await _voiceNoteService.startRecording();
      setState(() {
        _isRecording = true;
        _voiceNotePath = path;
        _transcription = 'Transcribing...';
      });
    }
  }

  Future<void> _deleteEntry() async {
    if (widget.entryId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Adventure?'),
        content: const Text(
            'This action is permanent and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _journalService.deleteEntry(widget.entryId!);
      if (mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry deleted.')));
      }
    }
  }

  Future<void> _saveEntry() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final entry = JournalEntry(
        id: widget.entryId ?? const Uuid().v4(),
        title: _titleController.text,
        description: _descriptionController.text,
        photoPaths: _photoPaths,
        date: DateTime.now().toIso8601String(),
        location: _location,
        tags: _manualTags,
        latitude: _latitude,
        longitude: _longitude,
        voiceNotePath: _voiceNotePath ?? '',
        transcription: _transcription,
      );
      await _journalService.saveEntry(entry);
      if (mounted) {
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entryId == null ? 'New Entry' : 'Edit Entry',
            style: GoogleFonts.zenDots()),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/')),
        actions: [
          if (widget.entryId != null)
            IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _deleteEntry),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                        validator: (v) => v!.isEmpty ? 'Please enter a title' : null),
                    const SizedBox(height: 16),
                    TextFormField(
                        controller: _descriptionController,
                        decoration:
                            const InputDecoration(labelText: 'Description'),
                        maxLines: 5,
                        validator: (v) =>
                            v!.isEmpty ? 'Please enter a description' : null),
                    const SizedBox(height: 16),
                    PhotoPicker(
                        onPhotosSelected: _onPhotosSelected,
                        initialPhotos: _photoPaths),
                    const SizedBox(height: 16),
                    ListTile(
                        leading: const Icon(Icons.location_on),
                        title: Text(_location)),
                    const SizedBox(height: 16),
                    _buildVoiceNoteSection(),
                    const SizedBox(height: 16),
                    _buildAITaggingSection(),
                    _buildManualTaggingSection(),
                    _buildTagsDisplay(),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isLoading || _isRecording ? null : _saveEntry,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFBF360C),
                          foregroundColor: Colors.white),
                      child: const Text('Save Entry'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
  
  Widget _buildVoiceNoteSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Voice Note', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.red : Colors.green),
                  onPressed: _toggleRecording,
                ),
              ],
            ),
            if (_voiceNotePath != null)
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => _voiceNoteService.startPlayback(_voiceNotePath!),
              ),
            if (_transcription.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 8.0),
                child: Text('Transcription: $_transcription', style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAITaggingSection() {
    return ElevatedButton.icon(
      onPressed: (_photoPaths.isNotEmpty && !_isLoading) ? _getAITags : null,
      icon: const Icon(Icons.auto_awesome),
      label: const Text('Get AI Tags'),
    );
  }

  Widget _buildManualTaggingSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _tagController,
              decoration: const InputDecoration(labelText: 'Add a tag', border: OutlineInputBorder()),
              onFieldSubmitted: _addManualTag,
            ),
          ),
          IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.green),
              onPressed: () => _addManualTag(_tagController.text)),
        ],
      ),
    );
  }

  Widget _buildTagsDisplay() {
    if (_manualTags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        children: _manualTags
            .map((tag) => Chip(
                  label: Text(tag),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => _removeTag(tag),
                ))
            .toList(),
      ),
    );
  }
}