import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/main_menu_screen.dart';
import 'services/auth_service.dart';

final _authService = AuthService();

Future<void> main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  if (kIsWeb) {
    // Web requires explicit options
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } else {
    // Mobile/desktop use bundled platform config
    await Firebase.initializeApp();
  }

  // Simple smoke test: ensure we're signed in anonymously
  await _authService.signInAnonymously();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Land of Clans & Wanderers - Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 2),
      ),
      home: const MainMenuScreen(),
    );
  }
}
