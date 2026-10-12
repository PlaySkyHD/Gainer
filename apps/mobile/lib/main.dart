import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'ui/core/app.dart';
import 'ui/core/view_models/mobile_shell_view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider<MobileShellViewModel>(
      create: (_) => MobileShellViewModel(),
      child: const GainerMobileApp(),
    ),
  );
}
