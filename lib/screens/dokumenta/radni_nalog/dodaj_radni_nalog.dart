import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:knjigovodstvo_app/widgets/input_widget.dart';

class DodajRadniNalog extends StatefulWidget {
  const DodajRadniNalog({super.key});

  @override
  State<DodajRadniNalog> createState() => _DodajRadniNalogState();
}

class _DodajRadniNalogState extends State<DodajRadniNalog> {
  final kupacController = TextEditingController();
  final datumController = TextEditingController(
    text: DateTime.now().toString().split(' ')[0],
  );
  final brojNalogaController = TextEditingController();
  final artikalController = TextEditingController();
  final brojKomadaController = TextEditingController();

  @override
  void dispose() {
    kupacController.dispose();
    datumController.dispose();
    brojNalogaController.dispose();
    artikalController.dispose();
    brojKomadaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj radni nalog')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dodaj radni nalog',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 30),

                // Red 1: Kupac
                buildInput(
                  controller: kupacController,
                  label: 'Kupac',
                  width: null,
                ),
                const SizedBox(height: 20),

                // Red 2: Datum + Broj naloga
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: buildInput(
                        controller: datumController,
                        label: 'Datum',
                        width: null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: buildInput(
                        controller: brojNalogaController,
                        label: 'Broj naloga',
                        width: null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Red 3: Artikal + Broj komada
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: buildInput(
                        controller: artikalController,
                        label: 'Artikal',
                        width: null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: buildInput(
                        controller: brojKomadaController,
                        label: 'Broj komada',
                        width: null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Dugmad
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.save_outlined, size: 24),
                      label: const Text('Sačuvaj dokument'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 20,
                        ),
                        minimumSize: const Size(0, 56),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.print),
                      label: const Text('Štampaj'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 20,
                        ),
                        minimumSize: const Size(0, 56),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => Get.back(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 20,
                        ),
                        minimumSize: const Size(0, 56),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Odustani'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
