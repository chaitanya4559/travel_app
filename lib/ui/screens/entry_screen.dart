import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:travelapp/models/journal_entry.dart';
import 'package:travelapp/services/journal_service.dart';
import 'package:travelapp/services/location_service.dart';
import 'package:travelapp/services/voice_note_service.dart';
import 'package:travelapp/ui/widgets/photo_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:exif/exif.dart';

class JournalEntryScreen extends StatefulWidget {
  final String? entryId;
  const JournalEntryScreen({super.key, this.entryId});

  @override
  State<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends State<JournalEntryScreen> {
  // Services and Controllers
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagController = TextEditingController();
  final JournalService _journalService = JournalService();
  final LocationService _locationService = LocationService();
  final VoiceNoteService _voiceNoteService = VoiceNoteService();

  // State variables
  List<String> _photoPaths = [];
  List<String> _manualTags = [];
  bool _isLoading = true;
  String? _voiceNotePath;
  String _transcription = '';
  bool _isRecording = false;
  DateTime _adventureDate = DateTime.now();

  // Location state
  String? _deviceLocation;
  Map<String, String> _photoLocations = {};
  double _latitude = 0.0;
  double _longitude = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    _voiceNoteService.dispose();
    super.dispose();
  }

  // --- Data Logic ---

  Future<void> _initializeScreen() async {
    if (widget.entryId != null) {
      await _loadEntry();
    } else {
      await _fetchLocation();
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadEntry() async {
    final entry = _journalService.getEntryById(widget.entryId!);
    if (entry != null) {
      _titleController.text = entry.title;
      _descriptionController.text = entry.description;
      _photoPaths = List.from(entry.photoPaths);

      final allLocations =
          entry.location.split(' | ').where((loc) => loc.isNotEmpty).toList();
      if (allLocations.isNotEmpty) {
        _deviceLocation = allLocations.first;
        if (allLocations.length > 1) {
          final photoLocs = allLocations.sublist(1);
          for (var i = 0; i < _photoPaths.length && i < photoLocs.length; i++) {
            _photoLocations[_photoPaths[i]] = photoLocs[i];
          }
        }
      }

      _latitude = entry.latitude;
      _longitude = entry.longitude;
      _voiceNotePath = entry.voiceNotePath;
      _transcription = entry.transcription;
      _manualTags = List.from(entry.tags);
      _adventureDate = DateTime.parse(entry.date);
    }
  }

  Future<void> _fetchLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (position != null && mounted) {
        final address = await _locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
        setState(() {
          _deviceLocation = address;
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deviceLocation = 'Location not available');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
      }
    }
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final allLocations = <String>[
        if (_deviceLocation != null) _deviceLocation!,
        ..._photoPaths.map((path) => _photoLocations[path]).whereType<String>()
      ];

      final entry = JournalEntry(
        id: widget.entryId ?? const Uuid().v4(),
        title: _titleController.text,
        description: _descriptionController.text,
        photoPaths: _photoPaths,
        date: _adventureDate.toIso8601String(),
        location: allLocations.join(' | '),
        tags: _manualTags,
        latitude: _latitude,
        longitude: _longitude,
        voiceNotePath: _voiceNotePath ?? '',
        transcription: _transcription,
      );
      await _journalService.saveEntry(entry);
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save entry: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectAdventureDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _adventureDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (pickedDate != null && pickedDate != _adventureDate) {
      setState(() {
        _adventureDate = pickedDate;
      });
    }
  }

  Future<void> _onPhotosSelected(
      List<String> allPaths, PhotoSelectionResult? newPhoto) async {
    setState(() {
      _photoPaths = allPaths;
      _isLoading = true;
    });

    final newPhotoLocations = <String, String>{};
    for (final path in allPaths) {
      if (_photoLocations.containsKey(path)) {
        newPhotoLocations[path] = _photoLocations[path]!;
      }
    }

    if (newPhoto != null) {
      String? newAddress;
      if (newPhoto.source == ImageSource.camera) {
        newAddress = _deviceLocation;
        // Keep the device's main lat/lon as it's the most current.
      } else {
        final locationData =
            await _locationService.getAddressFromExif(newPhoto.path);
        if (locationData != null) {
          newAddress = locationData;
          // Set primary lat/lon if it's the first photo with GPS and device location hasn't been set.
          // If you need latitude/longitude, you must update getAddressFromExif to return those.
        }
      }

      if (newAddress != null) {
        newPhotoLocations[newPhoto.path] = newAddress;
      }
    }

    setState(() {
      _photoLocations = newPhotoLocations;
      _isLoading = false;
    });
  }

  void _addManualTag(String tag) {
    if (tag.trim().isNotEmpty && !_manualTags.contains(tag.trim())) {
      setState(() {
        _manualTags.add(tag.trim());
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _manualTags.remove(tag));
  }

  Future<void> _getAITags() async {
    if (_photoPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a photo first.')),
      );
      return;
    }
    _showPhotoSelectionDialog();
  }

  Future<void> _showPhotoSelectionDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select a Photo for AI Tags'),
          content: SingleChildScrollView(
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _photoPaths.map((path) {
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    _generateTagsForSelectedPhoto(path);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: path.startsWith('http')
                        ? Image.network(path,
                            width: 80, height: 80, fit: BoxFit.cover)
                        : Image.file(File(path),
                            width: 80, height: 80, fit: BoxFit.cover),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateTagsForSelectedPhoto(String photoIdentifier) async {
    setState(() => _isLoading = true);
    try {
      final tags = await _journalService.getAITagsForImage(photoIdentifier);
      if (tags.isNotEmpty && mounted) {
        setState(() {
          _manualTags.addAll(tags);
          _manualTags = _manualTags.toSet().toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI tags generated successfully!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No relevant tags found for this image.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to get AI tags: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showFeatureNotAvailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This feature is currently not available.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    _showFeatureNotAvailable();
  }

  Future<void> _deleteEntry() async {
    if (widget.entryId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Adventure?'),
        content: const Text('This action is permanent and cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _journalService.deleteEntry(widget.entryId!);
      if (mounted) {
        context.go('/');
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Entry deleted.')));
      }
    }
  }

  // --- Build Methods ---
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: _buildAppBar(theme),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildFormContent(),
    );
  }

  AppBar _buildAppBar(ThemeData theme) {
    return AppBar(
      title: Text(widget.entryId == null ? 'New Adventure' : 'Edit Adventure',
          style: GoogleFonts.zenDots()),
      leading: IconButton(
          icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
      actions: [
        if (widget.entryId != null)
          IconButton(
            icon: Icon(Icons.delete, color: theme.colorScheme.error),
            onPressed: _deleteEntry,
          ),
      ],
    );
  }

  Widget _buildFormContent() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTextFieldsSection(),
                  const SizedBox(height: 16),
                  PhotoPicker(
                      onPhotosSelected: _onPhotosSelected,
                      initialPhotos: _photoPaths),
                  const SizedBox(height: 16),
                  _buildLocationSection(),
                  const SizedBox(height: 16),
                  _buildVoiceNoteSection(),
                  const SizedBox(height: 16),
                  _buildTaggingSection(),
                  _buildTagsDisplay(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
        _buildSaveButton(),
      ],
    );
  }

  Widget _buildTextFieldsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              validator: (v) => v!.isEmpty ? 'Please enter a title' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              validator: (v) =>
                  v!.isEmpty ? 'Please enter a description' : null,
            ),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.calendar_today),
              title: const Text('Adventure Date'),
              subtitle: Text(
                DateFormat.yMMMMd().format(_adventureDate),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: _selectAdventureDate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    final allLocations = [
      if (_deviceLocation != null) MapEntry('device', _deviceLocation!),
      ..._photoPaths.map((path) {
        return _photoLocations.containsKey(path)
            ? MapEntry(path, _photoLocations[path]!)
            : null;
      }).whereType<MapEntry<String, String>>()
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Locations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (allLocations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('No location data available.',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              )
            else
              ...allLocations.asMap().entries.map((entry) {
                final index = entry.key;
                final locationData = entry.value;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    locationData.key == 'device'
                        ? Icons.my_location
                        : Icons.photo_camera,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  title: Text(locationData.value),
                  subtitle: Text(locationData.key == 'device'
                      ? 'Device Location'
                      : 'From Photo ${index + 1}'),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTaggingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40)),
              onPressed:
                  (_photoPaths.isNotEmpty && !_isLoading) ? _getAITags : null,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate AI Tags from Photo'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tagController,
              decoration: InputDecoration(
                labelText: 'Add a manual tag',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_circle),
                  onPressed: () => _addManualTag(_tagController.text),
                ),
              ),
              onFieldSubmitted: _addManualTag,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: ElevatedButton.icon(
        onPressed: _isLoading || _isRecording ? null : _saveEntry,
        icon: const Icon(Icons.save),
        label: const Text('Save Adventure'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                const Text('Voice Note',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.mic_off, color: Colors.grey),
                  onPressed: _showFeatureNotAvailable,
                ),
              ],
            ),
            if (_voiceNotePath != null && _voiceNotePath!.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.play_disabled, color: Colors.grey),
                onPressed: _showFeatureNotAvailable,
              ),
            if (_transcription.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Text('Transcription: $_transcription',
                    style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
          ],
        ),
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