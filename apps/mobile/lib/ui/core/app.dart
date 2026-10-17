import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../data/services/auth/mobile_auth_controller.dart';
import '../../data/services/platform/pigeon_native_route_dispatcher.dart';
import '../features/access/auth_screen.dart';
import 'shell/mobile_shell.dart';
import 'theme.dart';

class GainerMobileApp extends StatefulWidget {
  const GainerMobileApp({this.configuration, super.key});

  final MobileAppConfiguration? configuration;

  @override
  State<GainerMobileApp> createState() => _GainerMobileAppState();
}

class _GainerMobileAppState extends State<GainerMobileApp>
    with WidgetsBindingObserver {
  Brightness _brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  MobileAuthController? _auth;
  PigeonNativeRouteDispatcher? _routes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final configuration = widget.configuration;
    if (configuration != null) {
      final auth = MobileAuthController(configuration: configuration);
      _auth = auth;
      _routes = PigeonNativeRouteDispatcher(consumer: auth);
      auth.initialize();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routes?.dispose();
    _auth?.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (brightness == _brightness) return;
    setState(() => _brightness = brightness);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Gainer',
      theme: GainerTheme.forBrightness(_brightness),
      builder: (context, child) => GainerDesign(child: child!),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: const [
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      home: _auth == null
          ? const StartupConfigurationErrorScreen()
          : AnimatedBuilder(
              animation: _auth!,
              builder: (context, _) {
                if (_auth!.state == MobileAuthState.starting) {
                  return const _StartupScreen();
                }
                final account = _auth!.account;
                if (account == null) return AuthScreen(controller: _auth!);
                return MobileShell(
                  key: ValueKey(
                    '${account.session.userId}:${account.generation}',
                  ),
                  controller: _auth!,
                  account: account,
                );
              },
            ),
    );
  }
}

class StartupConfigurationErrorScreen extends StatelessWidget {
  const StartupConfigurationErrorScreen({super.key});
  @override
  Widget build(BuildContext context) => const CupertinoPageScaffold(
    child: SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.exclamationmark_circle, size: 44),
                SizedBox(height: 16),
                Text(
                  'Gainer kann noch nicht starten',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10),
                Text(
                  'Die App benötigt eine gültige API-Konfiguration. Bitte installiere eine korrekt konfigurierte Version.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();
  @override
  Widget build(BuildContext context) => const CupertinoPageScaffold(
    child: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(),
            SizedBox(height: 12),
            Text('Sitzung wird geprüft …'),
          ],
        ),
      ),
    ),
  );
}
