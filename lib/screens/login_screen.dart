import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_sync_service.dart';
import 'home_screen.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mobileFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  final _auth = FirebaseAuth.instance;
  final _syncService = FirebaseSyncService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _loading = false;
  bool _isLogin = true;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _error;
  String _syncStatus = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOutBack),
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _mobileFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  String _mobileToEmail(String mobile) => '${mobile.trim()}@dairymanager.com';

  String? _validateMobile(String? value) {
    if (value?.trim().isEmpty ?? true) {
      return 'Mobile number is required';
    }
    if (value!.trim().length < 10) {
      return 'Enter valid mobile number';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value?.isEmpty ?? true) {
      return 'Password is required';
    }
    if (value!.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      _loading = true;
      _error = null;
      _syncStatus = _isLogin ? 'Signing in...' : 'Creating account...';
    });

    try {
      if (_isLogin) {
        await _auth.signInWithEmailAndPassword(
          email: _mobileToEmail(_mobileController.text),
          password: _passwordController.text.trim(),
        );
      } else {
        await _auth.createUserWithEmailAndPassword(
          email: _mobileToEmail(_mobileController.text),
          password: _passwordController.text.trim(),
        );
      }

      if (!mounted) return;

      setState(() => _syncStatus = 'Syncing your data...');
      final syncResult = await _syncService.syncAllData();

      if (!mounted) return;

      if (!syncResult.success && _isLogin) {
        _showSnackBar(
          'Login successful but sync failed: ${syncResult.message}',
          Colors.orange,
        );
      }

      HapticFeedback.lightImpact()  ;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );

    } on FirebaseAuthException catch (e) {
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() => _error = _getErrorMessage(e));
      }
    } catch (e) {
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _syncStatus = '';
        });
      }
    }
  }

  String _getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this mobile number';
      case 'wrong-password':
        return 'Incorrect password';
      case 'email-already-in-use':
        return 'Account already exists with this mobile number';
      case 'weak-password':
        return 'Password is too weak';
      case 'network-request-failed':
        return 'Network error. Check your connection';
      default:
        return e.message ?? (_isLogin ? 'Login failed' : 'Registration failed');
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _toggleMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _isLogin = !_isLogin;
      _error = null;
    });
  }

  void _continueOffline() {
    HapticFeedback.lightImpact();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: _buildContent(context, theme, colorScheme, size),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme, ColorScheme colorScheme, Size size) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(theme, colorScheme),
                const SizedBox(height: 40),
                _buildFormFields(colorScheme),
                const SizedBox(height: 24),
                _buildStatusMessages(),
                const SizedBox(height: 32),
                _buildActionButtons(colorScheme),
                const SizedBox(height: 24),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Hero(
      tag: 'app_logo',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.primary.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              blurRadius: 20,
              color: colorScheme.primary.withOpacity(0.3),
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Logo container
            Container(
              width: 100,
              height: 100,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    color: Colors.black.withOpacity(0.1),
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _buildLogo(),
            ),
            const SizedBox(height: 16),
            Text(
              "Dairy Manager",
              style: theme.textTheme.headlineMedium!.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Sync & manage effortlessly",
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colorScheme.onPrimary.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    // Try to load custom logo, fallback to icon if not found
    return Image.asset(
      'assets/images/logo_white.png', // Use white version on colored background
      width: 80,
      height: 80,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        // Fallback to default icon if logo not found
        return Icon(
          Icons.agriculture,
          size: 64,
          color: Colors.white,
        );
      },
    );
  }

  Widget _buildFormFields(ColorScheme colorScheme) {
    return Column(
      children: [
        TextFormField(
          controller: _mobileController,
          focusNode: _mobileFocusNode,
          validator: _validateMobile,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
          decoration: InputDecoration(
            labelText: "Mobile Number",
            hintText: "Enter your mobile number",
            prefixIcon: const Icon(Icons.phone_android),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.error),
            ),
            filled: true,
            fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          validator: _validatePassword,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submitForm(),
          decoration: InputDecoration(
            labelText: "Password",
            hintText: "Enter your password",
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _obscurePassword = !_obscurePassword);
              },
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.error),
            ),
            filled: true,
            fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
          ),
        ),
        if (_isLogin) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  setState(() => _rememberMe = value ?? false);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              const Text("Remember me"),
              const Spacer(),
              TextButton(
                onPressed: () {
                  // Implement forgot password
                  _showSnackBar('Feature coming soon!', colorScheme.primary);
                },
                child: const Text("Forgot Password?"),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStatusMessages() {
    return Column(
      children: [
        if (_error != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
            ),
          ),
        if (_syncStatus.isNotEmpty) ...[
          if (_error != null) const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _syncStatus,
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(ColorScheme colorScheme) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _loading
              ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: const Center(child: CircularProgressIndicator()),
          )
              : SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
              ),
              onPressed: _submitForm,
              child: Text(
                _isLogin ? "Login" : "Create Account",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isLogin ? "Don't have an account? " : "Already have an account? ",
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
            ),
            TextButton(
              onPressed: _toggleMode,
              child: Text(
                _isLogin ? "Sign Up" : "Login",
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          height: 1,
          color: colorScheme.outline.withOpacity(0.2),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: _continueOffline,
          icon: const Icon(Icons.offline_bolt_outlined),
          label: const Text("Continue Offline"),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurface.withOpacity(0.7),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Text(
      "© 2024 Dairy Manager. All rights reserved.",
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        fontSize: 12,
      ),
      textAlign: TextAlign.center,
    );
  }
}