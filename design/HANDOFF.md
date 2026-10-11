# Dietownik, przekazanie projektu do implementacji

Pliki `*.dc.html` w tym folderze to makiety 390x844 (telefon). Traktuj je jako wzorzec wyglądu i zachowania, nie jako kod do przepisania 1:1. Otwórz je w przeglądarce, linki między ekranami działają. `canvas.json` zawiera układ płótna i tytuły ekranów.

Zasada nadrzędna: funkcje aplikacji zostają. Zmienia się wygląd, przepływ i teksty. Ekrany oznaczone "NOWE" wymagają logiki, której jeszcze nie ma.

## Tokeny (zastąp lib/core/theme.dart)

Kolory:

| Rola | Wartość |
|---|---|
| tło strony | `#FFFFFF` |
| strefa hero (nagłówek) | `#E3EDE8` |
| tor paska | `#C5D9CF` |
| tekst | `#17201C` |
| tekst drugorzędny | `#566059`, `#3A463F` |
| linia | `#E1E6E3` |
| obrys przycisku | `#CBD3CE` |
| wypełnienie pola | `#EEF2EF` |
| akcent (primary) | `#1F5F4A`, ciemny tekst na nim `#12392C` |
| białko | `#2B4BC9` |
| węglowodany | `#B56A0A` |
| tłuszcz | `#B04A35` |
| ostrzeżenie (tekst) | `#8A4B06` |

Tryb ciemny (`Ciemny.dc.html`): tło `#0F1613`, hero `#1A2822`, linia `#263630`, akcent `#5CC3A0`, tekst `#EAF0EC`, drugorzędny `#B7C4BD`, makro `#8FA6FF`, `#F0B05A`, `#F08A73`.

Czcionki (dodaj do pubspec, bez Google Fonts w runtime): Bricolage Grotesque 700/800 do nagłówków i dużych liczb, Figtree 400 do 700 do reszty. Cyfry tabelaryczne (`FontFeature.tabularFigures()`). Usuń `mono()`, `monoFamily` i wszystkie nagłówki WIELKIMI LITERAMI.

Skala: hero liczba 72 px (Bricolage 800, odstęp liter -0.02em), druga liczba 56 px, tytuł ekranu 30 do 32 px, nagłówek sekcji 16 do 17 px (Figtree 700), treść 16 do 17 px, opis 14 px. Zdania z małej litery, bez CAPS.

Kształt: strefa hero ma zaokrąglony dół (32 px), przyciski główne 56 px wysokości i promień 16, pola 52 px i promień 14, chipy 48 px, cel dotyku zawsze minimum 48 px. Listy rozdzielane linią `#E1E6E3`, bez kart w kartach, bez cieni, bez gradientów, bez lewych kolorowych pasków, bez ikon emoji.

## Zasady UX (z briefu, nie łam)

- Zapis posiłku ma kosztować 1 do 2 dotknięć. Domyślna porcja pod plusem na liście.
- Zamiast okien potwierdzenia: akcja od razu i przycisk "Cofnij".
- Szacunki zawsze z `~`. AI nigdy nie udaje pewności. Przepis od AI jest oznaczony jako niezweryfikowany.
- Ton bez winy, np. "Każdy wpis się liczy", pusty dzień to pusty stan, a nie porażka.
- Jeden bohater na ekran (jedna duża liczba), reszta ma słabszą hierarchię.
- Stany puste, błędów i offline są zaprojektowane, nie domyślne.

## Dolna nawigacja (lib/features/shell.dart)

Wysokość 84 px: Dziś, Przepisy, środkowy duży przycisk mikrofonu (70 px, biała obwódka 6 px, wystaje 28 px w górę), Czat, Ja. Aktywna zakładka na zielono, waga 700. Skaner nie jest już pływającym przyciskiem: jest w rzędzie akcji na Dziś, w nagłówku Przepisów i jako "Zeskanuj kod" w Szukaj. Zakładka Porady zmienia nazwę na Czat.

## Mapa ekranów do kodu

