import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_config_scope.dart';
import '../../firebase/firebase_client.dart';
import '../../logging/app_logger.dart';
import 'auth_credentials_store.dart';


class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.firebase});

  final FirebaseClient firebase;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _uidCtrl = TextEditingController();

  bool _rememberMe = false;
  bool _obscurePassword = true;
  bool _submitting = false;
  bool _prefillDone = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final saved = await AuthCredentialsStore.load();
    if (!mounted) return;
    setState(() {
      if (saved.rememberMe) {
        _emailCtrl.text = saved.email;
        _passwordCtrl.text = saved.password;
        _uidCtrl.text = saved.uid;
        _rememberMe = true;
      }
      _prefillDone = true;
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _uidCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final uid = _uidCtrl.text.trim();

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final cred = await widget.firebase.signInWithEmailPassword(
        email: email,
        password: password,
      );
      final actualUid = cred.user?.uid ?? '';

      if (actualUid.isEmpty || actualUid != uid) {
        
        
        try {
          await widget.firebase.signOut();
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _errorMessage = 'Signed in successfully but the UID does not match.\n'
              'Expected: $uid\nActual: $actualUid';
        });
        return;
      }

      
      if (!mounted) return;
      final controller = AppConfigScope.of(context);
      await controller.update(controller.value.copyWith(allowedUid: uid));

      if (_rememberMe) {
        await AuthCredentialsStore.save(AuthCredentials(
          email: email,
          password: password,
          uid: uid,
          rememberMe: true,
        ));
      } else {
        await AuthCredentialsStore.clear();
      }

      AppLogger.instance.info('Sign-in succeeded', context: {'uid': uid});

      
      TextInput.finishAutofillContext(shouldSave: _rememberMe);
    } on FirebaseAuthException catch (e, st) {
      AppLogger.instance.warn(
        'Sign-in failed',
        context: {'code': e.code, 'message': e.message ?? ''},
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = _friendlyAuthError(e);
      });
      
      
      assert(() {
        debugPrint('Sign-in error: $e\n$st');
        return true;
      }());
    } catch (e) {
      AppLogger.instance.error('Sign-in unknown error', context: {'error': '$e'});
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = e.toString();
      });
    }
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many failed attempts. Try again in a moment.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message ?? 'Sign-in failed (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!_prefillDone) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/icons/vest_tracker_icon.png',
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Vest Tracker',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in to continue',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'Email is required';
                          if (!t.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.password],
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Password is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _uidCtrl,
                        decoration: const InputDecoration(
                          labelText: 'UID',
                          hintText: 'T23KmMSm7gY0Ui43aBavfbFWU842',
                          helperText: 'Must match your RTDB rule UID',
                          prefixIcon: Icon(Icons.fingerprint_outlined),
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'UID is required';
                          if (t.length < 8) return 'UID looks too short';
                          return null;
                        },
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _rememberMe,
                        onChanged: (v) => setState(() => _rememberMe = v),
                        title: const Text('Remember me'),
                        subtitle: const Text(
                          'Save email, password and UID on this device.',
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline,
                                  color: cs.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: cs.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: Text(_submitting ? 'Signing in…' : 'Sign in'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
