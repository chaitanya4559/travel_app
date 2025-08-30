// lib/ui/widgets/journal_card.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:travelapp/models/journal_entry.dart';

class JournalCard extends StatelessWidget {
  final JournalEntry entry;
  final void Function(String entryId) onDismissed;

  const JournalCard({
    super.key,
    required this.entry,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => onDismissed(entry.id),
      background: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete, color: theme.colorScheme.onErrorContainer),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () => context.go('/entry/${entry.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCardImage(theme),
              _buildCardContent(theme),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the image section of the card with a placeholder.
  Widget _buildCardImage(ThemeData theme) {
    if (entry.photoPaths.isNotEmpty) {
      final String path = entry.photoPaths.first;

      // Check if it's a Supabase URL or local file
      final bool isUrl = path.startsWith('http');

      return Hero(
        tag: 'entry_image_${entry.id}',
        child: isUrl
            ? Image.network(
                path,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                (progress.expectedTotalBytes ?? 1)
                            : null),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return _buildImagePlaceholder(theme,
                      icon: Icons.broken_image, text: 'Load Error');
                },
              )
            : Image.file(
                File(path),
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildImagePlaceholder(theme,
                      icon: Icons.broken_image, text: 'Load Error');
                },
              ),
      );
    } else {
      return _buildImagePlaceholder(theme,
          icon: Icons.photo_size_select_actual_outlined, text: 'No Image');
    }
  }

  /// A consistent placeholder widget for when there is no image.
  Widget _buildImagePlaceholder(ThemeData theme,
      {required IconData icon, required String text}) {
    return Container(
      height: 150,
      width: double.infinity,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(text,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// Builds the text content section of the card.
  Widget _buildCardContent(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  style: GoogleFonts.zenDots(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!entry.isSynced)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.sync_problem,
                      color: theme.colorScheme.tertiary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.location,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          if (entry.tags.isNotEmpty)
            Text(
              'Tags: ${entry.tags.join(', ')}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.secondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
