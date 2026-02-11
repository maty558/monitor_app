import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String serverUrl = 'http://192.168.100.2:3000';

void main() {
  runApp(MonitorApp());
}

class MonitorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web Monitor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Color(0xFF1a1a2e),
      ),
      home: StartScreen(),
    );
  }
}

// ═══════════════════════════════════════════
// 🔐 PRIHLÁSENIE / REGISTRÁCIA
// ═══════════════════════════════════════════
class StartScreen extends StatefulWidget {
  @override
  _StartScreenState createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _nacitavam = true;

  @override
  void initState() {
    super.initState();
    _skontrolujPrihlasenie();
  }

  Future<void> _skontrolujPrihlasenie() async {
    final prefs = await SharedPreferences.getInstance();
    final odlozeneId = prefs.getInt('uzivatel_id');
    final odlozenyEmail = prefs.getString('email');

    if (odlozeneId != null && odlozenyEmail != null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MonitorScreen(
            uzivatelId: odlozeneId,
            email: odlozenyEmail,
          ),
        ),
      );
    } else {
      setState(() => _nacitavam = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_nacitavam) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final emailController = TextEditingController();
    String chyba = '';

    return Scaffold(
      body: StatefulBuilder(
        builder: (context, setLocalState) => Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🌐 Web Monitor',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('Zadaj email pre prihlásenie',
                    style: TextStyle(color: Colors.grey)),
                SizedBox(height: 24),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: '📧 Email',
                    labelStyle: TextStyle(color: Colors.grey),
                    hintText: 'moj@email.com',
                    hintStyle: TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue)),
                  ),
                ),
                if (chyba.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Text(chyba, style: TextStyle(color: Colors.red)),
                ],
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final email = emailController.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        setLocalState(() => chyba = 'Zadaj platný email!');
                        return;
                      }
                      try {
                        final odpoved = await http.post(
                          Uri.parse('$serverUrl/api/registracia'),
                          headers: {'Content-Type': 'application/json'},
                          body: json.encode({'email': email}),
                        );
                        final data = json.decode(odpoved.body);
                        if (data['ok'] == true) {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt('uzivatel_id', data['uzivatel_id']);
                          await prefs.setString('email', email);
                          if (!mounted) return;
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => MonitorScreen(
                                uzivatelId: data['uzivatel_id'],
                                email: email,
                              ),
                            ),
                          );
                        } else {
                          setLocalState(
                              () => chyba = data['chyba'] ?? 'Chyba!');
                        }
                      } catch (e) {
                        setLocalState(() =>
                            chyba = 'Nedá sa pripojiť k serveru!');
                      }
                    },
                    child: Text('Prihlásiť sa',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// 📊 HLAVNÁ OBRAZOVKA
// ═══════════════════════════════════════════
class MonitorScreen extends StatefulWidget {
  final int uzivatelId;
  final String email;

  MonitorScreen({required this.uzivatelId, required this.email});

  @override
  _MonitorScreenState createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  List<dynamic> monitory = [];
  String chyba = '';
  Timer? timer;
  Set<int> notifikovane = {};
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    _initPlayer();
    nacitajData();
    timer = Timer.periodic(Duration(seconds: 10), (t) => nacitajData());
  }

  Future<void> _initPlayer() async {
    _player = AudioPlayer();
    await _player!.setSource(AssetSource('alarm.mp3'));
  }

  @override
  void dispose() {
    timer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> nacitajData() async {
    try {
      final odpoved = await http.get(
        Uri.parse('$serverUrl/api/monitory/${widget.uzivatelId}'),
      );
      setState(() {
        monitory = json.decode(odpoved.body);
        chyba = '';
      });

      for (var m in monitory) {
        int id = m['id'] ?? 0;
        String stav = m['stav'] ?? '';

        if (stav.contains('❌') && !notifikovane.contains(id)) {
          notifikovane.add(id);
          zobrazNotifikaciu(m['stranka'] ?? '');
        }
        if (stav.contains('✅')) {
          notifikovane.remove(id);
        }
      }
    } catch (e) {
      setState(() {
        chyba = 'Nedá sa pripojiť k serveru!';
      });
    }
  }

  void zobrazNotifikaciu(String stranka) {
    _player?.stop();
    _player?.play(AssetSource('alarm.mp3'));

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF16213e),
        title: Text('🚨 ALARM!',
            style: TextStyle(color: Colors.red, fontSize: 24)),
        content: Text('$stranka – text nenájdený!',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () {
              _player?.stop();
              Navigator.of(ctx).pop();
            },
            child: Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void zobrazPridajDialog() {
    final strankaCtrl = TextEditingController();
    final slovaCtrl = TextEditingController();
    final cenaOdCtrl = TextEditingController();
    final cenaDoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF16213e),
        title:
            Text('➕ Nový monitoring', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _textField(strankaCtrl, '🌐 URL stránky', 'https://example.com'),
              SizedBox(height: 12),
              _textField(slovaCtrl, '🔍 Kľúčové slová', 'slovo1, slovo2'),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _textField(cenaOdCtrl, '💰 Cena od', '0',
                        keyboard: TextInputType.number),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _textField(cenaDoCtrl, '💰 Cena do', '100',
                        keyboard: TextInputType.number),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text('Ceny sú voliteľné',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Zrušiť', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              if (strankaCtrl.text.isEmpty || slovaCtrl.text.isEmpty) return;

              final body = {
                'uzivatel_id': widget.uzivatelId,
                'stranka': strankaCtrl.text,
                'klucove_slova': slovaCtrl.text,
              };
              if (cenaOdCtrl.text.isNotEmpty) {
                body['cena_od'] = double.tryParse(cenaOdCtrl.text) ?? 0;
              }
              if (cenaDoCtrl.text.isNotEmpty) {
                body['cena_do'] = double.tryParse(cenaDoCtrl.text) ?? 0;
              }

              await http.post(
                Uri.parse('$serverUrl/api/pridaj'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(body),
              );
              Navigator.of(ctx).pop();
              nacitajData();
            },
            child: Text('Pridať'),
          ),
        ],
      ),
    );
  }

  void zobrazZmazDialog(int monitorId, String stranka) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF16213e),
        title: Text('🗑️ Zmazať?', style: TextStyle(color: Colors.white)),
        content: Text('Naozaj chceš zmazať\n$stranka?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Nie', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await http.delete(
                Uri.parse('$serverUrl/api/zmaz/$monitorId'),
              );
              Navigator.of(ctx).pop();
              nacitajData();
            },
            child: Text('Zmazať'),
          ),
        ],
      ),
    );
  }

  Future<void> toggleMonitor(int monitorId) async {
    await http.put(Uri.parse('$serverUrl/api/toggle/$monitorId'));
    nacitajData();
  }

  void zobrazHistoriu(int monitorId, String stranka) async {
    try {
      final odpoved = await http.get(
        Uri.parse('$serverUrl/api/historia/$monitorId'),
      );
      final historia = json.decode(odpoved.body) as List;

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Color(0xFF16213e),
          title: Text('📜 História: $stranka',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: historia.isEmpty
                ? Center(
                    child: Text('Žiadna história',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: historia.length,
                    itemBuilder: (_, i) {
                      final h = historia[i];
                      final cena = h['najdena_cena'];
                      return ListTile(
                        dense: true,
                        title: Text(h['najdeny_text'] ?? '',
                            style: TextStyle(fontSize: 13)),
                        subtitle: Text(h['cas'] ?? '',
                            style:
                                TextStyle(color: Colors.grey, fontSize: 11)),
                        trailing: cena != null
                            ? Text('${cena}€',
                                style: TextStyle(
                                    color: Colors.green, fontSize: 13))
                            : null,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Zavrieť', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> _odhlasit() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => StartScreen()),
    );
  }

  Color getStavColor(String stav) {
    if (stav.contains('✅')) return Colors.green;
    if (stav.contains('❌')) return Colors.red;
    return Colors.orange;
  }

  Widget _textField(TextEditingController ctrl, String label, String hint,
      {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      style: TextStyle(color: Colors.white),
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey),
        enabledBorder:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
        focusedBorder:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int najdene =
        monitory.where((m) => (m['stav'] ?? '').contains('✅')).length;
    int nenajdene =
        monitory.where((m) => (m['stav'] ?? '').contains('❌')).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('🌐 Web Monitor'),
        centerTitle: true,
        backgroundColor: Color(0xFF16213e),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.grey),
            onPressed: _odhlasit,
            tooltip: 'Odhlásiť sa',
          ),
        ],
      ),
      body: Column(
        children: [
          // Email info
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('📧 ${widget.email}',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),

          // Štatistiky
          Container(
            padding: EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statCard('📊 Celkom', '${monitory.length}', Colors.blue),
                _statCard('✅ Nájdené', '$najdene', Colors.green),
                _statCard('❌ Nenájdené', '$nenajdene', Colors.red),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('🔄 Automatická obnova každých 10s',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),

          if (chyba.isNotEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('🚨 $chyba',
                  style: TextStyle(color: Colors.red, fontSize: 18)),
            ),

          Expanded(
            child: ListView.builder(
              itemCount: monitory.length,
              itemBuilder: (context, index) {
                final m = monitory[index];
                String stav = m['stav'] ?? '⏳';
                int monitorId = m['id'] ?? 0;
                bool aktivny = (m['aktivny'] ?? 1) == 1;
                String klucoveSlova = m['klucove_slova'] ?? '';
                double? cenaOd = m['cena_od'] != null
                    ? (m['cena_od'] as num).toDouble()
                    : null;
                double? cenaDo = m['cena_do'] != null
                    ? (m['cena_do'] as num).toDouble()
                    : null;

                return GestureDetector(
                  onLongPress: () =>
                      zobrazZmazDialog(monitorId, m['stranka'] ?? ''),
                  onDoubleTap: () =>
                      zobrazHistoriu(monitorId, m['stranka'] ?? ''),
                  child: Opacity(
                    opacity: aktivny ? 1.0 : 0.5,
                    child: Card(
                      margin:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      color: Color(0xFF16213e),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: getStavColor(stav).withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m['stranka'] ?? '',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => toggleMonitor(monitorId),
                                  child: Icon(
                                    aktivny
                                        ? Icons.pause_circle
                                        : Icons.play_circle,
                                    color:
                                        aktivny ? Colors.orange : Colors.green,
                                    size: 28,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            Text('🔍 $klucoveSlova',
                                style: TextStyle(fontSize: 13)),
                            if (cenaOd != null || cenaDo != null)
                              Text(
                                  '💰 ${cenaOd ?? "?"} – ${cenaDo ?? "?"} €',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.amber)),
                            SizedBox(height: 4),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    '🕐 ${m['posledna_kontrola'] ?? '-'}',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 11)),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        getStavColor(stav).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(stav,
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'refresh',
            onPressed: nacitajData,
            backgroundColor: Color(0xFF0f3460),
            child: Icon(Icons.refresh),
          ),
          SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: zobrazPridajDialog,
            backgroundColor: Colors.green,
            child: Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}
