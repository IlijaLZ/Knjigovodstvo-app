# Glasovne komande

Prečica **⌘⇧Space** (Ctrl+Shift+Space na Windowsu) ili klik na zeca → izgovori npr. „otvori mi sva trebovanja” → otvara se ekran. Ako je polje za unos u fokusu, diktira se u njega.

- `glasovne_komande.dart` — lista komandi (ključne riječi → ekran). Nova komanda = novi red u `glasovneKomande`.
- `glasovno_dugme.dart` — kontroler: prečica, slušanje (`speech_to_text`), komande i diktat.
- `diktat.dart` — obrada diktata: ispravke („1232 ne nego 1234”), brojevi riječima, „obriši”, „dalje”.
- `diktat_u_polje.dart` — upis u polje koje je u fokusu (radi na svim TextField-ovima).
- `zec_panel.dart` — zec Kalkulino u donjem desnom uglu koji sluša i odgovara (uvezan u `main.dart`).
- `analiticka_kartica_glasom.dart` — „analitička kartica brašna”: traži artikal na stanju i otvara njegovu karticu.
- `izvoz_glasom.dart` — čim u rečenici bilo gdje ima „excel”/„izvezi”: bez ekrana izvozi ekran koji je otvoren („izvezi u excel”), a sa ekranom ga otvori pa izveze („radne naloge u excel”, „napravi mi u excelu kupce”). Ide preko dugmeta „Excel” (`lib/izvoz/registar_izvoza.dart`), pa se otvara isti prozor „Sačuvaj kao”.

## Uklanjanje

1. Obrisati folder `lib/glasovne_komande/` i testove `test/glasovne_komande_test.dart`, `test/diktat_test.dart`, `test/diktat_u_polje_test.dart`, `test/glas_navigacija_test.dart`, `test/glas_precica_test.dart`, `test/izvoz_glasom_test.dart` (registar izvoza u `lib/izvoz/` može ostati).
2. U `lib/main.dart` obrisati import `zec_panel.dart` i liniju `builder: (context, child) => ZecSloj(child: child!),`.
3. `flutter pub remove speech_to_text`
4. Dozvole (opciono):
   - `ios/Runner/Info.plist`, `macos/Runner/Info.plist`: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`
   - `macos/Runner/*.entitlements`: `com.apple.security.device.audio-input`
   - `android/app/src/main/AndroidManifest.xml`: `RECORD_AUDIO` i `<intent>` za `RecognitionService`

## macOS: pokretanje iz VS Code-a / terminala

Kad je aplikacija pokrenuta sa `flutter run` ili F5 u VS Code-u, macOS dozvolu za mikrofon traži u ime VS Code-a i ugasi aplikaciju. Zato dugme tada samo javi poruku. Da glasovne komande rade (uz hot reload):

```bash
./tool/pokreni_macos.sh
```

Ili se otvori `build/macos/Build/Products/Debug/Kalkulino.app` dvoklikom.
Kod uklanjanja obrisati i `tool/pokreni_macos.sh`.
