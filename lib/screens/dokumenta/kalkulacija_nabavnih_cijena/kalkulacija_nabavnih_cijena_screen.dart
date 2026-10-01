import 'package:flutter/material.dart';
import 'package:knjigovodstvo_app/screens/dokumenta/kalkulacija_nabavnih_cijena/dodaj_kalkulaciju_nabavnu_cijenu.dart';

class KalkulacijaNabavnihCijenaScreen extends StatefulWidget {
  const KalkulacijaNabavnihCijenaScreen({super.key});

  @override
  State<KalkulacijaNabavnihCijenaScreen> createState() =>
      _KalkulacijaNabavnihCijenaScreenState();
}

class _KalkulacijaNabavnihCijenaScreenState
    extends State<KalkulacijaNabavnihCijenaScreen> {
  int currentPage = 1;

  final int totalPages = 3;

  final List<Map<String, String>> dokumenti = [
    {
      'rb': '1',
      'datum': '23.09.2026',
      'dobavljac': 'Firma d.o.o.',
      'rcBr': 'RC-001',
      'prijemnicaBr': 'PR-001',
      'kalkulisao': 'Petar Petrović',
      'robuPrimio': 'Marko Marković',
    },
    {
      'rb': '2',
      'datum': '22.09.2026',
      'dobavljac': 'Komerc Trade',
      'rcBr': 'RC-002',
      'prijemnicaBr': 'PR-002',
      'kalkulisao': 'Petar Petrović',
      'robuPrimio': 'Nikola Nikolić',
    },
    {
      'rb': '3',
      'datum': '20.09.2026',
      'dobavljac': 'Montenegro Commerce',
      'rcBr': 'RC-003',
      'prijemnicaBr': 'PR-003',
      'kalkulisao': 'Jovan Jovanović',
      'robuPrimio': 'Marko Marković',
    },
    {
      'rb': '4',
      'datum': '18.09.2026',
      'dobavljac': 'Balkan Trade',
      'rcBr': 'RC-004',
      'prijemnicaBr': 'PR-004',
      'kalkulisao': 'Petar Petrović',
      'robuPrimio': 'Nikola Nikolić',
    },
    {
      'rb': '5',
      'datum': '15.09.2026',
      'dobavljac': 'Adria Market',
      'rcBr': 'RC-005',
      'prijemnicaBr': 'PR-005',
      'kalkulisao': 'Jovan Jovanović',
      'robuPrimio': 'Marko Marković',
    },
    {
      'rb': '6',
      'datum': '12.09.2026',
      'dobavljac': 'Euro Commerce',
      'rcBr': 'RC-006',
      'prijemnicaBr': 'PR-006',
      'kalkulisao': 'Petar Petrović',
      'robuPrimio': 'Nikola Nikolić',
    },
    {
      'rb': '7',
      'datum': '10.09.2026',
      'dobavljac': 'Primorje Trade',
      'rcBr': 'RC-007',
      'prijemnicaBr': 'PR-007',
      'kalkulisao': 'Jovan Jovanović',
      'robuPrimio': 'Marko Marković',
    },
    {
      'rb': '8',
      'datum': '08.09.2026',
      'dobavljac': 'Market Plus',
      'rcBr': 'RC-008',
      'prijemnicaBr': 'PR-008',
      'kalkulisao': 'Petar Petrović',
      'robuPrimio': 'Nikola Nikolić',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------
            // NASLOV + DUGME
            // ------------------------------------------------
            Row(
              children: [
                const Text(
                  'Kalkulacija nabavnih cijena',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),

                const Spacer(),

                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DodajKalkulacijuScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj novi dokument'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ------------------------------------------------
            // TABELA
            // ------------------------------------------------
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Colors.grey.shade100,
                      ),
                      columnSpacing: 40,

                      columns: const [
                        DataColumn(
                          label: Text(
                            'RB',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'Datum',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'Dobavljač',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'RC.BR',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'Prijemnica br',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'Kalkulisao',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'Robu primio',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),

                        DataColumn(
                          label: Text(
                            'Akcije',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],

                      rows: dokumenti.map((dokument) {
                        return DataRow(
                          cells: [
                            DataCell(Text(dokument['rb']!)),

                            DataCell(Text(dokument['datum']!)),

                            DataCell(Text(dokument['dobavljac']!)),

                            DataCell(Text(dokument['rcBr']!)),

                            DataCell(Text(dokument['prijemnicaBr']!)),

                            DataCell(Text(dokument['kalkulisao']!)),

                            DataCell(Text(dokument['robuPrimio']!)),

                            DataCell(
                              Row(
                                children: [
                                  // Pregled
                                  IconButton(
                                    tooltip: 'Pregled',
                                    onPressed: () {},
                                    icon: const Icon(Icons.visibility_outlined),
                                  ),

                                  // Izmijeni
                                  IconButton(
                                    tooltip: 'Izmijeni',
                                    onPressed: () {},
                                    icon: const Icon(Icons.edit_outlined),
                                  ),

                                  // Obriši
                                  IconButton(
                                    tooltip: 'Obriši',
                                    onPressed: () {},
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ------------------------------------------------
            // PAGINACIJA
            // ------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Prethodna stranica',
                  onPressed: currentPage > 1
                      ? () {
                          setState(() {
                            currentPage--;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),

                const SizedBox(width: 8),

                ...List.generate(totalPages, (index) {
                  final page = index + 1;
                  final isSelected = currentPage == page;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          currentPage = page;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$page',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(width: 8),

                IconButton(
                  tooltip: 'Sljedeća stranica',
                  onPressed: currentPage < totalPages
                      ? () {
                          setState(() {
                            currentPage++;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
