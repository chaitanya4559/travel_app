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

  // Filter state
  DateTimeRange? _selectedDateRange;
  double? _proximityRadiusKm; // in Kilometers

  @override
  void initState() {
    super.initState();
    _setVideoBackground(themeNotifier.value);
    _searchController.addListener(_onSearchChanged);
    _initConnectionListener();
    _syncData(isInitial: true);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _initConnectionListener() {
    InternetConnectionChecker().onStatusChange.listen((status) {
      final isOnlineNow = status == InternetConnectionStatus.connected;
      if (mounted) {
        setState(() => _isOnline = isOnlineNow);
      }
      if (isOnlineNow) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Back online! Syncing data...'),
          backgroundColor: Colors.green,
        ));
        _syncData();
      }
    });
  }

  Future<void> _syncData({bool isInitial = false}) async {
    if (mounted) setState(() => _isSyncing = true);
    if (!isInitial) await _journalService.syncEntries();
    await _journalService.fetchAndStoreEntries();
    if (mounted) {
      setState(() => _isSyncing = false);
      // Re-apply search after fetching
      _onSearchChanged();
    }
  }

  void _onSearchChanged() {
    setState(() {
      // This just triggers a rebuild. The filtering logic is in build().
    });
  }

  void _setVideoBackground(ThemeMode themeMode) {
    _videoController?.dispose();
    final videoPath = themeMode == ThemeMode.dark
        ? 'assets/background.mp4'
        : 'assets/background2.mp4';
    _videoController = VideoPlayerController.asset(videoPath)
      ..initialize().then((_) {
        _videoController?.setLooping(true);
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

  void _showProfileScreen() {
    showDialog(context: context, builder: (context) => const ProfileScreen());
  }

  void _clearFilters() {
    setState(() {
      _selectedDateRange = null;
      _proximityRadiusKm = null;
    });
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Filter Entries'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('By Date Range'),
                subtitle: Text(_selectedDateRange == null
                    ? 'Not set'
                    : '${_selectedDateRange!.start.toLocal().toString().split(' ')[0]} - ${_selectedDateRange!.end.toLocal().toString().split(' ')[0]}'),
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: _selectedDateRange,
                  );
                  if (picked != null) {
                    setState(() => _selectedDateRange = picked);
                    Navigator.pop(context);
                    _showFilterDialog();
                  }
                },
              ),
              ListTile(
                title: Text(
                    'By Proximity (${_proximityRadiusKm?.toStringAsFixed(0) ?? "Any"} km)'),
                subtitle: _proximityRadiusKm == null
                    ? null
                    : Slider(
                        value: _proximityRadiusKm!,
                        min: 1,
                        max: 100,
                        divisions: 99,
                        label: '${_proximityRadiusKm!.round()} km',
                        onChanged: (value) {
                          setState(() => _proximityRadiusKm = value);
                           // A bit of a hack to rebuild dialog content
                           Navigator.pop(context);
                           _showFilterDialog();
                        },
                      ),
                onTap: () {
                  if(_proximityRadiusKm == null){
                     setState(() => _proximityRadiusKm = 10);
                     Navigator.pop(context);
                     _showFilterDialog();
                  }
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
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.value == ThemeMode.dark;
    final bool hasActiveFilters =
        _selectedDateRange != null || _proximityRadiusKm != null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: isDark
              ? Colors.black.withOpacity(0.5)
              : Colors.white.withOpacity(0.9),
          elevation: 0,
          title: _buildSearchBar(isDark),
          actions: [
            if (hasActiveFilters)
              IconButton(
                  icon: const Icon(Icons.filter_alt_off),
                  onPressed: _clearFilters,
                  tooltip: 'Clear Filters'),
            IconButton(
                icon: const Icon(Icons.filter_alt),
                onPressed: _showFilterDialog,
                tooltip: 'Filters'),
            IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                onPressed: _toggleTheme),
            IconButton(
                icon: Icon(Icons.person,
                    color: isDark ? Colors.white : Colors.black),
                onPressed: _showProfileScreen),
          ],
        ),
        body: Stack(
          children: [
            if (_videoController?.value.isInitialized ?? false)
              SizedBox.expand(
                  child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                          width: _videoController!.value.size.width,
                          height: _videoController!.value.size.height,
                          child: VideoPlayer(_videoController!)))),
            Container(
                color: isDark
                    ? Colors.black.withOpacity(0.4)
                    : Colors.white.withOpacity(0.9)),
            SafeArea(
              child: RefreshIndicator(
                onRefresh: _syncData,
                child: Column(
                  children: [
                    if (!_isOnline)
                      Container(
                        color: Colors.orange,
                        width: double.infinity,
                        padding: const EdgeInsets.all(4),
                        child: const Text('Offline mode',
                            textAlign: TextAlign.center),
                      ),
                    if (_isSyncing) const LinearProgressIndicator(),
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: Hive.box<JournalEntry>('journal_entries')
                            .listenable(),
                        builder: (context, box, _) {
                          List<JournalEntry> entries = box.values.toList();
                          final query = _searchController.text.toLowerCase();

                          // Apply keyword search
                          if (query.isNotEmpty) {
                            entries = entries.where((entry) {
                              return entry.title.toLowerCase().contains(query) ||
                                  entry.description
                                      .toLowerCase()
                                      .contains(query) ||
                                  entry.tags.any((t) => t.contains(query)) ||
                                  entry.location.toLowerCase().contains(query);
                            }).toList();
                          }

                          // Apply date range filter
                          if (_selectedDateRange != null) {
                            entries = entries.where((entry) {
                              final entryDate = DateTime.parse(entry.date);
                              return entryDate
                                      .isAfter(_selectedDateRange!.start) &&
                                  entryDate.isBefore(_selectedDateRange!.end
                                      .add(const Duration(days: 1)));
                            }).toList();
                          }

                          // Apply proximity filter
                          if (_proximityRadiusKm != null) {
                            // This would be async in a real app to avoid UI jank
                            // For simplicity, it's sync here.
                            entries = entries.where((entry) {
                              // A placeholder for current location
                              final currentLat =
                                  17.3850; // Replace with actual current location
                              final currentLon = 78.4867;
                              final distance = Geolocator.distanceBetween(
                                  currentLat,
                                  currentLon,
                                  entry.latitude,
                                  entry.longitude);
                              return (distance / 1000) <= _proximityRadiusKm!;
                            }).toList();
                          }

                          if (entries.isEmpty) {
                            return Center(
                                child: Text('No journal entries found.',
                                    style: GoogleFonts.zenDots(
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black54)));
                          }

                          return ListView.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return Dismissible(
                                key: Key(entry.id),
                                direction: DismissDirection.endToStart,
                                onDismissed: (direction) async {
                                  await _journalService.deleteEntry(entry.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              '${entry.title} deleted')));
                                },
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 20),
                                  child: const Icon(Icons.delete,
                                      color: Colors.white),
                                ),
                                child: Card(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.1)
                                      : Colors.white,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: ListTile(
                                    leading: entry.isSynced
                                        ? null
                                        : const Icon(Icons.sync_problem,
                                            color: Colors.orange),
                                    title: Text(entry.title,
                                        style: GoogleFonts.zenDots(
                                            fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                        '${entry.location}\n${entry.tags.join(', ')}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    onTap: () =>
                                        context.go('/entry/${entry.id}'),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.go('/entry'),
          backgroundColor: const Color(0xFFBF360C),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return TextField(
      controller: _searchController,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        hintText: 'Search journals...',
        hintStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        filled: true,
        fillColor: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _searchController.clear(),
              )
            : null,
      ),
    );
  }
}