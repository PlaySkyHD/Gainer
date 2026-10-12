import 'package:flutter/cupertino.dart';

import 'data/services/auth/mobile_auth_controller.dart';
import 'ui/core/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    GainerMobileApp(configuration: MobileAppConfiguration.fromEnvironment()),
  );
}
