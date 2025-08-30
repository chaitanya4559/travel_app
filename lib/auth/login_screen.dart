import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user == null) {
        setState(() => _error = "Login failed: Invalid credentials.");
      }
      // ✅ No navigation here → GoRouter redirect handles it
    } on AuthException catch (e) {
      setState(() => _error = "Auth Error: ${e.message}");
    } catch (e) {
      setState(() => _error = "Unexpected Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.flutter://login-callback/',
      );
      // ✅ After Google login, Supabase updates session → GoRouter redirects
    } on AuthException catch (e) {
      setState(() => _error = 'Auth Error: ${e.message}');
    } catch (e) {
      setState(() => _error = 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: NetworkImage(
                "https://images.unsplash.com/photo-1528543606781-2f6e6857f318?q=80&w=1965",
              ),
              fit: BoxFit.cover,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                reverse: true,
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(25.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Welcome back,",
                                style: GoogleFonts.zenDots(
                                  color: Colors.black,
                                  fontSize: 24,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Email field
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text("Email",
                                    style: TextStyle(color: Colors.black)),
                              ),
                              _buildTextField(
                                _emailController,
                                "Enter your email",
                                validator: (v) => v == null || !v.contains('@')
                                    ? "Enter valid email"
                                    : null,
                              ),
                              const SizedBox(height: 20),

                              // Password field
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text("Password",
                                    style: TextStyle(color: Colors.black)),
                              ),
                              _buildTextField(
                                _passwordController,
                                "Enter your password",
                                obscureText: true,
                                validator: (v) => v == null || v.length < 6
                                    ? "Min 6 characters"
                                    : null,
                              ),
                              const SizedBox(height: 12),

                              // Error message
                              if (_error != null)
                                Text(
                                  _error!,
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),

                              const SizedBox(height: 12),

                              // Buttons
                              _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Color(0xFFBF360C),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ElevatedButton(
                                          onPressed: _loginUser,
                                          style: _buttonStyle(),
                                          child: const Text(
                                            "Login",
                                            style: TextStyle(fontSize: 20),
                                          ),
                                        ),
                                        const SizedBox(height: 10),

                                        // Google Sign-In (only for mobile)
                                        if (!kIsWeb &&
                                            (Platform.isAndroid ||
                                                Platform.isIOS))
                                          ElevatedButton.icon(
                                            onPressed: _googleSignIn,
                                            icon: Image.asset(
                                              'assets/google.png',
                                              height: 24,
                                            ),
                                            label: const Text(
                                                'Sign in with Google'),
                                            style: ElevatedButton.styleFrom(
                                              foregroundColor: Colors.black,
                                              backgroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                side: const BorderSide(
                                                    color: Colors.grey),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),

                              TextButton(
                                onPressed: () => context.go('/signup'),
                                child: const Text(
                                  "Don't have an account? Sign Up",
                                  style: TextStyle(color: Color(0xFFBF360C)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.black),
      decoration: _inputDecoration(hint),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
      );

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFBF360C),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      );
}

// ✅ No HomeScreen here – it already exists in your `ui/screens/home_screen.dart`
