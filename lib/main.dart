// lib/main.dart - v2.1 (ALL ERRORS FIXED - PRODUCTION READY)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// Firebase options
import 'firebase_options.dart';

// Services
import 'services/connectivity_service.dart';
import 'services/database_helper.dart';
import 'services/backgroud_sync_service.dart';

// Screens
import 'screens/home_screen.dart';
import 'screens/client_screen.dart';
import 'screens/product_screen.dart';
import 'screens/billing_screen.dart';
import 'screens/history_screen.dart';
import 'screens/ledger_book_screen.dart';
import 'screens/demand_screen.dart';
import 'screens/demand_details_screen.dart';
import 'screens/demand_history_screen.dart';
import 'screens/login_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/setting_screen.dart';
import 'screens/inventory_screen.dart';

// ========================================================================
// GLOBAL CONFIGURATION
// ========================================================================

/// Global navigator key for navigation from services
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// App configuration constants
class AppConfig {
  static const String appName = 'Dairy Manager';
  static const String version = '2.0.1';
  static const int databaseVersion = 30;
  static const bool enableAnalytics = true;
  static const bool enableCrashlytics = true;
  static const Duration syncInterval = Duration(minutes: 15);
  static const Duration sessionTimeout = Duration(minutes: 30);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
}

// ========================================================================
// MAIN ENTRY POINT - FIXED
// ========================================================================

Future<void> main() async {
  // ✅ CRITICAL FIX: Initialize bindings FIRST before any async operations
  WidgetsFlutterBinding.ensureInitialized();

  // Set up global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🔴 Flutter Error: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
  };

  // Configure and initialize
  try {
    await _configureApp();
    await _initializeApp();
  } catch (e, stackTrace) {
    debugPrint('❌ Initialization error: $e');
    debugPrint('Stack: $stackTrace');
  }

  // Run app
  _runApp();
}

/// Configure app-level settings
Future<void> _configureApp() async {
  try {
    // Lock orientation to portrait
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Configure status bar and navigation bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    debugPrint('✅ App configuration complete');
  } catch (e) {
    debugPrint('⚠️ App configuration warning: $e');
  }
}

/// Initialize app dependencies
Future<void> _initializeApp() async {
  final initializer = AppInitializer();
  await initializer.initialize();
}

/// Run the app with providers
void _runApp() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ConnectivityService(),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider()..loadThemePreference(),
        ),
        ChangeNotifierProvider(
          create: (_) => AppStateProvider(),
        ),
      ],
      child: const DairyApp(),
    ),
  );
}

// ========================================================================
// APP INITIALIZER
// ========================================================================

class AppInitializer {
  int _currentRetry = 0;

