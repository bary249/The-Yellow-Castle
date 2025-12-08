import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/main_menu_screen.dart';
import 'screens/auth_screen.dart';
import 'services/auth_service.dart';

bool _firebaseInitialized = false;

Future<void> main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    if (kIsWeb) {
      // Web requires explicit options
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    } else {
      // Mobile/desktop use bundled platform config
      await Firebase.initializeApp();
    }
    _firebaseInitialized = true;
  } catch (e) {
    print("Firebase initialization failed: $e");
    print("Running in offline/demo mode");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Land of Clans & Wanderers',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 2),
      ),
      home: const AuthWrapper(),
    );
  }
}

/// Wrapper that listens to auth state and shows appropriate screen
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // If Firebase failed to initialize, bypass auth and show main menu (Demo Mode)
    if (!_firebaseInitialized) {
      return const MainMenuScreen();
    }

    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading...'),
                ],
              ),
            ),
          );
        }

        // If user is logged in, show main menu
        if (snapshot.hasData && snapshot.data != null) {
          return const MainMenuScreen();
        }

        // Otherwise show auth screen
        return const AuthScreen();
      },
    );
  }
}
