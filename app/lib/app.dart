import 'package:flutter/material.dart';

import 'data/remote/aws_alert_repository.dart';
import 'data/remote/aws_auth_repository.dart';
import 'data/remote/aws_patients_repository.dart';
import 'data/remote/aws_tremor_repository.dart';
import 'models/user.dart';
import 'repositories/alert_repository.dart';
import 'repositories/patients_repository.dart';
import 'repositories/tremor_repository.dart';
import 'screens/auth/login_screen.dart';
import 'screens/shell/shell_screen.dart';

class ParkinSenseApp extends StatefulWidget {
  const ParkinSenseApp({super.key});

  @override
  State<ParkinSenseApp> createState() => _ParkinSenseAppState();
}

class _ParkinSenseAppState extends State<ParkinSenseApp>
    with WidgetsBindingObserver {
  final AwsAuthRepository _authRepository = AwsAuthRepository();
  late final TremorRepository _tremorRepository =
      AwsTremorRepository(_authRepository);
  late final AlertRepository _alertRepository =
      AwsAlertRepository(_authRepository);
  late final PatientsRepository _patientsRepository =
      AwsPatientsRepository(_authRepository);

  User? _currentUser;
  bool _isLoading = true;
  bool _isObscured = false;
  DateTime? _backgroundedAt;

  static const _kSessionTimeout = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tryRestoreSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    bool sessionExpired = false;

    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _currentUser != null) {
      final bg = _backgroundedAt;
      if (bg != null && DateTime.now().difference(bg) >= _kSessionTimeout) {
        sessionExpired = true;
        _authRepository.signOut();
      }
      _backgroundedAt = null;
    }

    setState(() {
      if (sessionExpired) _currentUser = null;
      // Keep privacy overlay while backgrounded; remove it on resume (or after timeout, login screen is shown)
      _isObscured = !sessionExpired && state != AppLifecycleState.resumed;
    });
  }

  Future<void> _tryRestoreSession() async {
    try {
      final user = await _authRepository.restoreSession();
      if (mounted) setState(() => _currentUser = user);
    } catch (_) {
      // No restorable session — show login screen
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onLogin(User user) => setState(() => _currentUser = user);

  void _onSignOut() {
    _authRepository.signOut(); // clears persisted tokens from secure storage
    setState(() => _currentUser = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF42A5F5),
        ),
        home: const Scaffold(
          backgroundColor: Color(0xFF42A5F5),
          body: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    return MaterialApp(
      title: 'ParkinSense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF42A5F5),
      ),
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            if (_isObscured) const _PrivacyScreen(),
          ],
        );
      },
      home: _currentUser == null
          ? LoginScreen(
              authRepository: _authRepository,
              onLogin: _onLogin,
            )
          : ShellScreen(
              user: _currentUser!,
              tremorRepository: _tremorRepository,
              alertRepository: _alertRepository,
              patientsRepository: _patientsRepository,
              onSignOut: _onSignOut,
            ),
    );
  }
}

class _PrivacyScreen extends StatelessWidget {
  const _PrivacyScreen();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF1565C0),
      child: Center(
        child: Icon(Icons.lock_outline, color: Colors.white, size: 64),
      ),
    );
  }
}
