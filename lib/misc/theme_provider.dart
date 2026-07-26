import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _lightScheme = ColorScheme.fromSeed(
  brightness: Brightness.light,
  seedColor: Colors.white,
  primary: infiniteSportsPrimaryColor,
  dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
);

// Dark mode is black & gold: gold accents wherever light mode uses red.
// onPrimary is near-black so anything filled with primary (buttons, pills,
// banners) gets readable dark text on gold instead of white.
final _darkScheme = ColorScheme.fromSeed(
  brightness: Brightness.dark,
  seedColor: Colors.black,
  primary: infiniteSportsGoldColor,
  dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
).copyWith(
  onPrimary: const Color(0xFF1A1206),
);

ThemeData lightMode = ThemeData(
  // This is the theme of your application.
  //
  // TRY THIS: Try running your application with "flutter run". You'll see
  // the application has a purple toolbar. Then, without quitting the app,
  // try changing the seedColor in the colorScheme below to Colors.green
  // and then invoke "hot reload" (save your changes or press the "hot
  // reload" button in a Flutter-supported IDE, or press "r" if you used
  // the command line to start the app).
  //
  // Notice that the counter didn't reset back to zero; the application
  // state is not lost during the reload. To reset the state, use hot
  // restart instead.
  //
  // This works for code too, not just values: Most code changes can be
  // tested with just a hot reload.
  brightness: Brightness.light,
  colorScheme: _lightScheme,
  useMaterial3: true,
  appBarTheme: AppBarTheme(
    backgroundColor: _lightScheme.surface,
    foregroundColor: _lightScheme.onSurface,
    elevation: 0,
    scrolledUnderElevation: 0.5,
    centerTitle: true,
    iconTheme: IconThemeData(color: _lightScheme.onSurface),
    actionsIconTheme: IconThemeData(color: _lightScheme.onSurface),
  ),
);

ThemeData darkMode = ThemeData(
  brightness: Brightness.dark,
  colorScheme: _darkScheme,
  useMaterial3: true,
  appBarTheme: AppBarTheme(
    backgroundColor: _darkScheme.surface,
    foregroundColor: _darkScheme.onSurface,
    elevation: 0,
    scrolledUnderElevation: 0.5,
    centerTitle: true,
    iconTheme: IconThemeData(color: _darkScheme.onSurface),
    actionsIconTheme: IconThemeData(color: _darkScheme.onSurface),
  ),
);

/// Startup dark-mode default (auth-wall F2 owner feedback): resolves the
/// persisted `darkMode` pref ([storedPref], from
/// `SharedPreferences.getBool('darkMode')`) into the value `main()` seeds
/// `ThemeProvider` with. A brand-new install has no pref yet (`null`) and now
/// defaults to dark instead of the previous light default. A user who
/// explicitly chose light before this change shipped has `false` stored,
/// which is kept as-is — this only changes the ABSENT case.
bool resolveDarkModeDefault(bool? storedPref) => storedPref ?? true;

enum ThemeModes{
  light,
  dark
}
class ThemeProvider with ChangeNotifier {
  ThemeData _themeData = lightMode;
  ThemeData get themeData => _themeData;
  
  set themeData(ThemeData themeData) {
    _themeData = themeData;
    notifyListeners();
  }

  ThemeProvider(bool darkModeEnabled) {
    if (darkModeEnabled) {
      themeData = darkMode;
    } else {
      themeData = lightMode;
    }
  }

  void toggleTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_themeData == lightMode) {
      themeData = darkMode;
      prefs.setBool('darkMode', true);
    } else {
      themeData = lightMode;
      prefs.setBool('darkMode', false);
    }
  }


}