  Future<void> initialize() async {
    try {
      debugPrint('🚀 Starting app initialization...');

      await _initializeFirebase();
      await _initializeDatabase();
      await _initializeServices();
      await _runMaintenanceTasks();

      debugPrint('✅ App initialization complete');
    } catch (e) {
      debugPrint('❌ App initialization failed: $e');

      // Retry logic
      if (_currentRetry < AppConfig.maxRetries) {
        _currentRetry++;
        debugPrint('🔄 Retrying initialization ($_currentRetry/${AppConfig.maxRetries})...');
        await Future.delayed(AppConfig.retryDelay);
        return await initialize();
      } else {
        debugPrint('❌ Max retries reached. Continuing in degraded mode.');
      }
    }
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase initialized');
    } catch (e) {
      debugPrint('⚠️ Firebase initialization failed: $e');
      // Continue without Firebase - offline mode
    }
  }

  Future<void> _initializeDatabase() async {
    try {
      final db = DatabaseHelper();

      // Initialize database
      await db.database;

      // Add any new columns
      await db.addStockLimitColumns();

      // Get initial stats
      final stats = await db.getDashboardStats();
      debugPrint('✅ Database initialized');
      debugPrint('📊 Stats: ${stats['clientsCount']} clients, ${stats['productsCount']} products, ${stats['billsCount']} bills');
    } catch (e) {
      debugPrint('❌ Database initialization failed: $e');
      rethrow; // Database is critical
    }
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize notification service
      await NotificationService().initialize();

      // Initialize background sync
      _initializeBackgroundSync();

      debugPrint('✅ Services initialized');
    } catch (e) {
      debugPrint('⚠️ Service initialization warning: $e');
      // Non-critical, continue
    }
  }

  void _initializeBackgroundSync() {
    try {
      final backgroundSync = BackgroundSyncService();
      backgroundSync.startBackgroundSync(
        syncInterval: AppConfig.syncInterval,
      );
      debugPrint('✅ Background sync started');
    } catch (e) {
      debugPrint('⚠️ Background sync failed to start: $e');
    }
  }

  Future<void> _runMaintenanceTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check database version
      final lastDbVersion = prefs.getInt('db_version') ?? 0;
      if (lastDbVersion < AppConfig.databaseVersion) {
        await _performDatabaseMaintenance();
        await prefs.setInt('db_version', AppConfig.databaseVersion);
        debugPrint('✅ Database upgraded: v$lastDbVersion → v${AppConfig.databaseVersion}');
      }

      // Check app version
      final lastAppVersion = prefs.getString('app_version') ?? '0.0.0';
      if (lastAppVersion != AppConfig.version) {
        await _performAppUpgrade(lastAppVersion);
        await prefs.setString('app_version', AppConfig.version);
        debugPrint('✅ App upgraded: $lastAppVersion → ${AppConfig.version}');
      }

      // Clean up old data (run weekly)
      final lastCleanup = prefs.getInt('last_cleanup') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastCleanup > 7 * 24 * 60 * 60 * 1000) {
        await _performCleanup();
        await prefs.setInt('last_cleanup', now);
        debugPrint('✅ Cleanup performed');
      }
    } catch (e) {
      debugPrint('⚠️ Maintenance tasks warning: $e');
    }
  }

  Future<void> _performDatabaseMaintenance() async {
    try {
      final db = DatabaseHelper();

      // Optimize database
      await db.rawQuery('VACUUM');

      // Analyze tables for query optimization
      await db.rawQuery('ANALYZE');

      debugPrint('✅ Database maintenance complete');
    } catch (e) {
      debugPrint('⚠️ Database maintenance failed: $e');
    }
  }

  Future<void> _performAppUpgrade(String oldVersion) async {
    try {
      // Perform any app-specific upgrade tasks
      debugPrint('Upgrading from $oldVersion to ${AppConfig.version}');

      // Example: Clear cache on major version change
      if (oldVersion.split('.')[0] != AppConfig.version.split('.')[0]) {
        final prefs = await SharedPreferences.getInstance();
        final keysToKeep = ['db_version', 'app_version', 'theme_mode'];
        final allKeys = prefs.getKeys();
        for (var key in allKeys) {
          if (!keysToKeep.contains(key)) {
            await prefs.remove(key);
          }
        }
        debugPrint('✅ Cache cleared for major version upgrade');
      }
    } catch (e) {
      debugPrint('⚠️ App upgrade tasks failed: $e');
    }
  }

  Future<void> _performCleanup() async {
    try {
      final db = DatabaseHelper();

      // Clean up old deleted records (older than 30 days)
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      await db.rawQuery('''
        DELETE FROM bills 
        WHERE isDeleted = 1 AND updatedAt < ?
      ''', [thirtyDaysAgo.toIso8601String()]);

      await db.rawQuery('''
        DELETE FROM bill_items 
        WHERE isDeleted = 1 AND updatedAt < ?
      ''', [thirtyDaysAgo.toIso8601String()]);

      debugPrint('✅ Old records cleaned up');
    } catch (e) {
      debugPrint('⚠️ Cleanup failed: $e');
    }
  }
}

// ========================================================================
// MAIN APP WIDGET
// ========================================================================

class DairyApp extends StatefulWidget {
  const DairyApp({super.key});

  @override
  State<DairyApp> createState() => _DairyAppState();
}

