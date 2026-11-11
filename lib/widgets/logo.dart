import 'package:flutter/material.dart';

import 'magacin_ui.dart';

// Logo aplikacije: zec Kalkulino. LogoZnak je pločica sa gornjim dijelom
// zeca (kao ikona aplikacije), LogoNaziv je naziv sa mint tačkom.

const String _poprsje = 'assets/logo/zec_poprsje.png';
const String zecCijeli = 'assets/logo/zec.png';

class LogoZnak extends StatelessWidget {
  final double velicina;

  // Na tamnoj podlozi pločica dobija mint sjaj, na svijetloj tanku sjenku.
  final bool naTamnom;

  const LogoZnak({super.key, required this.velicina, this.naTamnom = false});

  @override
  Widget build(BuildContext context) {
    final radijus = BorderRadius.circular(velicina * 0.28);
    return Container(
      width: velicina,
      height: velicina,
      decoration: BoxDecoration(
        borderRadius: radijus,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEEF9F5), Color(0xFFC9EEE0)],
        ),
        border: Border.all(
          color: naTamnom
              ? Colors.white.withValues(alpha: 0.55)
              : MagacinBoje.linija,
          width: velicina >= 48 ? 1.5 : 1,
        ),
        boxShadow: naTamnom
            ? const [
                BoxShadow(
                  color: Color(0x553FD0B4),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x1A0A3238),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radijus,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: Image.asset(
              _poprsje,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}

class LogoNaziv extends StatelessWidget {
  final double velicina;
  final Color boja;

  const LogoNaziv({
    super.key,
    required this.velicina,
    this.boja = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final stil = TextStyle(
      fontSize: velicina,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      color: boja,
      height: 1.1,
    );
    // Na bijeloj podlozi svijetla mint se slabo vidi, pa tačka ide tamnija.
    final tacka = boja == Colors.white ? mint : mintTamni;
    return Text.rich(
      TextSpan(
        text: 'Kalkulino',
        style: stil,
        children: [
          TextSpan(
            text: '.',
            style: stil.copyWith(color: tacka),
          ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Maskota Kalkulino u raznim pozama (prazna stanja, početna...)
// ---------------------------------------------------------------------------

enum PozaZeca {
  // Sjedi bočno i drži kalkulator.
  sjedi('assets/logo/zec_sjedi.png'),
  // Stoji i gleda u stranu (traži nešto).
  stoji('assets/logo/zec_stoji.png'),
  // Isto, u majici boje magacina repromaterijala / proizvodnje u toku.
  stojiRepro('assets/logo/zec_stoji_repro.png'),
  stojiProizvodnja('assets/logo/zec_stoji_proizvodnja.png'),
  // Pruža kalkulator: "KLIK!" (poziv na akciju).
  klik('assets/logo/zec_klik.png'),
  // Leži i odmara.
  lezi('assets/logo/zec_lezi.png'),
  // Kuca po kalkulatoru (učitavanje, priprema).
  racuna('assets/logo/zec_racuna.png'),
  // Prekrštene ruke (greška, brisanje).
  ruke('assets/logo/zec_ruke.png');

  final String slika;
  const PozaZeca(this.slika);
}

class Zec extends StatelessWidget {
  final PozaZeca poza;
  final double visina;

  const Zec(this.poza, {super.key, required this.visina});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      poza.slika,
      height: visina,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

// Zec za prazna stanja liste: mint krug iza i mala značka sa ikonom stanja
// (npr. crvena za grešku).
class ZecStanja extends StatelessWidget {
  final PozaZeca poza;
  final IconData ikona;
  final Color boja;
  final Color pozadina;
  final double visina;

  const ZecStanja({
    super.key,
    required this.poza,
    required this.ikona,
    required this.boja,
    required this.pozadina,
    this.visina = 128,
  });

  @override
  Widget build(BuildContext context) {
    // Ležeći zec je širok: umjesto kruga dobija ovalni "jastuk".
    final lezi = poza == PozaZeca.lezi;
    final krug = visina * 0.86;
    // Značka prati veličinu zeca, da na malom zecu ne bude prevelika.
    final znacka = (visina * 0.27).clamp(24.0, 34.0);
    return SizedBox(
      height: visina,
      width: lezi ? visina * 2.3 : visina * 1.25,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: lezi ? visina * 2.2 : krug,
              height: lezi ? visina * 0.5 : krug,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(visina),
                color: pozadina,
                border: Border.all(
                  color: hoverNijansa(boja, 0.12, pozadina),
                  width: 6,
                ),
              ),
            ),
          ),
          Positioned(bottom: 4, child: Zec(poza, visina: visina)),
          Positioned(
            right: lezi ? -4 : visina * 0.1,
            bottom: 2,
            child: Container(
              width: znacka,
              height: znacka,
              decoration: BoxDecoration(
                color: boja,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Icon(ikona, size: znacka * 0.47, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// Učitavanje: Kalkulino kuca po kalkulatoru i blago poskakuje.
class ZecRacuna extends StatefulWidget {
  final String tekst;
  final double visina;

  const ZecRacuna({
    super.key,
    this.tekst = 'Kalkulino računa…',
    this.visina = 120,
  });

  @override
  State<ZecRacuna> createState() => _ZecRacunaState();
}

class _ZecRacunaState extends State<ZecRacuna>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, dijete) {
            final t = Curves.easeInOut.transform(_c.value);
            return Transform.translate(
              offset: Offset(0, -6 * t),
              child: dijete,
            );
          },
          child: Zec(PozaZeca.racuna, visina: widget.visina),
        ),
        // Sjenka koja se skuplja kad zec poskoči.
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_c.value);
            return Container(
              width: widget.visina * (0.55 - 0.1 * t),
              height: 6,
              decoration: BoxDecoration(
                color: akcentTamni.withValues(alpha: 0.12 - 0.05 * t),
                borderRadius: BorderRadius.circular(6),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          widget.tekst,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: MagacinBoje.priguseno,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              minHeight: 4,
              color: mintTamni,
              backgroundColor: mintSvijetlo,
            ),
          ),
        ),
      ],
    );
  }
}
