# Dietownik — brief dla projektanta (Claude Design)

Android, Flutter, język polski. Dziennik diety w stylu Fitatu, ale zbudowany pod
**lenistwo i ADHD**: jak najmniej tapnięć, zero poczucia winy, wszystko w jednym miejscu.

## Cel produktu
Użytkownik ma **nie odkładać aplikacji na bok**. Dlatego:
1. Dodanie posiłku ma zajmować kilka sekund (głos, skan, jeden tap na „zwykle jem").
2. Aplikacja nigdy nie karze za dziurę w logu ani za przekroczenie kalorii.
3. Tracking, przepisy, zakupy i porady są w jednym miejscu.
4. Wszystko poprawialne po fakcie, więc wpis nie wymaga perfekcji.

## Tożsamość wizualna (obecnie)
- Jasne, ciepłe tło `#F3F2EE`, białe karty z dużym zaokrągleniem (24 px), zieleń główna `#1F5F4A`.
- Akcenty: bursztyn `#C4780E` (ostrzeżenia, „ponad"), niebieski `#2B4BC9` (białko, woda).
- Liczby (kcal) w czcionce monospace. Nagłówki grube (w800).
- Przejęte z aplikacji „rachunkownik", do zmiany i dopracowania.

## Nawigacja
Dolny pasek: **Dziś · Przepisy · [duży mikrofon w środku] · Porady · Ja**.
Mały biały przycisk **skanera** w lewym dolnym rogu, widoczny na każdej zakładce
(obecnie zasłania kółko poniedziałku w pasku 7 dni — do poprawy).

## Ekrany i funkcje

### Dziś (ekran główny)
- Przełącznik dnia (‹ ›), dotknięcie tytułu wraca do dziś.
- Karta podsumowania: pierścień „zostało X kcal" + paski białko/węgle/tłuszcz.
- Opcjonalna linia „Tydzień: zostało X kcal, ok. Y na dzień" (tryb celu tygodniowego).
- Wiersz wody: pasek, +250 ml, cofnij (cel 2000 ml).
- Trzy szybkie akcje: **Skanuj · Szukaj · Co zjeść?**
- „Zwykle jesz — jeden tap": chipsy z najczęstszymi posiłkami, tap dodaje wpis.
- Pusty stan: zachęta do mikrofonu + „Powtórz poprzedni dzień".
- Posiłki (Śniadanie/Obiad/Kolacja/Przekąska, przypisywane automatycznie wg godziny),
  wpisy z gramami i makro, `~` przy wartościach szacunkowych, przesunięcie = usuń z „Cofnij",
  tap = zmiana gramów. Ikona zakładki przy posiłku = „zapisz jako zestaw".
- Pasek ostatnich 7 dni (✓ / – dla dni z wpisem, bez karania), tap → statystyki.

### Mikrofon (arkusz od dołu)
- Duży przycisk; mówisz „dwa jajka, kanapka z serem i kawa", wpis zapisuje się od razu.
- Stany: słucham (transkrypt na żywo) → liczę → podsumowanie z „Cofnij / Dodaj jeszcze / Gotowe".
- Tryb tekstowy jako alternatywa. Komunikat, gdy brakuje wartości dla produktu.
- Polecenia zakupowe: „zakupy jajka, ser, masło" dodaje do listy zakupów zamiast do dziennika.
- Nazwa zapisanego zestawu („śniadanie") dodaje cały zestaw.

### Skaner (pełny ekran, działa od razu)
- Kamera z ramką, latarka, skanowanie ciągłe (licznik dodanych w tytule).
- Po kodzie: karta produktu (makro, skład) z akcjami: **Zjadłem / Do koszyka / Skanuj dalej**.
- Gdy kodu nie ma w bazie lub nie ma kodu: **zdjęcie etykiety, AI odczytuje** nazwę, makro i skład,
  użytkownik poprawia i zapisuje (produkt zapamiętany pod kodem).

### Szukaj / dodawanie produktu
- Wyszukiwarka: własna baza, ok. 8000 popularnych polskich produktów offline,
  Open Food Facts na żywo, ok. 260 produktów podstawowych i sieciówek.
- Opcje: szacowanie AI, zdjęcie etykiety, własny produkt (makro, porcja, skład).
- Okno podania gramów z przeliczeniem na żywo i skrótem „1 porcja".

### Przepisy
- Lista z kcal/porcję, ulubione na górze.
- Dodawanie: **z linku** (import ze stron przepisów), **własny**, **pomysł AI**.
- Edytor: nazwa, porcje, makro/porcję, „Policz makro (AI)", składniki, kroki, źródło,
  „Składniki do listy zakupów", **„Zjadłem porcję"**.
- **Co mam w lodówce:** użytkownik wpisuje składniki, aplikacja szuka **prawdziwych przepisów**
  w sieci i pokazuje **% zgodności** (liczony kodem, nie przez AI), „masz X z Y",
  listę brakujących i przycisk „Brakujące do zakupów". Przepisy AI mają znacznik „nieweryfikowane".
- **Zakupy:** lista z odhaczaniem, dodawanie tekstem lub głosem (wiele pozycji naraz),
  „Usuń kupione".

### Porady
- Pole pytania do AI (z kontekstem dnia: ile zostało kcal i białka), gotowe podpowiedzi
  („Co zjeść teraz?", „Podsumuj mój tydzień" itd.).
- Karty z krótkimi zasadami dla leniwego mózgu (offline).

### Ja (ustawienia)
- Cele dzienne (kalkulator Mifflin-St Jeor, cele makro), przełącznik celu tygodniowego.
- **Waga i trend:** wykres, zmiana z 14 dni, lista pomiarów.
- **Przypomnienia o posiłkach:** 3 godziny, tylko gdy posiłku jeszcze nie ma w logu.
- AI: wybór lokalnie/API dla każdego zadania, modele lokalne (pobierane), dostawca API.
- Import produktów z CSV, kopia zapasowa i przywracanie (JSON), informacja o źródłach danych.

### Statystyki (7 dni)
Wykres słupkowy kalorii z linią celu, średnie makro, liczba dni z wpisem.

## Zasady UX do zachowania
- Maksymalnie 1–2 tapnięcia do dodania jedzenia.
- Zawsze „Cofnij" zamiast pytań „czy na pewno".
- Wartości szacunkowe zawsze oznaczone `~`; AI nigdy nie udaje pewności.
- Język łagodny, bez wyrzutów („Każdy wpis się liczy").
- Duże pola dotyku (min. 48 px), czytelne kontrasty, jedna główna akcja na ekran.

## Znane braki / pomysły
Widget na pulpit, zdjęcie talerza, skan paragonu, leki i suplementy, alerty alergenów,
błonnik/cukier/sól, automatyczna kopia w chmurze, tryb ciemny, ikona i ekran powitalny,
wersja angielska, wersja release z własnym podpisem.

## Problemy wizualne do naprawienia (widoczne na emulatorze)
- Przycisk skanera nachodzi na pierwszy dzień paska 7 dni.
- Domyślna ikona i ekran startowy Fluttera.
- Hierarchia ekranu Dziś jest gęsta: rozważyć, co zostaje nad linią zgięcia.
