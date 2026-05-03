import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'pages/splash_page.dart';
import 'Services/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AcadifyApp());
}

class AcadifyApp extends StatelessWidget {
  const AcadifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Acadify',
            debugShowCheckedModeBanner: false,
            themeMode: theme.isDark ? ThemeMode.dark : ThemeMode.light,
            theme: ThemeData(
              colorSchemeSeed: const Color(0xFF7C4DFF),
              brightness: Brightness.light,
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorSchemeSeed: const Color(0xFF7C4DFF),
              brightness: Brightness.dark,
              useMaterial3: true,
            ),
            home: const SplashPage(),
          );
        },
      ),
    );
  }
}
