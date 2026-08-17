import 'package:flutter/material.dart';

import 'src/ui/home_page.dart';

void main() {
  runApp(const ExportCsvApp());
}

class ExportCsvApp extends StatelessWidget {
  const ExportCsvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1E6F5C));
    return MaterialApp(
      title: 'Excel to CSV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
        scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      ),
      home: const HomePage(),
    );
  }
}
