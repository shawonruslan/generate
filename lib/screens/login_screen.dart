import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Login screen — matches the web app: Member/Admin segmented control
/// (light-gray track, white active pill), username + password fields,
/// "Keep me signed in", royal-blue Sign in button, and a proper padded
/// circle day/night toggle top-right. The worker URL is fixed to the
/// default (changeable in Settings); login never asks for it.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isAdmin = false;
  bool _persist = true;
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = context.read<SessionProvider>();
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (!_isAdmin && username.isEmpty) {
      showMsg(context, 'Enter your username.', error: true);
      return;
    }
    if (password.isEmpty) {
      showMsg(context, 'Enter your password.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await session.login(
        role: _isAdmin ? 'admin' : 'member',
        username: _isAdmin ? null : username,
        password: password,
        persist: _persist,
      );
      if (mounted) showMsg(context, 'Welcome back, ${session.user!.username}!');
    } on UnauthorizedException {
      if (mounted) showMsg(context, 'Wrong username or password.', error: true);
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (e) {
      if (mounted) {
        showMsg(context, 'Could not reach the server. Check your connection.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final night = theme.night;
    final isWide = MediaQuery.of(context).size.width > 900;
    final brand = night ? AppColors.brandDark : AppColors.brandLight;

    return Scaffold(
      backgroundColor: night ? AppColors.nightBg : const Color(0xFFECEAE2),
      body: SafeArea(
        child: Row(
          children: [
            if (isWide) _buildBrandPanel(night),
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: _buildForm(night, brand),
                      ),
                    ),
                  ),
                  // Padded circle day/night toggle — not a naked floating icon.
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Material(
                      color: night ? AppColors.nightSide2 : Colors.white,
                      shape: const CircleBorder(),
                      elevation: 1,
                      child: IconButton(
                        tooltip: night ? 'Day mode' : 'Night mode',
                        icon: Icon(
                          night
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          color: night
                              ? AppColors.nightText
                              : AppColors.dayText,
                        ),
                        onPressed: () => theme.toggle(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dark hero panel on wide screens (web's #auth hero is always dark).
  Widget _buildBrandPanel(bool night) {
    return Container(
      width: 380,
      color: const Color(0xFF1B1B1E),
      padding: const EdgeInsets.all(56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.cloud_outlined,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 24),
          const Text('Team Drive',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text("Your team's files, one secure place.",
              style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 32),
          _brandPoint(Icons.bolt_outlined, 'Fast downloads with resume support'),
          _brandPoint(
              Icons.lock_outline, 'Private accounts & signed download links'),
          _brandPoint(Icons.cloud_done_outlined, 'Powered by Cloudflare R2'),
        ],
      ),
    );
  }

  Widget _brandPoint(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: Colors.white70, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 14))),
        ]),
      );

  Widget _buildForm(bool night, Color brand) {
    const dayText = Color(0xFF222222);
    const dayMuted = Color(0xFF888888);
    final textColor = night ? AppColors.nightText : dayText;
    final muted = night ? AppColors.nightMuted : dayMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Welcome back',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: textColor)),
        const SizedBox(height: 6),
        Text("Sign in to access your team's files",
            style: TextStyle(fontSize: 14, color: muted)),
        const SizedBox(height: 24),
        _segmented(night, brand, textColor, muted),
        const SizedBox(height: 16),
        if (!_isAdmin) ...[
          _field(
            night: night,
            brand: brand,
            controller: _userCtrl,
            hint: 'e.g. rahim',
            prefix: Icons.person_outline,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
        ],
        _field(
          night: night,
          brand: brand,
          controller: _passCtrl,
          hint: 'Password',
          prefix: Icons.lock_outline,
          obscure: _obscure,
          suffix: IconButton(
            icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: muted,
                size: 20),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _persist,
                activeColor: brand,
                onChanged: (v) => setState(() => _persist = v ?? true),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _persist = !_persist),
              child: Text('Keep me signed in',
                  style: TextStyle(fontSize: 13.5, color: textColor)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Sign in',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  /// Member/Admin segmented control: light-gray track, white active pill.
  Widget _segmented(bool night, Color brand, Color textColor, Color muted) {
    return Container(
      decoration: BoxDecoration(
        color: night ? AppColors.nightSide2 : const Color(0xFFE9E7E0),
        borderRadius: BorderRadius.circular(11),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(children: [
        _segTab(night, textColor, muted, 'Member', Icons.person_outline,
            !_isAdmin, () => setState(() => _isAdmin = false)),
        _segTab(night, textColor, muted, 'Admin',
            Icons.manage_accounts_outlined, _isAdmin, () => setState(() => _isAdmin = true)),
      ]),
    );
  }

  Widget _segTab(bool night, Color textColor, Color muted, String label,
      IconData icon, bool active, VoidCallback onTap) {
    final fg = active ? textColor : muted;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? (night ? AppColors.nightPanel : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 3,
                        offset: const Offset(0, 1))
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required bool night,
    required Color brand,
    required TextEditingController controller,
    required String hint,
    required IconData prefix,
    bool obscure = false,
    Widget? suffix,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
  }) {
    final muted = night ? AppColors.nightMuted : const Color(0xFF888888);
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    return TextField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: TextStyle(
          color: night ? AppColors.nightText : const Color(0xFF222222)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: muted),
        prefixIcon: Icon(prefix, color: muted, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: night ? AppColors.nightPanel : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: brand, width: 1.6),
        ),
      ),
    );
  }
}
