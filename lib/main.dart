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

// Global ValueNotifier for theme changes, accessible throughout the app.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  // Ensure all Flutter bindings are initialized before running the app.
  WidgetsFlutterBinding.ensureInitialized();
  // Load environment variables from the .env file.
  await dotenv.load(fileName: ".env");

  // Initialize Supabase client.
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Initialize Hive for local database storage.
  final appDocumentDirectory = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDirectory.path);
  // Register the adapter for the JournalEntry model.
  Hive.registerAdapter(JournalEntryAdapter());
  // Open the box (table) for journal entries.
  await Hive.openBox<JournalEntry>('journal_entries');

  runApp(const MyApp());
}

// Centralized navigation setup using GoRouter.
final GoRouter _router = GoRouter(
  initialLocation: '/',
  // Redirect logic: If the user is not logged in, they are always directed to the login screen.
  // This protects all other routes.
  redirect: (BuildContext context, GoRouterState state) {
    final session = Supabase.instance.client.auth.currentSession;
    final bool loggedIn = session != null;
    final loggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/signup';

    if (!loggedIn) {
      // If not logged in, only allow access to login/signup pages.
      return loggingIn ? null : '/login';
    }
    if (loggingIn) {
      // If logged in and trying to access login/signup, redirect to home.
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
    // ValueListenableBuilder rebuilds the widget tree when the themeNotifier changes.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp.router(
          title: 'CarMate',
          debugShowCheckedModeBanner: false,
          // Light Theme Configuration
          theme: ThemeData.light().copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFBF360C)),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          ),
          // Dark Theme Configuration
          darkTheme: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFBF360C),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: Colors.black,
            canvasColor: Colors.black,
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