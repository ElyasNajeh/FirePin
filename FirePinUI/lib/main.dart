import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/firepin_app.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemUi);
  runApp(const FirePinApp());
}
