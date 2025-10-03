// Updated main.dart with login route
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Your screens
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const DairyApp());
}

class DairyApp extends StatelessWidget {
  const DairyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dairy Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),

      // Decide initial screen based on FirebaseAuth state
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const HomeScreen(); // user already logged in
          }
          return const LoginScreen(); // user not logged in
        },
      ),

      // Named routes for the rest of the app
      routes: {
        '/login': (context) => const LoginScreen(),  // Add this route
        '/reports': (context) => const ReportsScreen(),
        '/clients': (context) => const ClientScreen(),
        '/products': (context) => const ProductScreen(),
        '/billing': (context) => const BillingScreen(),
        '/history': (context) => const HistoryScreen(),
        '/ledgerBook': (context) => const LedgerBookScreen(),
        '/inventory': (context) => const StockScreen(),
        '/demand': (context) => const DemandScreen(),
        '/demandHistory': (context) => const DemandHistoryScreen(),
        '/demandDetails': (context) {
          final batchId = ModalRoute.of(context)!.settings.arguments as int;
          return DemandDetailsScreen(batchId: batchId);
        },
      },
    );
  }
}