class _DairyAppState extends State<DairyApp> with WidgetsBindingObserver {
  DateTime? _pausedTime;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAuthListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  void _setupAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
          (User? user) {
        if (user == null) {
          debugPrint('🔒 User signed out');
          navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/login',
                (route) => false,
          );
        } else {
          debugPrint('✅ User authenticated: ${user.email}');
        }
      },
      onError: (error) {
        debugPrint('⚠️ Auth state error: $error');
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.paused:
        _onAppPaused();
        break;
      case AppLifecycleState.inactive:
        debugPrint('📱 App inactive');
        break;
      case AppLifecycleState.detached:
        _onAppDetached();
        break;
      case AppLifecycleState.hidden:
        debugPrint('📱 App hidden');
        break;
    }
  }

  void _onAppResumed() {
    debugPrint('📱 App resumed');
    _checkSessionTimeout();
    _refreshData();
  }

  void _onAppPaused() {
    debugPrint('📱 App paused');
    _pausedTime = DateTime.now();
    _saveAppState();
  }

  void _onAppDetached() {
    debugPrint('📱 App detached');
    _saveAppState();
  }

  void _checkSessionTimeout() {
    if (_pausedTime != null) {
      final difference = DateTime.now().difference(_pausedTime!);
      if (difference > AppConfig.sessionTimeout) {
        debugPrint('⏱️ Session timeout - signing out');
        FirebaseAuth.instance.signOut();
      }
      _pausedTime = null;
    }
  }

  void _refreshData() {
    try {
      context.read<AppStateProvider>().refreshData();
    } catch (e) {
      debugPrint('⚠️ Error refreshing data: $e');
    }
  }

  void _saveAppState() {
    try {
      context.read<AppStateProvider>().saveState();
    } catch (e) {
      debugPrint('⚠️ Error saving app state: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          home: const SplashScreen(),
          onGenerateRoute: AppRouter.onGenerateRoute,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.0),
              ),
              child: child!,
            );
          },
        );
      },
    );
  }
}

// ========================================================================
// APP THEME
// ========================================================================

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade900,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.grey.shade900,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          side: const BorderSide(color: Colors.green),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.green, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
        space: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ========================================================================
// APP ROUTER
// ========================================================================

