import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// Helper class to return both the path and the source of the new image.
class PhotoSelectionResult {
  final String path;
  final ImageSource source;
  PhotoSelectionResult(this.path, this.source);
}

class PhotoPicker extends StatefulWidget {
  // The callback now provides the full list and the newly added photo's details.
  final Function(List<String> allPaths, PhotoSelectionResult? newPhoto)
      onPhotosSelected;
  final List<String> initialPhotos;

  const PhotoPicker({
    super.key,
    required this.onPhotosSelected,
    this.initialPhotos = const [],
  });

  @override
  State<PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends State<PhotoPicker> {
  List<String> _photos = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.initialPhotos);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_photos.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can add a maximum of 5 photos.')));
      return;
    }
    final pickedFile =
        await _picker.pickImage(source: source, requestFullMetadata: true);
    if (pickedFile != null) {
      setState(() => _photos.add(pickedFile.path));
      // Pass both the full list and the details of the new photo back.
      widget.onPhotosSelected(
          _photos, PhotoSelectionResult(pickedFile.path, source));
    }
  }

  void _removePhoto(String path) {
    setState(() => _photos.remove(path));
    // When removing, we don't have a "new" photo, so the second argument is null.
    widget.onPhotosSelected(_photos, null);
  }

  void _reorderPhotos(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final String photo = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, photo);
      widget.onPhotosSelected(_photos, null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The UI for this widget is unchanged.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera')),
            ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery')),
          ],
        ),
        const SizedBox(height: 16),
        if (_photos.isNotEmpty)
          SizedBox(
            height: 100,
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              onReorder: _reorderPhotos,
              children: _photos.map((path) {
                return Padding(
                  key: Key(path),
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: path.startsWith('http')
                            ? Image.network(path,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.broken_image, size: 100))
                            : Image.file(File(path),
                                width: 100, height: 100, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        child: GestureDetector(
                          onTap: () => _removePhoto(path),
                          child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.red,
                              child: Icon(Icons.close,
                                  size: 16, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}