// FINALIZED CODE

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:travelapp/auth/login_screen.dart';
import 'package:travelapp/auth/register_screen.dart';
import 'package:travelapp/models/journal_entry.dart';
import 'package:travelapp/ui/screens/entry_screen.dart';
import 'package:travelapp/ui/screens/home_screen.dart';


// Global ValueNotifier for theme changes
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

// ✅ 1. Create a ValueNotifier to notify GoRouter of auth state changes.
final _authNotifier = ValueNotifier<bool>(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  final appDocumentDirectory = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDirectory.path);
  Hive.registerAdapter(JournalEntryAdapter());
  await Hive.openBox<JournalEntry>('journal_entries');

  // ✅ 2. Listen to Supabase auth changes and update the notifier.
  // This is the key to making navigation automatic after login/logout.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    _authNotifier.value = data.session != null;
  });

  runApp(const MyApp());
}

// Centralized navigation setup using GoRouter.
final GoRouter _router = GoRouter(
  initialLocation: '/',
  // ✅ 3. Pass the notifier to GoRouter. It will now rebuild routes on auth changes.
  refreshListenable: _authNotifier,
  redirect: (BuildContext context, GoRouterState state) {
    final bool loggedIn = Supabase.instance.client.auth.currentUser != null;
    final bool isLoggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/signup';

    if (!loggedIn && !isLoggingIn) {
      return '/login';
    }

    if (loggedIn && isLoggingIn) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
    GoRoute(path: '/entry', builder: (context, state) => const JournalEntryScreen()),
    GoRoute(
      path: '/entry/:id',
      builder: (context, state) {
        final entryId = state.pathParameters['id']!;
        return JournalEntryScreen(entryId: entryId);
      },
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp.router(
          title: 'WanderLog', // Using the new project name
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light().copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFBF360C)),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFBF360C),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
            canvasColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          ),
          themeMode: mode,
          routerConfig: _router,
        );
      },
    );
  }
}