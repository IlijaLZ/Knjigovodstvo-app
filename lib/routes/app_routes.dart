import 'package:get/get.dart';

import '../screens/main_screen.dart';

class AppRoutes {
  static const String main = '/';

  static final List<GetPage> pages = [
    GetPage(name: main, page: () => MainScreen()),
  ];
}
