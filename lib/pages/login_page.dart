import 'package:flutter/material.dart';
import '../Services/auth_service.dart';
import 'dashboard_page.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please fill all fields');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService().login(_emailCtrl.text.trim(), _passCtrl.text);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardPage()),
        );
      }
    } catch (e) {
      setState(() => _error = 'Login failed. Check your Username or Password.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEEEF5),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Card
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo inside card
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.school,
                                size: 22, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          const Text('ACADIFY',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF7C4DFF),
                                letterSpacing: 3,
                              )),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text('Start Learning Today 🎓',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D2D2D))),
                      const SizedBox(height: 4),
                      const Text('Sign in to your account',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 20),

                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12)),
                        ),

                      _buildField(
                          _emailCtrl, 'Email', Icons.email_outlined, false),
                      const SizedBox(height: 14),
                      _buildField(
                          _passCtrl, 'Password', Icons.lock_outline, _obscure,
                          suffix: IconButton(
                            icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                                size: 20),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          )),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: _loading ? null : _login,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7C4DFF)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : const Text('Log In',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? ",
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 13)),
                          GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SignupPage())),
                            child: const Text('Sign Up',
                                style: TextStyle(
                                    color: Color(0xFF7C4DFF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                        ],
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

  Widget _buildField(
      TextEditingController ctrl, String label, IconData icon, bool obscure,
      {Widget? suffix}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEF5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType:
            label == 'Email' ? TextInputType.emailAddress : TextInputType.text,
        style: const TextStyle(color: Color(0xFF2D2D2D)),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: const TextStyle(color: Colors.grey),
          prefixIcon: Icon(icon, color: const Color(0xFF7C4DFF), size: 20),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
