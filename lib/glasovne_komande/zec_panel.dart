import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../widgets/magacin_ui.dart';
import 'glasovne_komande.dart';
import 'glasovno_dugme.dart';

// Zec Kalkulino u donjem desnom uglu: izviri kad mu se obratiš, sluša,
// računa, klikne kad izvrši komandu, prekrsti ruke kad ne razumije.
// Uvezan u main.dart kroz GetMaterialApp(builder: …), pa je iznad svih
// ekrana (i kartice i unosa radnog naloga).

class ZecSloj extends StatelessWidget {
  final Widget child;

  const ZecSloj({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const Positioned(right: 0, bottom: 0, child: _ZecPanel()),
      ],
    );
  }
}

String _slika(ZecRaspolozenje r) => switch (r) {
  ZecRaspolozenje.slusa => 'assets/zec_glas/slusa.png',
  ZecRaspolozenje.pise => 'assets/zec_glas/pise.png',
  ZecRaspolozenje.prica => 'assets/zec_glas/prica.png',
  ZecRaspolozenje.racuna => 'assets/zec_glas/trazi.png',
  ZecRaspolozenje.klik => 'assets/zec_glas/klik.png',
  ZecRaspolozenje.zbunjen => 'assets/zec_glas/zbunjen.png',
  ZecRaspolozenje.greska => 'assets/zec_glas/greska.png',
};

// Poprsje je odsječeno (izviri iza ivice), cijeli zec mora biti viši da
// glava ostane iste veličine.
bool _poprsje(ZecRaspolozenje r) =>
    r == ZecRaspolozenje.slusa ||
    r == ZecRaspolozenje.prica ||
    r == ZecRaspolozenje.greska;

double _visinaPoze(ZecRaspolozenje r) => _poprsje(r) ? 1.0 : 1.3;

bool _slusa(ZecRaspolozenje r) =>
    r == ZecRaspolozenje.slusa || r == ZecRaspolozenje.pise;

// Primjeri dok se diktira u polje.
const List<String> _primjeriDiktata = [
  '„1234”',
  '„1232 ne nego 1234”',
  '„dva zarez pet”',
  '„Marko dalje Ivan” (sljedeće polje)',
  '„obriši”',
];

// Primjeri koji se vrte dok zec čeka da progovoriš.
const List<String> _primjeri = [
  '„otvori trebovanja”',
  '„novi radni nalog”',
  '„analitička kartica brašna”',
  '„stanje magacina”',
  '„nova kalkulacija”',
  '„kupci”',
];

class _ZecPanel extends StatefulWidget {
  const _ZecPanel();

  @override
  State<_ZecPanel> createState() => _ZecPanelState();
}

class _ZecPanelState extends State<_ZecPanel> with TickerProviderStateMixin {
  final GlasovniController _c = glasovniController();

