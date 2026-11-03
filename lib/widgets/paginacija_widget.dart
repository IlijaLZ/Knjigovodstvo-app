import 'package:flutter/material.dart';

// Red sa podacima o serverskoj paginaciji (meta) i dugmadima za stranice.
class Paginacija extends StatelessWidget {
  final int stranica;
  final int zadnjaStranica;
  final int ukupno;
  final int? od;
  final int? doBroja;
  final bool zakljucano;
  final String prazno;
  final ValueChanged<int> onStranica;

  const Paginacija({
    super.key,
    required this.stranica,
    required this.zadnjaStranica,
    required this.ukupno,
    required this.onStranica,
    this.od,
    this.doBroja,
    this.zakljucano = false,
    this.prazno = 'Nema podataka',
  });

  @override
  Widget build(BuildContext context) {
    final nazad = stranica > 1 && !zakljucano;
    final naprijed = stranica < zadnjaStranica && !zakljucano;

    return Row(
      children: [
        Text(
          ukupno == 0
              ? prazno
              : 'Prikazano ${od ?? 0}–${doBroja ?? 0} od $ukupno',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Prva stranica',
          onPressed: nazad ? () => onStranica(1) : null,
          icon: const Icon(Icons.first_page),
        ),
        IconButton(
          tooltip: 'Prethodna stranica',
          onPressed: nazad ? () => onStranica(stranica - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Strana $stranica od $zadnjaStranica'),
        IconButton(
          tooltip: 'Sljedeća stranica',
          onPressed: naprijed ? () => onStranica(stranica + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: 'Zadnja stranica',
          onPressed: naprijed ? () => onStranica(zadnjaStranica) : null,
          icon: const Icon(Icons.last_page),
        ),
      ],
    );
  }
}
