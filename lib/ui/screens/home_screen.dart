import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:travelapp/main.dart';
import 'package:travelapp/models/journal_entry.dart';
import 'package:travelapp/services/journal_service.dart';
import 'package:travelapp/ui/screens/profile_screen.dart';
import 'package:travelapp/ui/widgets/journal_card.dart';
import 'package:video_player/video_player.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final JournalService _journalService = JournalService();
  final _searchController = TextEditingController();
  bool _isSyncing = false;
  bool _isOnline = true;
  VideoPlayerController? _videoController;
  Position? _currentPosition;

  DateTimeRange? _selectedDateRange;
  double? _proximityRadiusKm;

  @override
  void initState() {
    super.initState();
    _setVideoBackground(themeNotifier.value);
    _searchController.addListener(() => setState(() {}));
    _initConnectionListener();
    _syncData(isInitial: true);
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _initConnectionListener() {
    InternetConnectionChecker().onStatusChange.listen((status) {
      final isOnlineNow = status == InternetConnectionStatus.connected;
      if (mounted) setState(() => _isOnline = isOnlineNow);
      if (isOnlineNow) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Back online! Syncing data...'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ));
        _syncData();
      }
    });
  }

  Future<void> _syncData({bool isInitial = false}) async {
    if (mounted) setState(() => _isSyncing = true);
    if (!isInitial) await _journalService.syncEntries();
    await _journalService.fetchAndStoreEntries();
    if (mounted) setState(() => _isSyncing = false);
  }

  void _setVideoBackground(ThemeMode themeMode) {
    _videoController?.dispose();
    final videoPath = themeMode == ThemeMode.dark
        ? 'assets/background.mp4'
        : 'assets/background2.mp4';
    _videoController = VideoPlayerController.asset(videoPath)
      ..initialize().then((_) {
        _videoController?.setLooping(true);
        _videoController?.setVolume(0);
        _videoController?.play();
        if (mounted) setState(() {});
      });
  }

  void _toggleTheme() {
    final newTheme = themeNotifier.value == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    themeNotifier.value = newTheme;
    _setVideoBackground(newTheme);
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = position);
    } catch (e) {
      debugPrint("Could not get location: $e");
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedDateRange = null;
      _proximityRadiusKm = null;
    });
  }

  void _showFilterDialog() {
    DateTimeRange? tempDateRange = _selectedDateRange;
    double? tempProximity = _proximityRadiusKm;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter Entries'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('By Date Range'),
                    subtitle: Text(tempDateRange == null
                        ? 'Not set'
                        : '${tempDateRange?.start.toLocal().toString().split(' ')[0]} - ${tempDateRange?.end.toLocal().toString().split(' ')[0]}'),
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: tempDateRange,
                      );
                      if (picked != null) {
                        setDialogState(() => tempDateRange = picked);
                      }
                    },
                  ),
                  ListTile(
                    title: Text(
                        'By Proximity (${tempProximity?.toStringAsFixed(0) ?? "Any"} km)'),
                    onTap: () {
                      if (tempProximity == null) {
                        setDialogState(() => tempProximity = 10);
                      }
                    },
                  ),
                  if (tempProximity != null)
                    Slider(
                      value: tempProximity ?? 10,
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: '${(tempProximity ?? 10).round()} km',
                      onChanged: (value) {
                        setDialogState(() => tempProximity = value);
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _clearFilters();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear All'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _selectedDateRange = tempDateRange;
                      _proximityRadiusKm = tempProximity;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<JournalEntry> _getFilteredEntries(List<JournalEntry> entries) {
    final query = _searchController.text.toLowerCase();

    return entries.where((entry) {
      if (query.isNotEmpty) {
        final searchableText =
            '${entry.title} ${entry.description} ${entry.tags.join(' ')} ${entry.location}'
                .toLowerCase();
        if (!searchableText.contains(query)) return false;
      }
      if (_selectedDateRange != null) {
        final entryDate = DateTime.parse(entry.date);
        if (entryDate.isBefore(_selectedDateRange!.start) ||
            entryDate.isAfter(
                _selectedDateRange!.end.add(const Duration(days: 1)))) {
          return false;
        }
      }
      if (_proximityRadiusKm != null && _currentPosition != null) {
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          entry.latitude,
          entry.longitude,
        );
        if ((distance / 1000) > _proximityRadiusKm!) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasActiveFilters =
        _selectedDateRange != null || _proximityRadiusKm != null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(theme, hasActiveFilters),
        body: _buildBody(theme),
        floatingActionButton: _buildFAB(theme),
      ),
    );
  }

  AppBar _buildAppBar(ThemeData theme, bool hasActiveFilters) {
    return AppBar(
      backgroundColor: theme.colorScheme.surface.withOpacity(0.8),
      elevation: 0,
      title: _buildSearchBar(theme),
      actions: [
        if (hasActiveFilters)
          IconButton(
            icon: const Icon(Icons.filter_alt_off),
            onPressed: _clearFilters,
            tooltip: 'Clear Filters',
          ),
        IconButton(
          icon: Icon(
            hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
            color: hasActiveFilters ? theme.colorScheme.primary : null,
          ),
          onPressed: _showFilterDialog,
          tooltip: 'Filters',
        ),
        IconButton(
          icon: Icon(theme.brightness == Brightness.dark
              ? Icons.light_mode
              : Icons.dark_mode),
          onPressed: _toggleTheme,
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => showDialog(
              context: context, builder: (_) => const ProfileScreen()),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search journals...',
        hintStyle: TextStyle(color: theme.colorScheme.onTertiaryContainer),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        filled: true,
        fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        isDense: true,
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _searchController.clear(),
              )
            : null,
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return Stack(
      children: [
        // Fullscreen video background
        if (_videoController?.value.isInitialized ?? false)
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          ),

        // Subtle overlay for readability
        Container(
          color: theme.brightness == Brightness.dark
              ? Colors.black.withOpacity(0.2)
              : Colors.white.withOpacity(0.2),
        ),

        // Actual UI content
        SafeArea(
          child: Column(
            children: [
              if (!_isOnline)
                Container(
                  color: theme.colorScheme.tertiaryContainer,
                  width: double.infinity,
                  padding: const EdgeInsets.all(4),
                  child: Text('Offline mode',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: theme.colorScheme.onTertiaryContainer)),
                ),
              if (_isSyncing) const LinearProgressIndicator(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _syncData,
                  child: _buildEntriesList(theme),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEntriesList(ThemeData theme) {
    return ValueListenableBuilder(
      valueListenable: Hive.box<JournalEntry>('journal_entries').listenable(),
      builder: (context, box, _) {
        final entries = _getFilteredEntries(box.values.toList());

        if (entries.isEmpty) {
          return Center(
            child: Text(
              'No journal entries found.',
              style: GoogleFonts.zenDots(
                  color: theme.colorScheme.onSurface.withOpacity(0.7)),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return JournalCard(
              entry: entry,
              onDismissed: (entryId) async {
                await _journalService.deleteEntry(entryId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${entry.title} deleted')),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFAB(ThemeData theme) {
    return FloatingActionButton(
      onPressed: () => context.go('/entry'),
      backgroundColor: theme.colorScheme.primary,
      foregroundColor: theme.colorScheme.onPrimary,
      child: const Icon(Icons.add),
    );
  }
}