  // Ulaz/izlaz (izviri odozdo sa malim odskokom).
  late final AnimationController _ulaz = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: const Duration(milliseconds: 280),
  );

  // Stalni "dah": lagano ljuljanje zeca, talasi, tačkice.
  late final AnimationController _dah = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  late final Worker _worker;
  ZecRaspolozenje _zadnje = ZecRaspolozenje.prica;
  Timer? _primjerTimer;
  int _primjer = 0;

  @override
  void initState() {
    super.initState();
    _worker = ever<ZecRaspolozenje?>(_c.zec, _promjena);
    _promjena(_c.zec.value);
  }

  void _promjena(ZecRaspolozenje? r) {
    if (r == null) {
      _ulaz.reverse();
    } else {
      _zadnje = r;
      _ulaz.forward();
    }
    _primjerTimer?.cancel();
    if (r != null && _slusa(r)) {
      _primjer = 0;
      _primjerTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
        if (!mounted) return;
        setState(() => _primjer++);
      });
    }
  }

  @override
  void dispose() {
    _worker.dispose();
    _primjerTimer?.cancel();
    _ulaz.dispose();
    _dah.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sirina = MediaQuery.sizeOf(context).width;
    final usko = sirina < 640;
    final visinaZeca = usko ? 150.0 : 220.0;
    final sirinaOblacica = math.min(340.0, sirina - visinaZeca * 0.7 - 40);

    return AnimatedBuilder(
      animation: _ulaz,
      builder: (context, child) {
        if (_ulaz.isDismissed) return const SizedBox.shrink();
        final t = _ulaz.value;
        final pomak = Curves.easeOutBack.transform(t);
        return Opacity(
          opacity: Curves.easeOut.transform(t.clamp(0.0, 1.0)),
          child: Transform.translate(
            offset: Offset(0, (1 - pomak) * visinaZeca * 0.9),
            child: child,
          ),
        );
      },
      // Klik na zeca ne skida fokus sa polja (diktiranje u polje).
      child: TextFieldTapRegion(
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: EdgeInsets.only(right: usko ? 4 : 20),
            child: Obx(() {
              final r = _c.zec.value ?? _zadnje;
              final slusa = _slusa(r);
              final polje = _c.diktatPolje.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: visinaZeca * 0.32),
                    child: SizedBox(
                      width: sirinaOblacica,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _ZecOblacic(
                            tekst: !slusa
                                ? _c.zecTekst.value
                                : polje != null
                                ? (_c.tekst.value.isEmpty
                                      ? 'Diktiraj u „$polje”. Npr. '
                                            '${_primjeriDiktata[_primjer % _primjeriDiktata.length]}'
                                      : 'Pišem u „$polje”…')
                                : _c.tekst.value.isEmpty
                                ? 'Slušam te! Probaj '
                                      '${_primjeri[_primjer % _primjeri.length]}'
                                : 'Mhm… slušam.',
                            raspolozenje: r,
                            dah: _dah,
                            onZatvori: _c.sakrij,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _Zec(
                    visina: visinaZeca,
                    raspolozenje: r,
                    dah: _dah,
                    nivo: _c.nivo,
                    onTap: _c.prekidac,
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zec
// ---------------------------------------------------------------------------

class _Zec extends StatefulWidget {
  final double visina;
  final ZecRaspolozenje raspolozenje;
  final Animation<double> dah;
  final RxDouble nivo;
  final VoidCallback onTap;

  const _Zec({
    required this.visina,
    required this.raspolozenje,
    required this.dah,
    required this.nivo,
    required this.onTap,
  });

  @override
  State<_Zec> createState() => _ZecState();
}

class _ZecState extends State<_Zec> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.raspolozenje;
    final slusa = _slusa(r);
    final zbunjen = r == ZecRaspolozenje.zbunjen || r == ZecRaspolozenje.greska;
    final v = widget.visina;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: v * 0.82,
          height: v * _visinaPoze(ZecRaspolozenje.klik),
          child: AnimatedBuilder(
            animation: widget.dah,
            builder: (context, _) {
              final faza = widget.dah.value * 2 * math.pi;
              final nivo = slusa ? widget.nivo.value : 0.0;
              // Dok sluša: naginje glavu u ritmu glasa; inače mirno diše.
              final nagib = slusa
                  ? math.sin(faza * 2) * 0.025 + nivo * 0.04
                  : zbunjen
                  ? math.sin(faza * 3) * 0.012
                  : math.sin(faza) * 0.012;
              final odskok = math.sin(faza * 2) * (slusa ? 2.5 : 1.5);
              final sjaj = slusa ? 0.35 + nivo * 0.65 : 0.25;
              final boja = zbunjen ? MagacinBoje.narandzasta : mint;

              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  // Sjaj iza zeca — dok sluša pulsira sa glasom.
                  Positioned(
                    bottom: -v * 0.25,
                    child: Container(
                      width: v * (0.95 + sjaj * 0.35),
                      height: v * (0.95 + sjaj * 0.35),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            boja.withValues(alpha: 0.55 * sjaj),
                            boja.withValues(alpha: 0.18 * sjaj),
                            boja.withValues(alpha: 0),
                          ],
                          stops: const [0, 0.55, 1],
                        ),
                      ),
                    ),
                  ),
                  // Talasi zvuka oko glave dok sluša.
                  if (slusa)
                    for (var i = 0; i < 3; i++)
                      _Talas(
                        faza: (widget.dah.value * 1.6 + i / 3) % 1,
                        velicina: v * 0.55,
                        // Centar glave poprsja: okvir je viši (za cijelog
                        // zeca), a poprsje stoji uz donju ivicu.
                        centar: _visinaPoze(r) == 1
                            ? v * (_visinaPoze(ZecRaspolozenje.klik) - 1) +
                                  v * 0.42
                            : v * 0.36,
                        jacina: 0.4 + nivo * 0.6,
                      ),
                  Transform.translate(
                    offset: Offset(0, -odskok + (_hover ? -6 : 0)),
                    child: Transform.rotate(
                      angle: nagib,
                      alignment: Alignment.bottomCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutBack,
                        transitionBuilder: (child, a) => ScaleTransition(
                          scale: Tween(begin: 0.85, end: 1.0).animate(a),
                          alignment: Alignment.bottomCenter,
                          child: FadeTransition(opacity: a, child: child),
                        ),
                        child: Image.asset(
                          _slika(r),
                          key: ValueKey(_slika(r)),
                          height: v * _visinaPoze(r),
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomCenter,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// Krug koji se širi i blijedi (kao zvuk) oko zečije glave.
class _Talas extends StatelessWidget {
  final double faza;
  final double velicina;
  final double centar;
  final double jacina;

  const _Talas({
    required this.faza,
    required this.velicina,
    required this.centar,
    required this.jacina,
  });

  @override
  Widget build(BuildContext context) {
    final s = velicina * (0.6 + faza * 0.9);
    return Positioned(
      top: centar - s / 2,
      child: IgnorePointer(
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: akcentAplikacije.withValues(
                alpha: (1 - faza) * 0.45 * jacina,
              ),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Oblačići
// ---------------------------------------------------------------------------

class _ZecOblacic extends StatelessWidget {
  final String tekst;
  final ZecRaspolozenje raspolozenje;
  final Animation<double> dah;
  final VoidCallback onZatvori;

  const _ZecOblacic({
    required this.tekst,
    required this.raspolozenje,
    required this.dah,
    required this.onZatvori,
  });

  @override
  Widget build(BuildContext context) {
    final zbunjen =
        raspolozenje == ZecRaspolozenje.zbunjen ||
        raspolozenje == ZecRaspolozenje.greska;
    final klik = raspolozenje == ZecRaspolozenje.klik;
    final racuna = raspolozenje == ZecRaspolozenje.racuna;

    final (ikona, oznaka) = switch (raspolozenje) {
      ZecRaspolozenje.slusa => (Icons.hearing_rounded, 'SLUŠAM'),
      ZecRaspolozenje.pise => (Icons.edit_note_rounded, 'PIŠEM'),
      ZecRaspolozenje.racuna => (Icons.search_rounded, 'TRAŽIM'),
      ZecRaspolozenje.klik => (Icons.check_circle_rounded, 'KLIK!'),
      ZecRaspolozenje.zbunjen => (Icons.help_rounded, 'HMM…'),
      ZecRaspolozenje.greska => (Icons.mic_off_rounded, 'UPS'),
      ZecRaspolozenje.prica => (Icons.chat_bubble_rounded, 'KALKULINO'),
    };
    final akcentOznake = zbunjen
        ? const Color(0xFFFBBF24)
        : klik
        ? const Color(0xFF6EE7B7)
        : mint;

    return CustomPaint(
      painter: _RepPainter(boja: akcentNoc),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [akcentTamni, akcentNoc],
          ),
          border: Border.all(
            color: (zbunjen ? MagacinBoje.narandzasta : mint).withValues(
              alpha: 0.35,
            ),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x400A3238),
              blurRadius: 22,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ikona, size: 14, color: akcentOznake),
                const SizedBox(width: 6),
                Text(
                  oznaka,
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w900,
                    color: akcentOznake,
                  ),
                ),
                if (racuna || raspolozenje == ZecRaspolozenje.pise) ...[
                  const SizedBox(width: 8),
                  _Tackice(dah: dah, boja: akcentOznake),
                ],
                const Spacer(),
                InkResponse(
                  onTap: onZatvori,
                  radius: 16,
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              layoutBuilder: (cur, prev) => Stack(
                alignment: Alignment.topLeft,
                children: [...prev, ?cur],
              ),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: Padding(
                key: ValueKey(tekst),
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  tekst,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Repić oblačića koji pokazuje na zeca (dolje desno).
class _RepPainter extends CustomPainter {
  final Color boja;

  const _RepPainter({required this.boja});

  @override
  void paint(Canvas canvas, Size size) {
    final put = Path()
      ..moveTo(size.width - 18, size.height - 1)
      ..quadraticBezierTo(
        size.width + 4,
        size.height + 2,
        size.width + 14,
        size.height + 12,
      )
      ..quadraticBezierTo(
        size.width + 2,
        size.height - 4,
        size.width - 2,
        size.height - 14,
      )
      ..close();
    canvas.drawPath(put, Paint()..color = boja);
  }

  @override
  bool shouldRepaint(_RepPainter old) => old.boja != boja;
}

class _Tackice extends StatelessWidget {
  final Animation<double> dah;
  final Color boja;

  const _Tackice({required this.dah, required this.boja});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dah,
      builder: (context, _) => Row(
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: boja.withValues(
                  alpha:
                      0.3 +
                      0.7 *
                          (math.sin(dah.value * 2 * math.pi * 4 - i * 0.9) *
                                  0.5 +
                              0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
