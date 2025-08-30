import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    // Phone is collected but not used in the profile table schema. You can add it if needed.
    // final phone = _phoneController.text.trim();
    try {
      // Pass user metadata during sign-up. The Supabase trigger will handle profile creation.
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );
      if (mounted) {
        _showSuccessSnackBar(
            'Success! Please check your email to confirm your account.');
        context.go('/login');
      }
    } on AuthException catch (e) {
      _showErrorSnackBar('Auth Error: ${e.message}');
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
  }

  void _showSuccessSnackBar(String message) {
     if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green,
    ));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
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
                  "https://images.unsplash.com/photo-1528543606781-2f6e6857f318?q=80&w=1965"),
              fit: BoxFit.cover,
            ),
          ),
          child: LayoutBuilder(builder: (context, constraints) {
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
                        color: const Color.fromARGB(255, 255, 255, 255),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 10),
                            Text(
                              "Create Account",
                              style: GoogleFonts.zenDots(
                                color: const Color.fromARGB(255, 0, 0, 0),
                                fontSize: 24,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildLabel("Name"),
                            _buildTextField(
                              _nameController,
                              "Enter your name",
                               validator: (v) => v == null || v.isEmpty ? "Name is required" : null
                            ),
                            const SizedBox(height: 10),
                            _buildLabel("Phone"),
                            _buildTextField(
                              _phoneController,
                              "Enter your phone number",
                            ),
                            const SizedBox(height: 10),
                            _buildLabel("Email"),
                            _buildTextField(
                              _emailController,
                              "Enter your email",
                              validator: (value) =>
                                  value == null || !value.contains('@')
                                      ? "Enter valid email"
                                      : null,
                            ),
                            const SizedBox(height: 10),
                            _buildLabel("Password"),
                            _buildTextField(
                              _passwordController,
                              "Enter your password",
                              obscureText: true,
                              validator: (value) =>
                                  value == null || value.length < 6
                                      ? "Min 6 characters"
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            _isLoading
                                ? const CircularProgressIndicator(
                                    color: Color(0xFFBF360C))
                                : ElevatedButton(
                                    onPressed: _signUp,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFBF360C),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                    child: const Text("Sign Up",
                                        style: TextStyle(fontSize: 20)),
                                  ),
                            TextButton(
                              onPressed: () => context.go('/login'),
                              child: const Text(
                                "Already have an account? Login",
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
          }),
        ),
      ),
    );
  }

  Widget _buildLabel(String label) => Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: const TextStyle(color: Colors.black)),
      );

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    bool obscureText = false,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        validator: validator,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
        ),
      );
}