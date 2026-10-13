import 'package:flutter/material.dart';

class ProizvodnjaUToku extends StatelessWidget {
  const ProizvodnjaUToku({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Proizvodnja u toku'),
      ),
      body: const Center(
        child: Text('Proizvodnja u toku', style: TextStyle(fontSize: 28)),
      ),
    );
  }
}
