// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ✅ Mutable list so we can reorder
  List<_FeatureTile> features = [
    const _FeatureTile(
      title: 'Purchase Orders',
      icon: Icons.shopping_cart,
      route: '/demand',
      colors: [Colors.green, Colors.greenAccent],
    ),
    const _FeatureTile(
      title: 'Billing Section',
      icon: Icons.receipt_long,
      route: '/billing',
      colors: [Colors.purple, Colors.deepPurpleAccent],
    ),
    const _FeatureTile(
      title: 'Billing History',
      icon: Icons.history,
      route: '/history',
      colors: [Colors.teal, Colors.tealAccent],
    ),
    const _FeatureTile(
      title: 'Ledger Book',
      icon: Icons.book,
      route: '/ledgerBook',
      colors: [Colors.red, Colors.redAccent],
    ),
    const _FeatureTile(
      title: 'Client Management',
      icon: Icons.person,
      route: '/clients',
      colors: [Colors.blue, Colors.blueAccent],
    ),
    const _FeatureTile(
      title: 'Product Management',
      icon: Icons.shopping_cart,
      route: '/products',
      colors: [Colors.orange, Colors.deepOrangeAccent],
    ),
    const _FeatureTile(
      title: 'Stock / Inventory',
      icon: Icons.inventory_2,
      route: '/inventory',
      colors: [Colors.indigo, Colors.indigoAccent],
    ),
    const _FeatureTile(
      title: 'Purchase Order History',
      icon: Icons.history,
      route: '/demandHistory',
      colors: [Colors.brown, Color(0xFF8D6E63)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dairy Manager'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor, // use theme color
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ReorderableGridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              final item = features.removeAt(oldIndex);
              features.insert(newIndex, item);
            });
            // TODO: Persist order using SharedPreferences or local DB if needed.
          },
          children: [
            for (final feature in features)
              _buildTile(feature, key: ValueKey(feature.title)),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(_FeatureTile feature, {required Key key}) {
    return Material(
      key: key,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pushNamed(context, feature.route),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: feature.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: feature.colors.last.withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(3, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(feature.icon, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                feature.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTile {
  final String title;
  final IconData icon;
  final String route;
  final List<Color> colors;

  const _FeatureTile({
    required this.title,
    required this.icon,
    required this.route,
    required this.colors,
  });
}
