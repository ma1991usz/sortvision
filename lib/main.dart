import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const SortVisionApp());
}

class SortVisionApp extends StatelessWidget {
  const SortVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SortVision Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
