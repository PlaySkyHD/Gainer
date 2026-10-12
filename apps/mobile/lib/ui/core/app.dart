import 'package:flutter/cupertino.dart';

import 'shell/mobile_shell.dart';
import 'theme.dart';

class GainerMobileApp extends StatefulWidget {
  const GainerMobileApp({super.key});

  @override
  State<GainerMobileApp> createState() => _GainerMobileAppState();
}

class _GainerMobileAppState extends State<GainerMobileApp>
    with WidgetsBindingObserver {
  Brightness _brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      debugShowCheckedModeBanner: false,
      home: const MobileShell(),
    );
  }
}
