import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'utils/water_transitions.dart';
import 'core/update/update_service.dart';
import 'core/notifications/call_notification.dart';
import 'features/call/active_call.dart';
import 'features/call/call_bar.dart';
import 'core/auth/phone_auth_service.dart';
import 'features/contacts/contact_controller.dart';
import 'features/contacts/contacts_screen.dart';
import 'firebase_options.dart';
import 'core/notifications/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/settings/app_settings.dart';
import 'utils/glass.dart';
import 'utils/splash_screen.dart';
import 'utils/perf_guard.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

final GlobalKey<NavigatorState> appNavKey = GlobalKey<NavigatorState>();


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError =
      (d) => debugPrint('FLUTTER ERROR: ${d.exceptionAsString()}');
  WidgetsBinding.instance.platformDispatcher.onError = (e, s) {
    debugPrint('UNCAUGHT: $e');
    return true;
  };
  ErrorWidget.builder = (d) => const SizedBox.shrink();
  if (!kIsWeb) {
    FlutterDisplayMode.setHighRefreshRate().catchError((_) {});
  }

  // Push setup is skipped on web (Chrome has no FCM service worker here)
  // and can never block the app from starting.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      messaging
          .getToken()
          .then((t) => debugPrint('FCM TOKEN: $t'))
          .catchError((_) {});
      // token is printed in the background above
    } catch (e) {
      debugPrint('Firebase/FCM setup skipped: $e');
    }
  }

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  } catch (e) {
    debugPrint('Supabase init: $e');
  }

  try {
    await CallNotification.checkLaunchAction();
  } catch (_) {}
  try {
    await AppSettings.load();
  } catch (e) {
    debugPrint('Settings load: $e');
  }
  runApp(const P2PCallApp());
  Future.delayed(const Duration(seconds: 10), PerfGuard.start);
  UpdateService.instance.start(appNavKey);
  CallNotification.openCallListener = ActiveCall.returnToCall;
  CallNotification.endCallListener = ActiveCall.hangUpRunning;
}

class P2PCallApp extends StatelessWidget {
  const P2PCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppSettings.accent,
      builder: (context, accent, _) => MaterialApp(
      navigatorKey: appNavKey,
      builder: (context, child) =>
          CallBarHost(child: child ?? const SizedBox()),
      title: 'P2P Call',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const WaterScrollBehavior(),
      theme: ThemeData(
        colorSchemeSeed: Color(accent),
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: WaterTransitionsBuilder(),
            TargetPlatform.iOS: WaterTransitionsBuilder(),
            TargetPlatform.windows: WaterTransitionsBuilder(),
            TargetPlatform.linux: WaterTransitionsBuilder(),
            TargetPlatform.macOS: WaterTransitionsBuilder(),
          },
        ),
      ),
      home: const _StartupGate(),
    ));
  }
}

/// Signs the user in (anonymously, for now) and creates their UID before
/// dropping them into the contacts screen. Once real phone OTP is wired
/// up, swap the call inside _init() from signInAnonymously() to the
/// phone-login flow — nothing else here needs to change.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  final _authService = PhoneAuthService();
  final _contactController = ContactController();

  String? _myUid;
  String? _error;
  bool _needsLogin = false;
  bool _signingIn = false;
  String? _loginMsg;

  // Opening animation: only on a normal open, never for a call wake-up.
  bool _splash = CallNotification.pendingCall == null &&
      CallNotification.pendingAction == null;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut && mounted) {
        setState(() {
          _myUid = null;
          _error = null;
          _needsLogin = true;
        });
      }
    });
    _init();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _loginMsg = null;
    });
    try {
      await _authService.signInWithGoogle();
      if (!mounted) return;
      setState(() {
        _needsLogin = false;
        _signingIn = false;
      });
      _init();
    } catch (e) {
      debugPrint('Sign-in error: $e');
      if (!mounted) return;
      final s = e.toString().toLowerCase();
      setState(() {
        _signingIn = false;
        _loginMsg = s.contains('cancel')
            ? null
            : 'Sign-in failed. Check your internet and try again.';
      });
    }
  }

  Future<void> _init() async {
    try {
      if (_authService.isAnonymous) await _authService.signOut();
      if (!_authService.isSignedIn) {
        if (!mounted) return;
        setState(() => _needsLogin = true);
        return;
      }
      String? uid;
      final authId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final prefs = await SharedPreferences.getInstance();
      try {
        uid = await _authService
            .getMyUid()
            .timeout(const Duration(seconds: 6));
        if (uid != null) await prefs.setString('my_uid_$authId', uid);
      } catch (_) {
        final cached = prefs.getString('my_uid_$authId');
        if (cached == null) rethrow;
        uid = cached;
      }
      if (!kIsWeb) PushNotificationService().init();
      if (!mounted) return;
      setState(() => _myUid = uid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _gate(),
        if (_splash)
          SplashScreen(onDone: () {
            if (mounted) setState(() => _splash = false);
          }),
      ],
    );
  }

  Widget _gate() {
    final k = _error != null
        ? 'e'
        : _needsLogin
            ? 'l'
            : _myUid == null
                ? 'w'
                : 'c';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(key: ValueKey(k), child: _screen(context)),
    );
  }

  Widget _glow(double size, Color c, double a) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [c.withOpacity(a), c.withOpacity(0)],
            ),
          ),
        ),
      );

  Widget _loginScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF042F2E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0F766E), Color(0xFF042F2E)],
              ),
            ),
          ),
          Positioned(
            top: -90,
            right: -70,
            child: _glow(260, const Color(0xFF5EEAD4), 0.28),
          ),
          Positioned(
            bottom: 120,
            left: -110,
            child: _glow(300, const Color(0xFF14B8A6), 0.20),
          ),
          SafeArea(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(
                  offset: Offset(0, 28 * (1 - v)),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    Container(
                      width: 104,
                      height: 104,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'QualityTime',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Clear calls. Low data.',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const Spacer(flex: 4),
                    Glass(
                      borderRadius: BorderRadius.circular(28),
                      blur: 18,
                      tint: Colors.white,
                      opacity: 0.12,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF042F2E),
                                disabledBackgroundColor: Colors.white70,
                                disabledForegroundColor:
                                    const Color(0xFF042F2E),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _signingIn ? null : _signInWithGoogle,
                              icon: _signingIn
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.login),
                              label: Text(
                                _signingIn
                                    ? 'Signing in...'
                                    : 'Continue with Google',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (_loginMsg != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _loginMsg!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFCA5A5),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _screen(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: $_error'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() => _error = null);
                  _init();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_needsLogin) return _loginScreen();

    if (_myUid == null) {
      final name = CallNotification.pendingCall?['n']?.toString();
      return Scaffold(
        backgroundColor: const Color(0xFF042F2E),
        body: Center(
          child: name == null
              ? Image.asset('assets/icon/app_icon.png',
                  width: 96, height: 96)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 24)),
                    const SizedBox(height: 8),
                    const Text('Connecting...',
                        style: TextStyle(color: Colors.white70)),
                  ],
                ),
        ),
      );
    }

    return ContactsScreen(
      key: ValueKey(_myUid),
      contactController: _contactController,
      myUid: _myUid!,
      onIdChanged: _init,
    );
  }
}