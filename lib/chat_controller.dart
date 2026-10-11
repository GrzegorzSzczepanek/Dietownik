import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/chat_ai.dart';
import 'domain/models.dart';
import 'providers.dart';

/// What the chat may read. Everything is on by default; each source can be switched off.
class ChatPrefs {
  const ChatPrefs({this.today = true, this.history = true, this.goals = true, this.fridge = true, this.recipes = true, this.web = true});
  final bool today, history, goals, fridge, recipes, web;

  static const keys = ['chat_today', 'chat_history', 'chat_goals', 'chat_fridge', 'chat_recipes', 'chat_web'];

  List<bool> get all => [today, history, goals, fridge, recipes, web];

  /// Short label for the header link: "Dane: wszystko" / "Dane: 3 z 5" / "Dane: brak".
  String get summary {
    final n = [today, history, goals, fridge, recipes].where((e) => e).length;
    return n == 5 ? 'Dane: wszystko' : (n == 0 ? 'Dane: brak' : 'Dane: $n z 5');
  }

  ChatPrefs with_(int i, bool v) {
    final a = [...all]..[i] = v;
    return ChatPrefs(today: a[0], history: a[1], goals: a[2], fridge: a[3], recipes: a[4], web: a[5]);
  }
}

class ChatPrefsNotifier extends Notifier<ChatPrefs> {
  @override
  ChatPrefs build() {
    SharedPreferences.getInstance().then((p) {
      final v = [for (final k in ChatPrefs.keys) p.getBool(k) ?? true];
      state = ChatPrefs(today: v[0], history: v[1], goals: v[2], fridge: v[3], recipes: v[4], web: v[5]);
    });
    return const ChatPrefs();
  }

  Future<void> set(int i, bool v) async {
    state = state.with_(i, v);
    (await SharedPreferences.getInstance()).setBool(ChatPrefs.keys[i], v);
  }
}

final chatPrefsProvider = NotifierProvider<ChatPrefsNotifier, ChatPrefs>(ChatPrefsNotifier.new);

class ChatMsg {
  const ChatMsg({required this.id, required this.role, required this.text, this.reply});
  final int id;
  final String role; // user | assistant
  final String text;
  final ChatReply? reply;
}

class ChatState {
  const ChatState({this.messages = const [], this.busy = false, this.start = 0, this.loaded = false});
  final List<ChatMsg> messages;
  final bool busy, loaded;