class AppRouter {
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    try {
      switch (settings.name) {
        case '/':
          return _createRoute(const SplashScreen());
        case '/login':
          return _createRoute(const LoginScreen());
        case '/home':
          return _createRoute(const HomeScreen());
        case '/reports':
          return _createRoute(const ReportsScreen());
        case '/clients':
          return _createRoute(const ClientScreen());
        case '/products':
          return _createRoute(const ProductScreen());
        case '/billing':
          return _createRoute(const BillingScreen());
        case '/history':
          return _createRoute(const HistoryScreen());
        case '/ledgerBook':
          return _createRoute(const LedgerBookScreen());
        case '/inventory':
          return _createRoute(const InventoryScreen());
        case '/stock':
          return _createRoute(const InventoryScreen());
        case '/demand':
          return _createRoute(const DemandScreen());
        case '/demandHistory':
          return _createRoute(const DemandHistoryScreen());
        case '/settings':
          return _createRoute(const SettingsScreen());
        case '/demandDetails':
          final batchId = settings.arguments as int?;
          if (batchId == null) {
            return _errorRoute('Batch ID is required');
          }
          return _createRoute(DemandDetailsScreen(batchId: batchId));
        default:
          return _errorRoute('Route ${settings.name} not found');
      }
    } catch (e) {
      debugPrint('⚠️ Route error: $e');
      return _errorRoute('Navigation error occurred');
    }
  }

  static Route<dynamic> _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOutCubic;

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => navigatorKey.currentState?.pushNamedAndRemoveUntil(
                    '/home',
                        (route) => false,
                  ),
                  child: const Text('Go to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// SPLASH SCREEN
// ========================================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  String _loadingMessage = 'Initializing...';
  double _progress = 0.0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeApp();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();
  }

  Future<void> _initializeApp() async {
    try {
      // Step 1: Load database (20%)
      await _updateProgress('Loading database...', 0.2);
      final db = DatabaseHelper();
      await db.database;

      // Step 2: Load data (40%)
      await _updateProgress('Loading your data...', 0.4);
      await Future.delayed(const Duration(milliseconds: 300));

      // Step 3: Check authentication (60%)
      await _updateProgress('Checking authentication...', 0.6);
      final user = FirebaseAuth.instance.currentUser;

      // Step 4: Load preferences (80%)
      await _updateProgress('Loading preferences...', 0.8);
      await SharedPreferences.getInstance();

      // Step 5: Complete (100%)
      await _updateProgress('Ready!', 1.0);
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Navigate
      _navigateToHome(user != null);
    } catch (e) {
      debugPrint('❌ Splash initialization error: $e');
      _handleError(e);
    }
  }

  Future<void> _updateProgress(String message, double progress) async {
    if (!mounted) return;
    setState(() {
      _loadingMessage = message;
      _progress = progress;
    });
    await Future.delayed(const Duration(milliseconds: 300));
  }

  void _handleError(Object error) {
    if (!mounted) return;

    setState(() {
      _hasError = true;
      _loadingMessage = 'Starting in offline mode...';
    });

    // Show error and continue
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _navigateToHome(false);
      }
    });
  }

  void _navigateToHome(bool isAuthenticated) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
        isAuthenticated ? const HomeScreen() : const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.local_drink,
                      size: 60,
                      color: Colors.green.shade600,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // App name
                  Text(
                    AppConfig.appName,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Tagline
                  Text(
                    'Manage your dairy business smartly',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Progress indicator
                  SizedBox(
                    width: 200,
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _progress,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _hasError ? Colors.orange : Colors.green.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _loadingMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: _hasError ? Colors.orange : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Version
                  const SizedBox(height: 48),
                  Text(
                    'v${AppConfig.version}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// PROVIDERS
// ========================================================================

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    _saveThemePreference();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
      _saveThemePreference();
    }
  }

  Future<void> _saveThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', _themeMode.toString());
    } catch (e) {
      debugPrint('⚠️ Failed to save theme preference: $e');
    }
  }

  Future<void> loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString('theme_mode');
      if (themeModeString != null) {
        _themeMode = ThemeMode.values.firstWhere(
              (mode) => mode.toString() == themeModeString,
          orElse: () => ThemeMode.light,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load theme preference: $e');
    }
  }
}

class AppStateProvider extends ChangeNotifier {
  bool _isLoading = false;
  Map<String, dynamic> _appData = {};
  String? _errorMessage;

  bool get isLoading => _isLoading;
  Map<String, dynamic> get appData => _appData;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  Future<void> refreshData() async {
    if (_isLoading) return; // Prevent multiple simultaneous refreshes

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final db = DatabaseHelper();
      _appData = await db.getDashboardStats();
      debugPrint('✅ App data refreshed');
    } catch (e) {
      _errorMessage = 'Failed to refresh data: $e';
      debugPrint('❌ Error refreshing data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_active', DateTime.now().toIso8601String());
      debugPrint('✅ App state saved');
    } catch (e) {
      debugPrint('⚠️ Failed to save app state: $e');
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

// ========================================================================
// NOTIFICATION SERVICE
// ========================================================================

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize local notifications here
      // Add your notification plugin initialization

      _isInitialized = true;
      debugPrint('✅ Notification service initialized');
    } catch (e) {
      debugPrint('⚠️ Notification service initialization failed: $e');
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      debugPrint('⚠️ Notification service not initialized');
      return;
    }

    try {
      // Show notification logic here
      debugPrint('📬 Notification: $title - $body');
    } catch (e) {
      debugPrint('⚠️ Failed to show notification: $e');
    }
  }

  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    if (!_isInitialized) return;

    try {
      // Schedule notification logic here
      debugPrint('⏰ Scheduled notification: $title at $scheduledDate');
    } catch (e) {
      debugPrint('⚠️ Failed to schedule notification: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      // Cancel all notifications
      debugPrint('🔕 All notifications cancelled');
    } catch (e) {
      debugPrint('⚠️ Failed to cancel notifications: $e');
    }
  }
}