import 'package:flutter/material.dart';

class ObjektiScreen extends StatelessWidget {
  const ObjektiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Objekti'),
      ),
      body: const Center(
        child: Text('Objekti', style: TextStyle(fontSize: 28)),
      ),
    );
  }
}