  /// Index of the first message of the current conversation.
  final int start;
  List<ChatMsg> get current => messages.sublist(start);
  ChatState copyWith({List<ChatMsg>? messages, bool? busy, int? start, bool? loaded}) =>
      ChatState(messages: messages ?? this.messages, busy: busy ?? this.busy, start: start ?? this.start, loaded: loaded ?? this.loaded);
}

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    _load();
    return const ChatState();
  }

  Future<void> _load() async {
    final rows = await ref.read(dbProvider).chatRows();
    final msgs = <ChatMsg>[];
    for (final r in rows) {
      ChatReply? reply;
      if (r['role'] == 'assistant') {
        try {
          final m = jsonDecode('${r['meta']}') as Map;
          reply = ChatReply(
            answer: '${r['text']}',
            recipe: m['recipe'] is Map ? ChatRecipe.fromJson(m['recipe'] as Map) : null,
            suggestions: (m['suggestions'] as List? ?? const []).map((e) => '$e').toList(),
            used: (m['used'] as List? ?? const []).map((e) => '$e').toList(),
            sources: [for (final s in (m['sources'] as List? ?? const [])) ChatSource.fromJson(s as Map)],
            searched: m['searched'] == true,
          );
        } catch (_) {}
      }
      msgs.add(ChatMsg(id: r['id'] as int, role: '${r['role']}', text: '${r['text']}', reply: reply));
    }
    // Reopening the app starts a fresh conversation view; history stays stored.
    state = ChatState(messages: msgs, start: msgs.length, loaded: true);
  }

  void newConversation() => state = state.copyWith(start: state.messages.length);

  Future<void> clearAll() async {
    await ref.read(dbProvider).clearChat();
    state = const ChatState(loaded: true);
  }

  Future<String> _context(ChatPrefs p) async {
    final db = ref.read(dbProvider);
    final goals = ref.read(goalsProvider);
    final now = DateTime.now();
    final b = StringBuffer('Teraz: ${now.hour}:${now.minute.toString().padLeft(2, '0')}, ${dayKey(now)}.\n');
    String n(double v) => v.round().toString();
    if (p.goals) {
      b.writeln('CELE DZIENNE: ${n(goals.kcal)} kcal, białko ${n(goals.p)} g, węgle ${n(goals.c)} g, tłuszcz ${n(goals.f)} g.');
      final wk = await db.macrosByDay(dayKey(now.subtract(const Duration(days: 6))), dayKey(now));
      if (wk.isNotEmpty) {
        final avg = wk.values.fold(Macros.zero, (a, e) => a + e) * (1 / wk.length);
        b.writeln('ŚREDNIA z ${wk.length} dni z wpisami w ostatnim tygodniu: ${n(avg.kcal)} kcal, białko ${n(avg.p)} g.');
      }
      b.writeln('WODA dziś: ${await db.waterFor(dayKey(now))} ml.');
    }
    if (p.today) {
      final today = await db.entriesFor(dayKey(now));
      final t = today.fold(Macros.zero, (a, e) => a + e.macros);
      b.writeln('DZISIAJ ZJEDZONE: ${n(t.kcal)} kcal, białko ${n(t.p)} g, węgle ${n(t.c)} g, tłuszcz ${n(t.f)} g. Zostało: ${n(goals.kcal - t.kcal)} kcal, białka ${n(goals.p - t.p)} g.');
      if (today.isNotEmpty) b.writeln('Dziś jadł: ${today.map((e) => e.name).join(', ')}.');
    }
    if (p.history) {
      final since = dayKey(now.subtract(const Duration(days: 90)));
      final rows = await db.entriesSince(since);
      final byDay = <String, List<Entry>>{};
      for (final e in rows) {
        byDay.putIfAbsent(e.day, () => []).add(e);
      }
      final lines = <String>[
        for (final d in byDay.keys.toList().reversed)
          '$d: ${n(byDay[d]!.fold<double>(0, (a, e) => a + e.macros.kcal))} kcal (${byDay[d]!.map((e) => e.name).toSet().take(6).join(', ')})'
      ];
      var out = <String>[];
      var len = 0;
      for (final l in lines) {
        len += l.length;
        if (len > 5000) break; // newest first, cut the oldest
        out.add(l);
      }
      if (out.isNotEmpty) b.writeln('HISTORIA (ostatnie 90 dni, od najnowszych):\n${out.join('\n')}');
    }
    if (p.fridge) {
      final pantry = ref.read(pantryProvider);
      final shop = ref.read(shoppingProvider).where((e) => e.startsWith('0|')).map((e) => e.substring(2));
      if (pantry.isNotEmpty) b.writeln('LODÓWKA: ${pantry.join(', ')}.');
      if (shop.isNotEmpty) b.writeln('NA LIŚCIE ZAKUPÓW: ${shop.join(', ')}.');
    }
    if (p.recipes) {
      final rs = await db.recipes();
      if (rs.isNotEmpty) b.writeln('ZAPISANE PRZEPISY: ${rs.take(30).map((r) => '${r.title} (~${n(r.perServing.kcal)} kcal)').join('; ')}.');
    }
    return b.toString();
  }

  Future<void> send(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.busy) return;
    final db = ref.read(dbProvider);
    final uid = await db.addChat('user', q, '{}');
    state = state.copyWith(messages: [...state.messages, ChatMsg(id: uid, role: 'user', text: q)], busy: true);
    final prefs = ref.read(chatPrefsProvider);
    try {
      final ai = await ref.read(aiSettingsProvider.notifier).dietAi();
      final ChatReply reply;
      if (!ai.canChat) {
        reply = const ChatReply(answer: 'Do rozmowy potrzebuję AI. Wejdź w Ja → Dostawca API (np. DeepSeek) i wklej klucz. To zajmie minutę.');
      } else {
        final hist = [
          for (final m in state.current.reversed.skip(1).take(6).toList().reversed) {'role': m.role, 'text': m.text}
        ];
        reply = await ai.chat(question: q, history: hist, context: await _context(prefs), webSearch: prefs.web);
      }
      final aid = await db.addChat('assistant', reply.answer, encodeMeta(reply));
      state = state.copyWith(messages: [...state.messages, ChatMsg(id: aid, role: 'assistant', text: reply.answer, reply: reply)], busy: false);
    } catch (e) {
      final reply = ChatReply(answer: 'Nie udało się dostać odpowiedzi: $e');
      final aid = await db.addChat('assistant', reply.answer, encodeMeta(reply));
      state = state.copyWith(messages: [...state.messages, ChatMsg(id: aid, role: 'assistant', text: reply.answer, reply: reply)], busy: false);
    }
  }
}

final chatProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);
