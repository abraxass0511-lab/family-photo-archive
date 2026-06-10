import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/photo_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/transfer_provider.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhotoBackupApp());
}

class PhotoBackupApp extends StatelessWidget {
  const PhotoBackupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PhotoProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        ChangeNotifierProvider(create: (_) => TransferProvider()),
      ],
      child: MaterialApp(
        title: '포토 백업',
        debugShowCheckedModeBanner: false,
        theme: _buildDarkTheme(),
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F5F8),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF7C6AEF),
        secondary: Color(0xFF4ECDC4),
        surface: Colors.white,
        error: Color(0xFFFF4D6D),
      ),
      textTheme: GoogleFonts.notoSansTextTheme(
        ThemeData.light().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Color(0xFF1A1A2E),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF7C6AEF),
        unselectedItemColor: Color(0xFF9E9EB8),
      ),
    );
  }
}
