import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/config.dart';
import '../widgets/app_widgets.dart';

/// Login screen — mirrors the web app: Member / Admin tabs, username +
/// password, worker-URL setting, day/night toggle.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isAdmin = false;
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _showUrl = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = context.read<SessionProvider>().api.baseUrl;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _urlCtrl.dispose();
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
        workerUrl: _showUrl ? _urlCtrl.text.trim() : null,
      );
      if (mounted) showMsg(context, 'Welcome back, ${session.user!.username}!');
    } on UnauthorizedException {
      if (mounted) showMsg(context, 'Wrong username or password.', error: true);
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (e) {
      if (mounted) {
        showMsg(context, 'Could not reach the server. Check the worker URL.',
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
    final isWide = MediaQuery.of(context).size.width > 760;

    final form = _buildForm(night);

    return Scaffold(
      body: Row(
        children: [
          if (isWide) _buildBrandPanel(night),
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: form,
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    tooltip: night ? 'Day mode' : 'Night mode',
                    icon: Icon(night ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                    onPressed: () => theme.toggle(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandPanel(bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    return Container(
      width: 380,
      color: brand,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.cloud_outlined, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 24),
          const Text('Team Drive',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text("Your team's files, one secure place.",
              style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 32),
          _brandPoint(Icons.bolt_outlined, 'Fast downloads with resume support'),
          _brandPoint(Icons.lock_outline, 'Private accounts & signed download links'),
          _brandPoint(Icons.cloud_done_outlined, 'Powered by Cloudflare R2'),
        ],
      ),
    );
  }

  Widget _brandPoint(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 14))),
        ]),
      );

  Widget _buildForm(bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Welcome back',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Sign in to your Team Drive',
            style: TextStyle(
                color: night ? AppColors.nightMuted : AppColors.dayMuted)),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: night ? AppColors.nightSide2 : const Color(0xFFEFEDE6),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            _tab('Member', !_isAdmin, () => setState(() => _isAdmin = false), night),
            _tab('Admin', _isAdmin, () => setState(() => _isAdmin = true), night),
          ]),
        ),
        const SizedBox(height: 16),
        if (!_isAdmin) ...[
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(
                labelText: 'Username', hintText: 'e.g. rahim'),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _passCtrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: IconButton(
              icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _showUrl = !_showUrl),
            icon: const Icon(Icons.dns_outlined, size: 16),
            label: const Text('Worker URL'),
          ),
        ),
        if (_showUrl)
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Worker URL',
              hintText: 'https://your-worker.workers.dev',
            ),
          ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: brand),
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
        const SizedBox(height: 12),
        Text(
          'Default worker: ${AppConfig.workerBaseUrl}',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11,
              color: night ? AppColors.nightMuted : AppColors.dayMuted),
        ),
      ],
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap, bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? brand : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: active
                      ? Colors.white
                      : (night ? AppColors.nightMuted : AppColors.dayMuted),
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
