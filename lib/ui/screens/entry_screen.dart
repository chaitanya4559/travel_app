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
  String _location = 'Fetching location...';
  double _latitude = 0;
  double _longitude = 0;
  bool _isLoading = true;
  String? _voiceNotePath;
  String _transcription = '';
  bool _isRecording = false;

  // ✅ 1. Add a state variable to hold the original date when editing.
  String? _originalDate;

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
      _location = entry.location;
      _latitude = entry.latitude;
      _longitude = entry.longitude;
      _voiceNotePath = entry.voiceNotePath;
      _transcription = entry.transcription;
      _manualTags = List.from(entry.tags);
      // ✅ 2. When loading an existing entry, store its original date.
      _originalDate = entry.date;
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
          _location = address;
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _location = 'Location not available');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to get location: $e')));
      }
    }
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final entry = JournalEntry(
        id: widget.entryId ?? const Uuid().v4(),
        title: _titleController.text,
        description: _descriptionController.text,
        photoPaths: _photoPaths,
        // ✅ 3. Use the original date if editing, otherwise use the current date.
        date: _originalDate ?? DateTime.now().toIso8601String(),
        location: _location,
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

  // --- Other UI handlers (no changes needed) ---
  void _onPhotosSelected(List<String> paths) =>
      setState(() => _photoPaths = paths);
  void _addManualTag(String tag) {/* ... */}
  void _removeTag(String tag) {/* ... */}
  Future<void> _getAITags() async {/* ... */}
  Future<void> _toggleRecording() async {/* ... */}
  Future<void> _deleteEntry() async {/* ... */}

  // --- Build Methods (no changes needed) ---
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
            padding: const EdgeInsets.all(16),
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
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    return Card(
      child: ListTile(
        leading: Icon(Icons.location_on,
            color: Theme.of(context).colorScheme.secondary),
        title: Text(_location,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Location'),
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
              label: const Text('Generate AI Tags'),
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
    /* Your existing code */ return const SizedBox.shrink();
  }

  Widget _buildTagsDisplay() {
    /* Your existing code */ return const SizedBox.shrink();
  }
}
