// lib/main.dart
import 'package:dairy_manager/screens/inventory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'screens/stock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/setting_screen.dart';

// Global navigator key for navigation from services
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// App configuration
class AppConfig {
  static const String appName = 'Dairy Manager';
  static const String version = '2.0.0';
  static const bool enableAnalytics = true;
  static const bool enableCrashlytics = true;
  static const Duration syncInterval = Duration(minutes: 15);
  static const Duration sessionTimeout = Duration(minutes: 30);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize app
  final appInitializer = AppInitializer();
  await appInitializer.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityService()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
      ],
      child: const DairyApp(),
    ),
  );
}

class AppInitializer {
  Future<void> initialize() async {
    try {
      await _initializeFirebase();
      await _initializeDatabase();
      await _initializeServices();
      await _runDatabaseMigrations();
      await _loadUserPreferences();
      await _setupCrashReporting();

      debugPrint('✅ App initialization complete');
    } catch (e) {
      debugPrint('❌ App initialization failed: $e');
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
    }
  }

  Future<void> _initializeDatabase() async {
    try {
      final db = DatabaseHelper();
      await db.database;
      await db.addStockLimitColumns();
      final stats = await db.getDashboardStats();
      debugPrint('✅ Database initialized with stats: $stats');
    } catch (e) {
      debugPrint('❌ Database initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _initializeServices() async {
    try {
      await NotificationService().initialize();
      debugPrint('✅ Services initialized');
    } catch (e) {
      debugPrint('⚠️ Service initialization failed: $e');
    }
  }

  Future<void> _runDatabaseMigrations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastVersion = prefs.getString('db_version') ?? '0';
      if (lastVersion != AppConfig.version) {
        final db = DatabaseHelper();
        await db.rawQuery('VACUUM');
        await prefs.setString('db_version', AppConfig.version);
        debugPrint('✅ Database migrated from $lastVersion to ${AppConfig.version}');
      }
    } catch (e) {
      debugPrint('⚠️ Migration failed: $e');
    }
  }

  Future<void> _loadUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDarkMode = prefs.getBool('dark_mode') ?? false;
      final themeColor = prefs.getInt('theme_color') ?? Colors.green.value;
      debugPrint('✅ User preferences loaded');
    } catch (e) {
      debugPrint('⚠️ Failed to load preferences: $e');
    }
  }

  Future<void> _setupCrashReporting() async {
    if (AppConfig.enableCrashlytics) {
      FlutterError.onError = (FlutterErrorDetails details) {
        debugPrint('Flutter Error: ${details.exception}');
      };
    }
  }
}

class DairyApp extends StatefulWidget {
  const DairyApp({super.key});

  @override
  State<DairyApp> createState() => _DairyAppState();
}

class _DairyAppState extends State<DairyApp> with WidgetsBindingObserver {
  DateTime? _pausedTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startBackgroundSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _pausedTime = DateTime.now();
        debugPrint('App paused');
        break;
      case AppLifecycleState.resumed:
        _checkSessionTimeout();
        _refreshData();
        debugPrint('App resumed');
        break;
      case AppLifecycleState.detached:
        _saveAppState();
        break;
      default:
        break;
    }
  }

  void _startBackgroundSync() {
    final backgroundSyncService = BackgroundSyncService();
    backgroundSyncService.startBackgroundSync(
      syncInterval: AppConfig.syncInterval,
    );
  }

  void _checkSessionTimeout() {
    if (_pausedTime != null) {
      final difference = DateTime.now().difference(_pausedTime!);
      if (difference > AppConfig.sessionTimeout) {
        FirebaseAuth.instance.signOut();
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/login',
              (route) => false,
        );
      }
    }
  }

  void _refreshData() {
    context.read<AppStateProvider>().refreshData();
  }

  void _saveAppState() {
    context.read<AppStateProvider>().saveState();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: themeProvider.themeMode,
      home: const SplashScreen(),
      onGenerateRoute: _onGenerateRoute,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          child: child!,
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.light,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.grey.shade800),
        titleTextStyle: TextStyle(
          color: Colors.grey.shade900,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
        space: 1,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const SplashScreen());
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
      case '/demand':
        return _createRoute(const DemandScreen());
      case '/demandHistory':
        return _createRoute(const DemandHistoryScreen());
      case '/settings':
        return _createRoute(const SettingsScreen());
      case '/demandDetails':
        final batchId = settings.arguments as int;
        return _createRoute(DemandDetailsScreen(batchId: batchId));
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('Route ${settings.name} not found')),
          ),
        );
    }
  }

  Route _createRoute(Widget page) {
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
}

// SplashScreen and providers remain unchanged...


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  String _loadingMessage = 'Initializing...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    _animationController.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Step 1: Load database
      setState(() {
        _loadingMessage = 'Loading database...';
        _progress = 0.2;
      });

      final db = DatabaseHelper();
      await db.database;

      // Step 2: Load user data
      setState(() {
        _loadingMessage = 'Loading your data...';
        _progress = 0.4;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      // Step 3: Check authentication
      setState(() {
        _loadingMessage = 'Checking authentication...';
        _progress = 0.6;
      });

      final user = FirebaseAuth.instance.currentUser;

      // Step 4: Load preferences
      setState(() {
        _loadingMessage = 'Loading preferences...';
        _progress = 0.8;
      });

      final prefs = await SharedPreferences.getInstance();
      final firstTime = prefs.getBool('first_time') ?? true;

      // Step 5: Navigate
      setState(() {
        _loadingMessage = 'Almost ready...';
        _progress = 1.0;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        if (firstTime) {
          // Show onboarding
          await prefs.setBool('first_time', false);
        }

        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
            user != null ? const HomeScreen() : const LoginScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error during initialization: $e');

      // Show error and continue offline
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Starting in offline mode: ${e.toString()}'),
            backgroundColor: Colors.orange,
          ),
        );

        await Future.delayed(const Duration(seconds: 2));

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
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
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                Text(
                  AppConfig.appName,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage your dairy business smartly',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 200,
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.green.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _loadingMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Providers
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _saveThemePreference();
  }

  Future<void> _saveThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', _themeMode.toString());
  }

  Future<void> loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('theme_mode');
    if (themeModeString != null) {
      _themeMode = ThemeMode.values.firstWhere(
            (mode) => mode.toString() == themeModeString,
        orElse: () => ThemeMode.light,
      );
      notifyListeners();
    }
  }
}

class AppStateProvider extends ChangeNotifier {
  bool _isLoading = false;
  Map<String, dynamic> _appData = {};

  bool get isLoading => _isLoading;
  Map<String, dynamic> get appData => _appData;

  Future<void> refreshData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final db = DatabaseHelper();
      _appData = await db.getDashboardStats();
    } catch (e) {
      debugPrint('Error refreshing data: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_state', DateTime.now().toIso8601String());
  }
}

// Notification Service (create this file separately)
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  Future<void> initialize() async {
    // Initialize local notifications
    debugPrint('✅ Notifications initialized');
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    // Show notification
  }
}