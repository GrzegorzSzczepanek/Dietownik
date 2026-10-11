import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/shell.dart';

class DietownikApp extends StatelessWidget {
  const DietownikApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Dietownik',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      );
}
