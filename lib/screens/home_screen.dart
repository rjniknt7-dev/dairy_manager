// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../services/database_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _statsAnimationController;
  String _syncStatus = '';
  bool _isLoadingStats = true;
  bool _hasError = false;

  // Quick stats data with proper initialization
  Map<String, dynamic> _quickStats = {
    'todayBills': 0,
    'pendingOrders': 0,
    'lowStock': 0,
    'todayRevenue': 0.0,
    'monthRevenue': 0.0,
    'topProduct': 'Loading...',
  };

  // Primary features (most used)
  final List<_FeatureTile> primaryFeatures = [
    _FeatureTile(
      title: 'New Bill',
      subtitle: 'Create invoice',
      icon: Icons.add_shopping_cart,
      route: '/billing',
      color: const Color(0xFF2196F3),
    ),
    _FeatureTile(
      title: 'Purchase Order',
      subtitle: 'Stock orders',
      icon: Icons.inventory_2,
      route: '/demand',
      color: const Color(0xFF4CAF50),
    ),
    _FeatureTile(
      title: 'Ledger Book',
      subtitle: 'Accounts',
      icon: Icons.account_balance_wallet,
      route: '/ledgerBook',
      color: const Color(0xFFFF9800),
    ),
    _FeatureTile(
      title: 'Stock',
      subtitle: 'Inventory',
      icon: Icons.warehouse,
      route: '/inventory',
      color: const Color(0xFF9C27B0),
    ),
  ];

  // Secondary features
  final List<_FeatureTile> secondaryFeatures = [
    _FeatureTile(
      title: 'Billing History',
      subtitle: 'Past invoices',
      icon: Icons.history,
      route: '/history',
      color: const Color(0xFF607D8B),
    ),
    _FeatureTile(
      title: 'Order History',
      subtitle: 'Past orders',
      icon: Icons.receipt_long,
      route: '/demandHistory',
      color: const Color(0xFF795548),
    ),
    _FeatureTile(
      title: 'Reports',
      subtitle: 'Analytics',
      icon: Icons.analytics,
      route: '/reports',
      color: const Color(0xFF00BCD4),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _statsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _initializeHomeScreen();
  }

  Future<void> _initializeHomeScreen() async {
    await _loadQuickStats();
    _animationController.forward();
    _statsAnimationController.forward();
    await _checkSyncStatus();
  }

  Future<void> _loadQuickStats() async {
    try {
      setState(() {
        _isLoadingStats = true;
        _hasError = false;
      });

      final db = DatabaseHelper();
      final stats = await db.getQuickInsights();

      if (mounted) {
        setState(() {
          _quickStats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      print('Error loading stats: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoadingStats = false;
          _quickStats = {
            'todayBills': 0,
            'pendingOrders': 0,
            'lowStock': 0,
            'todayRevenue': 0.0,
            'monthRevenue': 0.0,
            'topProduct': 'Error loading',
          };
        });
      }
    }
  }

  Future<void> _checkSyncStatus() async {
    final connectivity = context.read<ConnectivityService>();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null && connectivity.isOnline) {
      setState(() => _syncStatus = 'Synced');
    } else if (user == null) {
      setState(() => _syncStatus = 'Local Mode');
    } else {
      setState(() => _syncStatus = 'Offline');
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        setState(() => _syncStatus = 'Local Mode');
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _statsAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();
    final isOnline = connectivity.isOnline;
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(isLoggedIn, user, isOnline),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildQuickInsights(),
                const SizedBox(height: 24),
                _buildQuickActions(),
                const SizedBox(height: 24),
                _buildPrimaryFeatures(),
                const SizedBox(height: 24),
                _buildSecondaryFeatures(),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(context),
    );
  }

  Widget _buildSliverAppBar(bool isLoggedIn, User? user, bool isOnline) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      snap: true,
      backgroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Dairy Manager',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Sync indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isOnline
                                    ? Colors.green.shade200
                                    : Colors.orange.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isOnline ? Icons.cloud_done : Icons.cloud_off,
                                  size: 14,
                                  color: isOnline
                                      ? Colors.green.shade700
                                      : Colors.orange.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _syncStatus,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isOnline
                                        ? Colors.green.shade700
                                        : Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Settings button
                          IconButton(
                            onPressed: () => Navigator.pushNamed(context, '/settings'),
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.settings_outlined,
                                size: 20,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickInsights() {
    return FadeTransition(
      opacity: _statsAnimationController,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF6366F1),
              const Color(0xFF8B5CF6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Today\'s Overview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_hasError)
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                    onPressed: _loadQuickStats,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                else
                  Text(
                    _getCurrentDate(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _isLoadingStats
                ? _buildLoadingStats()
                : _hasError
                ? _buildErrorState()
                : _buildStatsGrid(),
            const SizedBox(height: 16),
            _buildTopProduct(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingStats() {
    return SizedBox(
      height: 80,
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.7)),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Column(
      children: [
        Icon(
          Icons.error_outline,
          color: Colors.white.withOpacity(0.7),
          size: 40,
        ),
        const SizedBox(height: 8),
        Text(
          'Failed to load stats',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loadQuickStats,
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.2),
          ),
          child: const Text(
            'Retry',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildStatItem(
          'Revenue',
          '₹${_quickStats['todayRevenue'].toStringAsFixed(0)}',
          Icons.trending_up,
          Colors.green,
        ),
        _buildStatItem(
          'Bills',
          '${_quickStats['todayBills']}',
          Icons.receipt,
          Colors.blue,
        ),
        _buildStatItem(
          'Pending',
          '${_quickStats['pendingOrders']}',
          Icons.pending_actions,
          Colors.orange,
        ),
        _buildStatItem(
          'Low Stock',
          '${_quickStats['lowStock']}',
          Icons.warning,
          Colors.red,
        ),
      ],
    );
  }

  Widget _buildTopProduct() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline,
            color: Colors.yellow.shade300,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Top selling: ${_quickStats['topProduct']}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildQuickActionChip(
                'New Bill',
                Icons.add_circle_outline,
                Colors.blue,
                    () => Navigator.pushNamed(context, '/billing'),
              ),
              const SizedBox(width: 12),
              _buildQuickActionChip(
                'Add Stock',
                Icons.add_box_outlined,
                Colors.green,
                    () => Navigator.pushNamed(context, '/inventory'),
              ),
              const SizedBox(width: 12),
              _buildQuickActionChip(
                'View Reports',
                Icons.bar_chart,
                Colors.purple,
                    () => Navigator.pushNamed(context, '/reports'),
              ),
              const SizedBox(width: 12),
              _buildQuickActionChip(
                'Pending Orders',
                Icons.access_time,
                Colors.orange,
                    () => Navigator.pushNamed(context, '/demand'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionChip(
      String label,
      IconData icon,
      Color color,
      VoidCallback onTap,
      ) {
    Color textColor = Colors.black;
    if (color is MaterialColor) {
      textColor = color.shade700;
    } else {
      final hsl = HSLColor.fromColor(color);
      textColor = hsl.withLightness((hsl.lightness - 0.3).clamp(0.0, 1.0)).toColor();
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryFeatures() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Main Features',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemCount: primaryFeatures.length,
          itemBuilder: (context, index) {
            final feature = primaryFeatures[index];
            return _buildModernTile(feature, index);
          },
        ),
      ],
    );
  }

  Widget _buildSecondaryFeatures() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'More',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: secondaryFeatures.map((feature) {
            return _buildListTile(feature);
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildModernTile(_FeatureTile feature, int index) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(0, 0.1 * (index + 1)),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      )),
      child: FadeTransition(
        opacity: _animationController,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, feature.route),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.grey.shade200,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: feature.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    feature.icon,
                    color: feature.color,
                    size: 24,
                  ),
                ),
                const Spacer(),
                Text(
                  feature.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  feature.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListTile(_FeatureTile feature) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.pushNamed(context, feature.route),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: feature.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            feature.icon,
            color: feature.color,
            size: 20,
          ),
        ),
        title: Text(
          feature.title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          feature.subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: Colors.grey.shade400,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        tileColor: Colors.white,
      ),
    );
  }

  Widget _buildFAB(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _showQuickMenu(context),
      backgroundColor: const Color(0xFF6366F1),
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  void _showQuickMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Add',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.receipt, color: Colors.blue),
              title: const Text('New Bill'),
              subtitle: const Text('Create a new invoice'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/billing');
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart, color: Colors.green),
              title: const Text('Purchase Order'),
              subtitle: const Text('Create stock order'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/demand');
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add, color: Colors.orange),
              title: const Text('Add Client'),
              subtitle: const Text('Register new client'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/clients');
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2, color: Colors.purple),
              title: const Text('Add Product'),
              subtitle: const Text('Add new product'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/products');
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getCurrentDate() {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${now.day} ${months[now.month - 1]}, ${now.year}';
  }
}

class _FeatureTile {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final Color color;

  const _FeatureTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.color,
  });
}