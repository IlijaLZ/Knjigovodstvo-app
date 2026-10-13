import 'package:flutter/material.dart';

class MagacinGotovihProizvoda extends StatelessWidget {
  const MagacinGotovihProizvoda({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Magacin gotovih proizvoda'),
      ),
      body: const Center(
        child: Text(
          'Magacin gotovih proizvoda',
          style: TextStyle(fontSize: 28),
        ),
      ),
    );
  }
}
