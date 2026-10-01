import 'package:flutter/material.dart';

class OFirmiScreen extends StatelessWidget {
  final TextEditingController nazivFirmeController = TextEditingController();
  final TextEditingController adresaController = TextEditingController();
  final TextEditingController pibController = TextEditingController();
  final TextEditingController pdvController = TextEditingController();
  final TextEditingController ovlascenoLiceController = TextEditingController();

  OFirmiScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Podaci o firmi',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: 500,
                child: Column(
                  children: [
                    TextField(
                      controller: nazivFirmeController,
                      decoration: InputDecoration(
                        labelText: 'Naziv firme',
                        hintText: 'Unesite naziv firme',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: adresaController,
                      decoration: InputDecoration(
                        labelText: 'Adresa',
                        hintText: 'Unesite adresu firme',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: pibController,
                      decoration: InputDecoration(
                        labelText: 'PIB',
                        hintText: 'Unesite PIB',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: pdvController,
                      decoration: InputDecoration(
                        labelText: 'PDV',
                        hintText: 'Unesite PDV broj',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: ovlascenoLiceController,
                      decoration: InputDecoration(
                        labelText: 'Ovlašćeno lice',
                        hintText: 'Unesite ime i prezime ovlašćenog lica',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Sačuvaj'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
