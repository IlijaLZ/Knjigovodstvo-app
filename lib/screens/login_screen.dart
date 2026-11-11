import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../widgets/logo.dart';
import '../widgets/magacin_ui.dart';

const Color _akcent = Color(0xFF0F5C66);
const Color _akcentTamni = Color(0xFF0C4D56);
const List<Color> _gradijent = [
  Color(0xFF062226),
  Color(0xFF0D4950),
  Color(0xFF0F5C66),
];

// Širina od koje se prikazuje bočni panel pored forme.
const double _sirinaPanela = 960;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthController authController = Get.find<AuthController>();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final passwordFocus = FocusNode();

  bool sakrijLozinku = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  void _prijava() {
    if (authController.isLoading.value) return;
    authController.login(emailController.text, passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MagacinBoje.pozadina,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final siroko = constraints.maxWidth >= _sirinaPanela;

          if (siroko) {
            return Row(
              children: [
                Expanded(
                  flex: 11,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _Panel(visina: constraints.maxHeight),
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: _forma(saNaslovom: true),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          // Usko: kompaktno zaglavlje u boji, ispod njega forma u kartici.
          final malo = constraints.maxWidth < 480;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  const _UskoZaglavlje(),
                  Transform.translate(
                    offset: const Offset(0, -36),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: malo ? 14 : 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Container(
                          padding: EdgeInsets.all(malo ? 22 : 32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: MagacinBoje.linija),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x140F172A),
                                blurRadius: 32,
                                offset: Offset(0, 14),
                              ),
                            ],
                          ),
                          child: _forma(saNaslovom: true),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _forma({required bool saNaslovom}) {
    return Obx(() {
      final loading = authController.isLoading.value;
      final greska = authController.errorMessage.value;

      return AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (saNaslovom) ...[
              const Text(
                'Dobrodošli nazad',
                style: TextStyle(
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Prijavite se na svoj nalog da nastavite.',
                style: TextStyle(fontSize: 14, color: MagacinBoje.priguseno),
              ),
              const SizedBox(height: 28),
            ],

            // Greška se pojavi i nestane glatko, bez skoka forme.
            AnimatedSize(
              duration: hoverTrajanje,
              curve: hoverKriva,
              alignment: Alignment.topCenter,
              child: greska == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: MagacinBoje.crvenaSvijetlo,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hoverNijansa(MagacinBoje.crvena, 0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 19,
                              color: MagacinBoje.crvena,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                greska,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: MagacinBoje.crvena,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            const _Oznaka('Email'),
            TextField(
              controller: emailController,
              enabled: !loading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => passwordFocus.requestFocus(),
              style: _stilUnosa,
              decoration: _decoration(
                hint: 'marko@gmail.com',
                icon: Icons.alternate_email_rounded,
                errorText: authController.emailError.value,
              ),
            ),

            const SizedBox(height: 18),

            const _Oznaka('Lozinka'),
            TextField(
              controller: passwordController,
              focusNode: passwordFocus,
              enabled: !loading,
              obscureText: sakrijLozinku,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _prijava(),
              style: _stilUnosa,
              decoration: _decoration(
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                errorText: authController.passwordError.value,
                suffix: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    tooltip: sakrijLozinku
                        ? 'Prikaži lozinku'
                        : 'Sakrij lozinku',
                    color: MagacinBoje.priguseno,
                    icon: AnimatedSwitcher(
                      duration: hoverTrajanje,
                      child: Icon(
                        sakrijLozinku
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        key: ValueKey(sakrijLozinku),
                        size: 20,
                      ),
                    ),
                    onPressed: () =>
                        setState(() => sakrijLozinku = !sakrijLozinku),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            _DugmePrijave(ucitavanje: loading, onTap: _prijava),

            const SizedBox(height: 22),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 14,
                  color: MagacinBoje.svijetlo,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Sigurna veza sa serverom',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: MagacinBoje.svijetlo),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  static const _stilUnosa = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
    color: MagacinBoje.naslov,
  );

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    String? errorText,
    Widget? suffix,
  }) {
    OutlineInputBorder okvir(Color boja, [double sirina = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: boja, width: sirina),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: MagacinBoje.svijetlo),
      errorText: errorText,
      prefixIcon: Icon(icon, size: 20),
      prefixIconColor: WidgetStateColor.resolveWith(
        (s) => s.contains(WidgetState.error)
            ? MagacinBoje.crvena
            : s.contains(WidgetState.focused)
            ? _akcent
            : MagacinBoje.svijetlo,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: MagacinBoje.zaglavlje,
      hoverColor: const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: okvir(MagacinBoje.linija),
      enabledBorder: okvir(MagacinBoje.linija),
      disabledBorder: okvir(MagacinBoje.linijaSvijetla),
      focusedBorder: okvir(_akcent, 1.6),
      errorBorder: okvir(hoverNijansa(MagacinBoje.crvena, 0.5)),
      focusedErrorBorder: okvir(MagacinBoje.crvena, 1.6),
    );
  }
}

class _Oznaka extends StatelessWidget {
  final String tekst;

  const _Oznaka(this.tekst);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        tekst,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: MagacinBoje.tekst,
        ),
      ),
    );
  }
}

// Glavno dugme sa glatkim hoverom (neprozirne boje, bez bljeska).
class _DugmePrijave extends StatefulWidget {
  final bool ucitavanje;
  final VoidCallback onTap;

  const _DugmePrijave({required this.ucitavanje, required this.onTap});

  @override
  State<_DugmePrijave> createState() => _DugmePrijaveState();
}

class _DugmePrijaveState extends State<_DugmePrijave> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final aktivno = !widget.ucitavanje;
    return Semantics(
      button: true,
      enabled: aktivno,
      label: 'Prijavi se',
      child: MouseRegion(
        cursor: aktivno ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: aktivno ? widget.onTap : null,
          child: AnimatedContainer(
            duration: hoverTrajanje,
            curve: hoverKriva,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover && aktivno ? _akcentTamni : _akcent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x400F5C66),
                  blurRadius: _hover && aktivno ? 22 : 14,
                  offset: Offset(0, _hover && aktivno ? 10 : 6),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: hoverTrajanje,
              child: widget.ucitavanje
                  ? const SizedBox(
                      key: ValueKey('ucitavanje'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      key: const ValueKey('tekst'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Prijavi se',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSlide(
                          duration: hoverTrajanje,
                          curve: hoverKriva,
                          offset: _hover ? const Offset(0.2, 0) : Offset.zero,
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _krug(double velicina, double alfa) => Container(
  width: velicina,
  height: velicina,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: Colors.white.withValues(alpha: alfa),
  ),
);

// Lijevi panel na širokom ekranu.
class _Panel extends StatelessWidget {
  final double visina;

  const _Panel({required this.visina});

  @override
  Widget build(BuildContext context) {
    // Na niskom prozoru stavke se sakriju da sve stane bez skrolovanja.
    final saStavkama = visina >= 620;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradijent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(right: -120, top: -120, child: _krug(380, 0.07)),
          Positioned(left: -90, bottom: -140, child: _krug(320, 0.05)),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    LogoZnak(velicina: 52, naTamnom: true),
                    SizedBox(width: 14),
                    LogoNaziv(velicina: 20),
                  ],
                ),
                // Maskota zauzima slobodan prostor; na niskom prozoru nestaje.
                const Expanded(child: _Maskota()),
                const Text(
                  'Magacini, dokumenta i knjiženja na jednom mjestu.',
                  style: TextStyle(
                    fontSize: 34,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Pratite zalihe, kalkulacije i analitičke kartice artikala '
                  'za sve svoje firme.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                if (saStavkama) ...[
                  const SizedBox(height: 32),
                  const _Stavka(
                    ikona: Icons.inventory_2_rounded,
                    naslov: 'Stanje magacina',
                    opis: 'Repromaterijal, proizvodnja i gotovi proizvodi',
                  ),
                  const SizedBox(height: 14),
                  const _Stavka(
                    ikona: Icons.description_rounded,
                    naslov: 'Dokumenta',
                    opis: 'Kalkulacije, radni nalozi, trebovanja, otpremnice',
                  ),
                  const SizedBox(height: 14),
                  const _Stavka(
                    ikona: Icons.business_rounded,
                    naslov: 'Više firmi',
                    opis: 'Brz prelaz između firmi iz istog naloga',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Zec Kalkulino sa mint sjajem iza i oblačićem pozdrava.
class _Maskota extends StatelessWidget {
  const _Maskota();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxHeight < 150) return const SizedBox.shrink();
        final visina = (c.maxHeight - 24).clamp(0.0, 340.0);

        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: visina,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: visina * 0.9,
                      height: visina * 0.9,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x553FD0B4), Color(0x003FD0B4)],
                        ),
                      ),
                    ),
                    Image.asset(
                      zecCijeli,
                      height: visina,
                      filterQuality: FilterQuality.medium,
                    ),
                  ],
                ),
              ),
              if (c.maxWidth >= 300) ...[
                const SizedBox(width: 8),
                const Flexible(child: _Oblacic()),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Oblacic extends StatelessWidget {
  const _Oblacic();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
        ),
        border: Border.all(color: mint.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Zdravo, ja sam Kalkulino!',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: mint,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Prijavite se, brojke čekaju.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stavka extends StatelessWidget {
  final IconData ikona;
  final String naslov;
  final String opis;

  const _Stavka({
    required this.ikona,
    required this.naslov,
    required this.opis,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(ikona, color: mint, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  naslov,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  opis,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Zaglavlje u boji na uskom ekranu; forma ga djelimično preklapa.
class _UskoZaglavlje extends StatelessWidget {
  const _UskoZaglavlje();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradijent,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(right: -60, top: -70, child: _krug(220, 0.07)),
          Positioned(left: -50, bottom: -90, child: _krug(180, 0.05)),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 72),
              child: Column(
                children: [
                  const LogoZnak(velicina: 76, naTamnom: true),
                  const SizedBox(height: 14),
                  const LogoNaziv(velicina: 22),
                  const SizedBox(height: 4),
                  Text(
                    'Magacini, dokumenta i knjiženja',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
