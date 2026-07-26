import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/createaccountpage.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

/// The auth wall: every signed-out user lands here and nothing else in the
/// app is reachable until they sign in or create an account (Volo/Instagram
/// -style hard gate). Deliberately fixed dark branding in BOTH app themes —
/// this screen does not follow `Theme.of(context).brightness`.
///
/// [onGoogle] / [onApple] are wiring seams: Phase C (Google) and Phase D
/// (Apple, iOS-only) replace the placeholder "coming soon" behavior with a
/// real credential sign-in flow. Leaving them nullable keeps this widget
/// trivially testable standalone.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, this.onGoogle, this.onApple});

  final VoidCallback? onGoogle;
  final VoidCallback? onApple;

  static const _bg = Color(0xFF0B0B0B);

  void _placeholder(BuildContext context, String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider sign-in coming in the next build')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const Spacer(flex: 3),
                        Image.asset(
                          'assets/welcome_logo.png',
                          width: 240,
                          height: 240,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'GET IN THE GAME.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Live scores, leagues & tournaments from Infinite Sports',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 15,
                            height: 1.3,
                          ),
                        ),
                        const Spacer(flex: 3),
                        _GoogleButton(
                          onPressed: () => (onGoogle ??
                              () => _placeholder(context, 'Google'))(),
                        ),
                        if (Platform.isIOS) ...[
                          const SizedBox(height: 12),
                          _AppleButton(
                            onPressed: () => (onApple ??
                                () => _placeholder(context, 'Apple'))(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _EmailButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CreateAccountPage()),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                                child: Divider(
                                    color:
                                        Colors.white.withValues(alpha: 0.24))),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('or',
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 13)),
                            ),
                            Expanded(
                                child: Divider(
                                    color:
                                        Colors.white.withValues(alpha: 0.24))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Already have an account? ',
                              style: TextStyle(color: Colors.grey.shade400),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const LoginPage()),
                              ),
                              child: Text(
                                'Log In',
                                style: TextStyle(
                                  color: infiniteSportsGoldColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(flex: 2),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        icon: const Text(
          'G',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF4285F4),
          ),
        ),
        label: const Text(
          'Sign up with Google',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }
}

class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: const BorderSide(color: Colors.white24),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.apple, color: Colors.white),
        label: const Text(
          'Sign up with Apple',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }
}

class _EmailButton extends StatelessWidget {
  const _EmailButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: infiniteSportsGoldColor,
          foregroundColor: const Color(0xFF1A1206),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        child: const Text(
          'Sign up with Email',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}