| Plik makiety | Ekran | Obecny plik w lib/ |
|---|---|---|
| Main, Dzis-pusty, Dzis-przewiniete | Dziś | features/today_screen.dart |
| Mikrofon-slucham, Mikrofon-wynik | arkusz głosowy | features/voice_sheet.dart, dictation.dart |
| Szukaj | wyszukiwarka jedzenia | features/food_search_screen.dart |
| Skaner | skaner kodów i etykiet | features/scan_screen.dart, label_flow.dart |
| Przepisy | lista i import | features/recipes_screen.dart |
| Lodowka | co mam w lodówce | features/fridge_screen.dart |
| Zakupy | lista zakupów | features/shopping_screen.dart |
| Statystyki | statystyki, 7 dni | features/week_screen.dart |
| Porady, Czat-rozmowa, Czat-zrodla | czat (zastępuje Porady) | features/advice_screen.dart |
| Ja | ustawienia i cele | features/settings_screen.dart, weight_screen.dart |
| Start-1, Start-2, Start-3 | NOWE: onboarding | nowy plik features/onboarding/ |
| Oko | NOWE: wpis na oko | nowy ekran, zapis wpisu bez produktu |
| Edycja-wpisu, Korekta-produktu | NOWE: edycja wpisu i produktu | arkusz z today_screen.dart |
| Nie-licze | NOWE: dzień bez liczenia | flaga dnia w db.dart |
| Porcje | NOWE: porcje i meal prep | recipes_screen.dart |
| Offline, Blad-ai | NOWE: stany błędów | wspólny widget błędu w common.dart |
| Zuzycie | NOWE: zużycie AI | licznik tokenów w ai/llm_api.dart |
| Czat-prywatnosc, Czat-dane | NOWE: dane dostępne dla czatu | ai_settings.dart i diet_ai.dart |
| Ciemny | tryb ciemny | ThemeData dark |
| Widget | widget ekranu głównego | osobny etap, natywny widget Androida |

## Nowa logika do dopisania

- Kalkulator celu (Mifflin-St Jeor) w kroku "Policz z moich danych" na onboardingu, makro liczone z kalorii automatycznie.
- Czat z wyszukiwaniem w sieci i cytowaniem źródeł (`services/web_search.dart` już istnieje). Odpowiedź ma mieć numerowane odnośniki [1][2] i listę źródeł. Czat dostaje kontekst z bazy (bilans, historia 90 dni, cele, lodówka, zakupy, przepisy) zgodnie z przełącznikami w "Czat-prywatnosc".
- Przepis od czatu: karta z `~` kcal i makro, przyciski "Zjadłem" i "Zapisz przepis", brakujące składniki idą do zakupów jednym dotknięciem.
- Flaga "dziś nie liczę" nie wlicza dnia do średnich i serii, wpisy zostają w historii.
- Skalowanie porcji przepisu i zapis "ugotowałem N porcji, zjadam 1".
- Korekta produktu zapisuje własne wartości na 100 g i działa od teraz.
- Szacunkowy licznik kosztu AI z limitem miesięcznym (kwoty w makietach są przykładowe).

## Uwagi

Domeny, przepisy, kwoty i liczby w makietach są wymyślone, to przykłady. Makiety mają polskie teksty, które warto przenieść do `core/localization.dart`.

## Sugerowana kolejność

1. Tokeny i czcionki w ThemeData (jasny i ciemny), wspólny motyw przycisków, pól i chipów.
2. Shell i dolna nawigacja.
3. Dziś (3 warianty), arkusz głosowy, Szukaj, Skaner.
4. Przepisy, Lodówka, Zakupy, Statystyki, Ja.
5. Czat (start, rozmowa, źródła, dostęp do danych).
6. Nowe ekrany: onboarding, wpis na oko, edycja, dzień bez liczenia, porcje, stany błędów, zużycie AI.
7. Widget ekranu głównego.

Po każdym ekranie uruchom aplikację, porównaj z makietą i zrób osobny commit.
