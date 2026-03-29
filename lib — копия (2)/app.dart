import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

class CineWordsApp extends StatelessWidget {
  const CineWordsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'CineWords',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.isMonochrome 
              ? AppTheme.monochromeTheme() 
              : AppTheme.lightTheme(dynamicScheme: lightDynamic),
          darkTheme: themeProvider.isMonochrome 
              ? AppTheme.monochromeTheme() 
              : AppTheme.darkTheme(dynamicScheme: darkDynamic),
          themeMode: themeProvider.flutterThemeMode,
          home: Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (auth.isLoading) return const SplashScreen();
              if (auth.isAuthenticated) return const HomeScreen();
              return const LoginScreen();
            },
          ),
        );
      },
    );
  }
}
