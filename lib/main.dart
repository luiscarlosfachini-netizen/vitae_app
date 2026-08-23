import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }
  runApp(const VitaeApp());
}

class VitaeApp extends StatelessWidget {
  const VitaeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vitae',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101921),
        primaryColor: Colors.tealAccent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.orangeAccent,
          surface: Color(0xFF1A2632),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // Diário
  String userName = "Usuário";
  double weightCurrent = 0.0;
  double weightTarget = 0.0;
  double weightStart = 0.0;
  double heightCm = 0.0;
  DateTime? startDate;
  DateTime? targetDate;
  List<Map<String, dynamic>> weightHistory = [];

  // Jejum
  List<Map<String, dynamic>> fastingHistory = [];

  // Corrida
  List<Map<String, dynamic>> runHistory = [];
  bool isRunning = false;
  Timer? runTimer;
  StreamSubscription<Position>? positionStreamSubscription;
  int runSeconds = 0;
  double runDistanceKm = 0.0;
  double runTargetDistance = 5.0;
  Position? lastPosition;
  DateTime? runStartTime;

  // Medidas
  Map<String, bool> enabledMeasurements = {
    'arm': true,
    'belly': true,
    'waist': true,
    'hip': true,
    'thigh': true,
  };
  List<Map<String, dynamic>> measurementsHistory = [];

  // Dieta
  List<Map<String, dynamic>> fixedMeals = [];
  List<Map<String, dynamic>> dietMeals = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadRunState();
  }

  Future<void> _requestPermissions() async {
    if (!kIsWeb) {
      await [
        Permission.location,
        Permission.notification,
      ].request();
    }
  }

  Future<void> _loadRunState() async {
    final prefs = await SharedPreferences.getInstance();
    final startTimeStr = prefs.getString('run_start_time');
    final savedDistance = prefs.getDouble('run_distance') ?? 0.0;

    if (startTimeStr != null) {
      final startTime = DateTime.parse(startTimeStr);
      final diff = DateTime.now().difference(startTime).inSeconds;

      setState(() {
        isRunning = true;
        runStartTime = startTime;
        runSeconds = diff;
        runDistanceKm = savedDistance;
      });

      _startRunTracking();
    }
  }

  void _startRunTracking() {
    runTimer?.cancel();
    runTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (runStartTime != null) {
        setState(() {
          runSeconds = DateTime.now().difference(runStartTime!).inSeconds;
        });
        _showRunNotification();
      }
    });

    if (!kIsWeb) {
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );

      positionStreamSubscription?.cancel();
      positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) async {
        if (pos.accuracy > 15.0) return;

        if (lastPosition != null) {
          double meters = Geolocator.distanceBetween(
            lastPosition!.latitude, lastPosition!.longitude,
            pos.latitude, pos.longitude,
          );

          if (meters >= 5.0 && meters < 100.0) {
            setState(() {
              runDistanceKm += meters / 1000.0;
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('run_distance', runDistanceKm);
          }
        }
        lastPosition = pos;
      });
    }
  }

  Future<void> _showRunNotification() async {
    if (kIsWeb) return;
    int h = runSeconds ~/ 3600;
    int m = (runSeconds % 3600) ~/ 60;
    int s = runSeconds % 60;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'run_channel',
      'Corrida em Andamento',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      999,
      'Vitae - Corrida em Andamento',
      'Distância: ${runDistanceKm.toStringAsFixed(2)} km | Tempo: ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
      details,
    );
  }

  void toggleRun() async {
    final prefs = await SharedPreferences.getInstance();

    if (isRunning) {
      runTimer?.cancel();
      positionStreamSubscription?.cancel();
      if (!kIsWeb) await flutterLocalNotificationsPlugin.cancel(999);

      double paceMinutes = runDistanceKm > 0 ? (runSeconds / 60) / runDistanceKm : 0.0;
      int pMin = paceMinutes.toInt();
      int pSec = ((paceMinutes - pMin) * 60).toInt();
      int calories = (runDistanceKm * 65).toInt();

      final now = DateTime.now();
      setState(() {
        runHistory.insert(0, {
          'id': DateTime.now().millisecondsSinceEpoch,
          'date': '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
          'distance': '${runDistanceKm.toStringAsFixed(2)} km',
          'time': '${runSeconds ~/ 3600}h ${(runSeconds % 3600) ~/ 60}m ${runSeconds % 60}s',
          'pace': '$pMin:${pSec.toString().padLeft(2, '0')} /km',
          'calories': '$calories kcal',
        });
        isRunning = false;
        runSeconds = 0;
        runDistanceKm = 0.0;
        lastPosition = null;
        runStartTime = null;
      });

      await prefs.remove('run_start_time');
      await prefs.remove('run_distance');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Corrida salva no histórico!')),
        );
      }
    } else {
      if (!kIsWeb) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
      }

      final now = DateTime.now();
      await prefs.setString('run_start_time', now.toIso8601String());
      await prefs.setDouble('run_distance', 0.0);

      setState(() {
        isRunning = true;
        runStartTime = now;
        runSeconds = 0;
        runDistanceKm = 0.0;
        lastPosition = null;
      });

      _startRunTracking();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      FastingTab(
        history: fastingHistory,
        onFinishFasting: (entry) {
          setState(() => fastingHistory.insert(0, entry));
        },
        onDeleteFasting: (id) {
          setState(() => fastingHistory.removeWhere((item) => item['id'] == id));
        },
        onAddManualFasting: (entry) {
          setState(() => fastingHistory.insert(0, entry));
        },
      ),
      DiaryTab(
        userName: userName,
        weightCurrent: weightCurrent,
        weightTarget: weightTarget,
        weightStart: weightStart,
        targetDate: targetDate,
        startDate: startDate,
        heightCm: heightCm,
        weightHistory: weightHistory,
        onProfileUpdate: (name, startWeight, cur, tar, height, sDate, tDate) {
          setState(() {
            userName = name;
            weightStart = startWeight;
            weightCurrent = cur;
            weightTarget = tar;
            heightCm = height;
            startDate = sDate;
            targetDate = tDate;
          });
        },
        onDeleteWeight: (id) {
          setState(() => weightHistory.removeWhere((item) => item['id'] == id));
        },
        onAddWeight: (newWeight) {
          final now = DateTime.now();
          setState(() {
            weightCurrent = newWeight;
            weightHistory.insert(0, {
              'id': DateTime.now().millisecondsSinceEpoch,
              'date': '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
              'weight': newWeight
            });
          });
        },
      ),
      RunTab(
        history: runHistory,
        isRunning: isRunning,
        seconds: runSeconds,
        distanceKm: runDistanceKm,
        targetDistance: runTargetDistance,
        onToggleRun: toggleRun,
        onUpdateTarget: (newTarget) => setState(() => runTargetDistance = newTarget),
        onDeleteRun: (id) {
          setState(() => runHistory.removeWhere((item) => item['id'] == id));
        },
      ),
      MeasurementsTab(
        enabledMeasurements: enabledMeasurements,
        history: measurementsHistory,
        onUpdateConfig: (newConfig) {
          setState(() {
            enabledMeasurements = newConfig;
          });
        },
        onAddMeasurement: (entry) {
          setState(() {
            measurementsHistory.insert(0, entry);
          });
        },
        onDeleteMeasurement: (id) {
          setState(() {
            measurementsHistory.removeWhere((item) => item['id'] == id);
          });
        },
      ),
      DietTab(
        fixedMeals: fixedMeals,
        meals: dietMeals,
        onAddFixedMeal: (meal) {
          setState(() {
            fixedMeals.add(meal);
          });
        },
        onDeleteFixedMeal: (id) {
          setState(() {
            fixedMeals.removeWhere((m) => m['id'] == id);
          });
        },
        onAddMeal: (meal) {
          setState(() {
            dietMeals.add(meal);
          });
        },
        onToggleMealDone: (id) {
          setState(() {
            final meal = dietMeals.firstWhere((m) => m['id'] == id);
            meal['done'] = !(meal['done'] ?? false);
          });
        },
        onDeleteMeal: (id) {
          setState(() {
            dietMeals.removeWhere((m) => m['id'] == id);
          });
        },
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        selectedItemColor: Colors.tealAccent,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF0D141C),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.timer), label: 'Jejum'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Diário'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_run), label: 'Corrida'),
          BottomNavigationBarItem(icon: Icon(Icons.straighten), label: 'Medidas'),
          BottomNavigationBarItem(icon: Icon(Icons.restaurant_menu), label: 'Dieta'),
        ],
      ),
    );
  }
}

class FastingTab extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  final Function(Map<String, dynamic>) onFinishFasting;
  final Function(int) onDeleteFasting;
  final Function(Map<String, dynamic>) onAddManualFasting;

  const FastingTab({
    super.key,
    required this.history,
    required this.onFinishFasting,
    required this.onDeleteFasting,
    required this.onAddManualFasting,
  });

  @override
  State<FastingTab> createState() => _FastingTabState();
}

class _FastingTabState extends State<FastingTab> {
  bool _isFasting = false;
  int _targetHours = 16;
  Timer? _timer;
  int _elapsedSeconds = 0;
  DateTime? _fastingStartTime;

  final List<Map<String, String>> _allPhases = [
    {'range': '0h - 2h', 'title': 'Digestão Ativa', 'desc': 'O corpo digere os alimentos. A glicose e a insulina sobem.'},
    {'range': '2h - 8h', 'title': 'Estabilização de Glicemia', 'desc': 'Insulina cai. O corpo usa o glicogênio armazenado.'},
    {'range': '8h - 12h', 'title': 'Transição & Queima de Gordura', 'desc': 'Glicogênio esgotando. Ativação da queima de gordura.'},
    {'range': '12h - 18h', 'title': 'Cetose & Autofagia Inicial', 'desc': 'Gordura vira cetonas. Início da renovação celular.'},
    {'range': '18h+', 'title': 'Autofagia Profunda & HGH', 'desc': 'Limpeza celular maximizada e elevação do HGH.'},
  ];

  @override
  void initState() {
    super.initState();
    _loadFastingState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadFastingState() async {
    final prefs = await SharedPreferences.getInstance();
    final startTimeStr = prefs.getString('fasting_start_time');
    final target = prefs.getInt('fasting_target') ?? 16;

    if (startTimeStr != null) {
      final startTime = DateTime.tryParse(startTimeStr);
      if (startTime != null) {
        final diff = DateTime.now().difference(startTime).inSeconds;
        if (mounted) {
          setState(() {
            _isFasting = true;
            _fastingStartTime = startTime;
            _targetHours = target;
            _elapsedSeconds = diff > 0 ? diff : 0;
          });
          _startTimer();
        }
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_fastingStartTime != null && mounted) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(_fastingStartTime!).inSeconds;
        });
        _showNotification();
      }
    });
  }

  Future<void> _showNotification() async {
    if (kIsWeb || !_isFasting) return;
    int h = _elapsedSeconds ~/ 3600;
    int m = (_elapsedSeconds % 3600) ~/ 60;
    int s = _elapsedSeconds % 60;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'fasting_channel',
      'Jejum em Andamento',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      888,
      'Vitae - Jejum em Andamento',
      'Tempo: ${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s (Meta: ${_targetHours}h)',
      details,
    );
  }

  Future<void> _toggleFasting() async {
    if (_isFasting) {
      // Interrompe temporizador imediatamente para não recarregar
      _timer?.cancel();
      _timer = null;

      if (!kIsWeb) {
        await flutterLocalNotificationsPlugin.cancel(888);
      }

      int currentElapsed = _elapsedSeconds;
      int hrs = currentElapsed ~/ 3600;
      int mins = (currentElapsed % 3600) ~/ 60;
      final now = DateTime.now();

      // Grava no histórico
      widget.onFinishFasting({
        'id': DateTime.now().millisecondsSinceEpoch,
        'date': '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
        'duration': '${hrs}h ${mins}m',
        'target': '${_targetHours}h',
      });

      // Atualiza interface imediatamente
      setState(() {
        _isFasting = false;
        _elapsedSeconds = 0;
        _fastingStartTime = null;
      });

      // Remove dados salvos
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fasting_start_time');
      await prefs.remove('fasting_target');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jejum encerrado e registrado!')),
        );
      }
    } else {
      final now = DateTime.now();

      setState(() {
        _isFasting = true;
        _fastingStartTime = now;
        _elapsedSeconds = 0;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fasting_start_time', now.toIso8601String());
      await prefs.setInt('fasting_target', _targetHours);

      _startTimer();
    }
  }

  void _showAddManualDialog() {
    final dateCtrl = TextEditingController(
      text: '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}'
    );
    final hoursCtrl = TextEditingController(text: '16');
    final minutesCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Adicionar Jejum Manual"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateCtrl,
                decoration: const InputDecoration(labelText: "Data (DD/MM/AAAA)"),
              ),
              TextField(
                controller: hoursCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Horas de Jejum"),
              ),
              TextField(
                controller: minutesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Minutos de Jejum"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              int h = int.tryParse(hoursCtrl.text) ?? 0;
              int m = int.tryParse(minutesCtrl.text) ?? 0;
              widget.onAddManualFasting({
                'id': DateTime.now().millisecondsSinceEpoch,
                'date': dateCtrl.text,
                'duration': '${h}h ${m}m',
                'target': '${_targetHours}h',
              });
              Navigator.pop(ctx);
            },
            child: const Text("Salvar"),
          ),
        ],
      ),
    );
  }

  int _getCurrentPhaseIndex(double hours) {
    if (hours < 2) return 0;
    if (hours < 8) return 1;
    if (hours < 12) return 2;
    if (hours < 18) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    int totalTargetSecs = _targetHours * 3600;
    int remainingSecs = max(0, totalTargetSecs - _elapsedSeconds);
    double elapsedHours = _elapsedSeconds / 3600.0;
    int activePhaseIdx = _getCurrentPhaseIndex(elapsedHours);

    String formatTime(int secs) {
      int h = secs ~/ 3600;
      int m = (secs % 3600) ~/ 60;
      int s = secs % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jejum Intermitente'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<int>(
              value: _targetHours,
              dropdownColor: const Color(0xFF1A2632),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              items: [12, 14, 16, 18, 20, 24].map((h) {
                return DropdownMenuItem(value: h, child: Text('Protocolo $h horas'));
              }).toList(),
              onChanged: _isFasting ? null : (val) => setState(() => _targetHours = val!),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _isFasting ? Colors.tealAccent : Colors.grey, width: 8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isFasting ? "Em progresso" : "Pronto", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(formatTime(_elapsedSeconds), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                    if (_isFasting) ...[
                      const SizedBox(height: 10),
                      Text("Restante:", style: TextStyle(color: Colors.orangeAccent.shade100, fontSize: 12)),
                      Text(formatTime(remainingSecs), style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isFasting ? Colors.redAccent : Colors.tealAccent,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: _toggleFasting,
              child: Text(
                _isFasting ? 'CONCLUIR JEJUM' : 'INICIAR JEJUM',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 25),
            Row(
              children: const [
                Icon(Icons.bolt, color: Colors.tealAccent),
                SizedBox(width: 8),
                Text("Estágios Metabólicos do Jejum", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _allPhases.length,
                itemBuilder: (ctx, idx) {
                  bool isCurrent = _isFasting && idx == activePhaseIdx;
                  final phase = _allPhases[idx];

                  return Container(
                    width: 260,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isCurrent ? Colors.teal.withOpacity(0.2) : const Color(0xFF1A2632),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? Colors.tealAccent : Colors.white10,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(phase['range']!, style: TextStyle(color: isCurrent ? Colors.tealAccent : Colors.orangeAccent, fontWeight: FontWeight.bold)),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.tealAccent, borderRadius: BorderRadius.circular(4)),
                                child: const Text("ATUAL", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                              )
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(phase['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(
                          phase['desc']!,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.history, color: Colors.tealAccent),
                    SizedBox(width: 8),
                    Text("Histórico de Jejuns", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _showAddManualDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Novo Jejum"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                ),
              ],
            ),
            const SizedBox(height: 10),
            widget.history.isEmpty
                ? const Text("Nenhum jejum registrado ainda.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.history.length,
                    itemBuilder: (ctx, idx) {
                      final item = widget.history[idx];
                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text("Duração: ${item['duration']}"),
                          subtitle: Text("Data: ${item['date']} | Meta: ${item['target']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => widget.onDeleteFasting(item['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class DiaryTab extends StatelessWidget {
  final String userName;
  final double weightCurrent;
  final double weightTarget;
  final double weightStart;
  final DateTime? targetDate;
  final DateTime? startDate;
  final double heightCm;
  final List<Map<String, dynamic>> weightHistory;
  final Function(String, double, double, double, double, DateTime?, DateTime?) onProfileUpdate;
  final Function(int) onDeleteWeight;
  final Function(double) onAddWeight;

  const DiaryTab({
    super.key,
    required this.userName,
    required this.weightCurrent,
    required this.weightTarget,
    required this.weightStart,
    required this.targetDate,
    required this.startDate,
    required this.heightCm,
    required this.weightHistory,
    required this.onProfileUpdate,
    required this.onDeleteWeight,
    required this.onAddWeight,
  });

  void _showEditProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: userName);
    final startCtrl = TextEditingController(text: weightStart == 0 ? '' : weightStart.toString());
    final curCtrl = TextEditingController(text: weightCurrent == 0 ? '' : weightCurrent.toString());
    final tarCtrl = TextEditingController(text: weightTarget == 0 ? '' : weightTarget.toString());
    final heightCtrl = TextEditingController(text: heightCm == 0 ? '' : heightCm.toString());

    DateTime? selStartDate = startDate;
    DateTime? selTargetDate = targetDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A2632),
          title: const Text("Editar Perfil & Metas"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nome")),
                TextField(controller: startCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Peso Inicial (kg)")),
                TextField(controller: curCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Peso Atual (kg)")),
                TextField(controller: tarCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Meta de Peso (kg)")),
                TextField(controller: heightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Altura (cm)")),
                const SizedBox(height: 12),
                ListTile(
                  title: Text(selStartDate == null ? "Selecione Data Inicial" : "Data Inicial: ${selStartDate!.day.toString().padLeft(2, '0')}/${selStartDate!.month.toString().padLeft(2, '0')}/${selStartDate!.year}"),
                  trailing: const Icon(Icons.calendar_today, color: Colors.tealAccent),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: selStartDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selStartDate = picked;
                      });
                    }
                  },
                ),
                ListTile(
                  title: Text(selTargetDate == null ? "Selecione Data Meta" : "Data Final: ${selTargetDate!.day.toString().padLeft(2, '0')}/${selTargetDate!.month.toString().padLeft(2, '0')}/${selTargetDate!.year}"),
                  trailing: const Icon(Icons.calendar_today, color: Colors.orangeAccent),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: selTargetDate ?? DateTime.now().add(const Duration(days: 90)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selTargetDate = picked;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () {
                onProfileUpdate(
                  nameCtrl.text,
                  double.tryParse(startCtrl.text) ?? 0.0,
                  double.tryParse(curCtrl.text) ?? 0.0,
                  double.tryParse(tarCtrl.text) ?? 0.0,
                  double.tryParse(heightCtrl.text) ?? 0.0,
                  selStartDate,
                  selTargetDate,
                );
                Navigator.pop(ctx);
              },
              child: const Text("Salvar"),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddWeightDialog(BuildContext context) {
    final wCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Registrar Novo Peso"),
        content: TextField(
          controller: wCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Novo Peso (kg)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              double? val = double.tryParse(wCtrl.text);
              if (val != null) onAddWeight(val);
              Navigator.pop(ctx);
            },
            child: const Text("Salvar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalWeightToLose = weightStart - weightTarget;
    double weightLost = weightStart - weightCurrent;
    double remainingWeight = weightCurrent - weightTarget;
    double progressPercent = (totalWeightToLose > 0 && weightStart > 0) ? (weightLost / totalWeightToLose).clamp(0.0, 1.0) : 0.0;

    double plannedPercent = 0.0;
    if (startDate != null && targetDate != null && targetDate!.isAfter(startDate!)) {
      int totalDays = targetDate!.difference(startDate!).inDays;
      int passedDays = DateTime.now().difference(startDate!).inDays;
      if (totalDays > 0) {
        plannedPercent = (passedDays / totalDays).clamp(0.0, 1.0);
      }
    }

    double imc = 0.0;
    double bodyFatPercent = 0.0;
    if (heightCm > 0 && weightCurrent > 0) {
      double heightMeters = heightCm / 100;
      imc = weightCurrent / (heightMeters * heightMeters);
      bodyFatPercent = ((1.20 * imc) + (0.23 * 25) - 5.4).clamp(5.0, 60.0);
    }

    String getImcClassification(double val) {
      if (val == 0) return "Não calculado";
      if (val < 18.5) return "Abaixo do peso";
      if (val < 24.9) return "Peso normal";
      if (val < 29.9) return "Sobrepeso";
      if (val < 34.9) return "Obesidade Grau I";
      if (val < 39.9) return "Obesidade Grau II";
      return "Obesidade Grau III";
    }

    String formatDateStr(DateTime? dt) {
      if (dt == null) return "--/--/----";
      return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diário Vitae'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.tealAccent),
            onPressed: () => _showEditProfileDialog(context),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(userName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(children: [
                  const Text("Começar", style: TextStyle(color: Colors.grey)),
                  Text("${weightStart.toStringAsFixed(1)} kg", style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(formatDateStr(startDate), style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ]),
                Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.tealAccent, width: 4)),
                  child: Center(child: Text("${weightCurrent.toStringAsFixed(1)} kg", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                ),
                Column(children: [
                  const Text("Objetivo", style: TextStyle(color: Colors.grey)),
                  Text("${weightTarget.toStringAsFixed(1)} kg", style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(formatDateStr(targetDate), style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ]),
              ],
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text("Progresso Real: ${(progressPercent * 100).toStringAsFixed(1)}% | Faltam ${remainingWeight.toStringAsFixed(1)} kg", style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progressPercent, color: Colors.tealAccent, backgroundColor: Colors.white10, minHeight: 8),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text("Progresso Planejado (Tempo): ${(plannedPercent * 100).toStringAsFixed(1)}%", style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: plannedPercent, color: Colors.orangeAccent, backgroundColor: Colors.white10, minHeight: 8),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1A2632), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        const Text("IMC", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(imc == 0 ? '--' : imc.toStringAsFixed(1), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                        Text(getImcClassification(imc), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1A2632), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        const Text("Gordura Corporal", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(bodyFatPercent == 0 ? '--' : "${bodyFatPercent.toStringAsFixed(1)}%", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                        const Text("Estimativa", style: TextStyle(fontSize: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Histórico de Pesagem", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ElevatedButton.icon(
                  onPressed: () => _showAddWeightDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Novo Peso"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                )
              ],
            ),
            const SizedBox(height: 10),
            weightHistory.isEmpty
                ? const Text("Nenhum registro de peso.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: weightHistory.length,
                    itemBuilder: (ctx, idx) {
                      final item = weightHistory[idx];
                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text("${item['weight']} kg"),
                          subtitle: Text("Data: ${item['date']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => onDeleteWeight(item['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class RunTab extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final bool isRunning;
  final int seconds;
  final double distanceKm;
  final double targetDistance;
  final VoidCallback onToggleRun;
  final Function(double) onUpdateTarget;
  final Function(int) onDeleteRun;

  const RunTab({
    super.key,
    required this.history,
    required this.isRunning,
    required this.seconds,
    required this.distanceKm,
    required this.targetDistance,
    required this.onToggleRun,
    required this.onUpdateTarget,
    required this.onDeleteRun,
  });

  @override
  Widget build(BuildContext context) {
    double paceMinutes = distanceKm > 0 ? (seconds / 60) / distanceKm : 0.0;
    int pMin = paceMinutes.toInt();
    int pSec = ((paceMinutes - pMin) * 60).toInt();
    int calories = (distanceKm * 65).toInt();

    String formatRunTime(int totalSecs) {
      int h = totalSecs ~/ 3600;
      int m = (totalSecs % 3600) ~/ 60;
      int s = totalSecs % 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Corrida & GPS'), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  Text(distanceKm.toStringAsFixed(2), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                  const Text("QUILÔMETROS", style: TextStyle(color: Colors.grey, letterSpacing: 2)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.timer, color: Colors.orangeAccent),
                          const SizedBox(height: 4),
                          Text(formatRunTime(seconds), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const Text("Tempo", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(Icons.speed, color: Colors.tealAccent),
                          const SizedBox(height: 4),
                          Text("$pMin:${pSec.toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const Text("Pace (/km)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(Icons.local_fire_department, color: Colors.redAccent),
                          const SizedBox(height: 4),
                          Text("$calories", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const Text("Kcal", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? Colors.redAccent : Colors.tealAccent,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: onToggleRun,
              child: Text(
                isRunning ? 'PARAR CORRIDA' : 'INICIAR CORRIDA',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 30),
            Row(
              children: const [
                Icon(Icons.history, color: Colors.tealAccent),
                SizedBox(width: 8),
                Text("Histórico de Corridas", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            history.isEmpty
                ? const Text("Nenhuma corrida registrada ainda.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: history.length,
                    itemBuilder: (ctx, idx) {
                      final item = history[idx];
                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text("${item['distance']} - ${item['time']}"),
                          subtitle: Text("Data: ${item['date']} | Pace: ${item['pace']} | ${item['calories']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => onDeleteRun(item['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class MeasurementsTab extends StatelessWidget {
  final Map<String, bool> enabledMeasurements;
  final List<Map<String, dynamic>> history;
  final Function(Map<String, bool>) onUpdateConfig;
  final Function(Map<String, dynamic>) onAddMeasurement;
  final Function(int) onDeleteMeasurement;

  const MeasurementsTab({
    super.key,
    required this.enabledMeasurements,
    required this.history,
    required this.onUpdateConfig,
    required this.onAddMeasurement,
    required this.onDeleteMeasurement,
  });

  void _showConfigDialog(BuildContext context) {
    Map<String, bool> temp = Map.from(enabledMeasurements);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A2632),
          title: const Text("Medidas a Monitorar"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text("Braço"),
                value: temp['arm'],
                onChanged: (v) => setDialogState(() => temp['arm'] = v!),
              ),
              CheckboxListTile(
                title: const Text("Barriga"),
                value: temp['belly'],
                onChanged: (v) => setDialogState(() => temp['belly'] = v!),
              ),
              CheckboxListTile(
                title: const Text("Cintura"),
                value: temp['waist'],
                onChanged: (v) => setDialogState(() => temp['waist'] = v!),
              ),
              CheckboxListTile(
                title: const Text("Quadril"),
                value: temp['hip'],
                onChanged: (v) => setDialogState(() => temp['hip'] = v!),
              ),
              CheckboxListTile(
                title: const Text("Coxa"),
                value: temp['thigh'],
                onChanged: (v) => setDialogState(() => temp['thigh'] = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () {
                onUpdateConfig(temp);
                Navigator.pop(ctx);
              },
              child: const Text("Salvar"),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddMeasurementDialog(BuildContext context) {
    final armCtrl = TextEditingController();
    final bellyCtrl = TextEditingController();
    final waistCtrl = TextEditingController();
    final hipCtrl = TextEditingController();
    final thighCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
      text: '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}'
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Novo Registro de Medidas"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: "Data (DD/MM/AAAA)")),
              if (enabledMeasurements['arm'] == true) TextField(controller: armCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Braço (cm)")),
              if (enabledMeasurements['belly'] == true) TextField(controller: bellyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Barriga (cm)")),
              if (enabledMeasurements['waist'] == true) TextField(controller: waistCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Cintura (cm)")),
              if (enabledMeasurements['hip'] == true) TextField(controller: hipCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Quadril (cm)")),
              if (enabledMeasurements['thigh'] == true) TextField(controller: thighCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Coxa (cm)")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              onAddMeasurement({
                'id': DateTime.now().millisecondsSinceEpoch,
                'date': dateCtrl.text,
                'arm': double.tryParse(armCtrl.text) ?? 0.0,
                'belly': double.tryParse(bellyCtrl.text) ?? 0.0,
                'waist': double.tryParse(waistCtrl.text) ?? 0.0,
                'hip': double.tryParse(hipCtrl.text) ?? 0.0,
                'thigh': double.tryParse(thighCtrl.text) ?? 0.0,
              });
              Navigator.pop(ctx);
            },
            child: const Text("Salvar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? latest = history.isNotEmpty ? history.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medidas Corporais'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.tealAccent),
            onPressed: () => _showConfigDialog(context),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Última Aferição", style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 10),
            latest == null
                ? const Card(
                    color: Color(0xFF1A2632),
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text("Nenhuma medida cadastrada ainda. Clique no + para registrar."),
                    ),
                  )
                : Card(
                    color: const Color(0xFF1A2632),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text("Data: ${latest['date']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 16,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              if (enabledMeasurements['arm'] == true) Text("Braço: ${latest['arm']} cm"),
                              if (enabledMeasurements['belly'] == true) Text("Barriga: ${latest['belly']} cm"),
                              if (enabledMeasurements['waist'] == true) Text("Cintura: ${latest['waist']} cm"),
                              if (enabledMeasurements['hip'] == true) Text("Quadril: ${latest['hip']} cm"),
                              if (enabledMeasurements['thigh'] == true) Text("Coxa: ${latest['thigh']} cm"),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Histórico de Medidas", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ElevatedButton.icon(
                  onPressed: () => _showAddMeasurementDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Novo Registro"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                ),
              ],
            ),
            const SizedBox(height: 10),
            history.isEmpty
                ? const Text("Nenhum histórico disponível.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: history.length,
                    itemBuilder: (ctx, idx) {
                      final item = history[idx];
                      List<String> details = [];
                      if (enabledMeasurements['arm'] == true && item['arm'] > 0) details.add("Braço: ${item['arm']}cm");
                      if (enabledMeasurements['belly'] == true && item['belly'] > 0) details.add("Barriga: ${item['belly']}cm");
                      if (enabledMeasurements['waist'] == true && item['waist'] > 0) details.add("Cintura: ${item['waist']}cm");
                      if (enabledMeasurements['hip'] == true && item['hip'] > 0) details.add("Quadril: ${item['hip']}cm");
                      if (enabledMeasurements['thigh'] == true && item['thigh'] > 0) details.add("Coxa: ${item['thigh']}cm");

                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text("Data: ${item['date']}"),
                          subtitle: Text(details.isEmpty ? "Sem dados" : details.join(" | ")),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => onDeleteMeasurement(item['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class DietTab extends StatelessWidget {
  final List<Map<String, dynamic>> fixedMeals;
  final List<Map<String, dynamic>> meals;
  final Function(Map<String, dynamic>) onAddFixedMeal;
  final Function(int) onDeleteFixedMeal;
  final Function(Map<String, dynamic>) onAddMeal;
  final Function(int) onToggleMealDone;
  final Function(int) onDeleteMeal;

  const DietTab({
    super.key,
    required this.fixedMeals,
    required this.meals,
    required this.onAddFixedMeal,
    required this.onDeleteFixedMeal,
    required this.onAddMeal,
    required this.onToggleMealDone,
    required this.onDeleteMeal,
  });

  void _showAddFixedMealDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final foodCtrl = TextEditingController();
    final calCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Nova Refeição Fixa"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Nome (ex: Café da Manhã Fixo)")),
              TextField(controller: foodCtrl, decoration: const InputDecoration(labelText: "Alimentos")),
              TextField(
                controller: calCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Calorias Meta (kcal)"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              int calories = int.tryParse(calCtrl.text) ?? 200;
              onAddFixedMeal({
                'id': DateTime.now().millisecondsSinceEpoch,
                'title': titleCtrl.text.isEmpty ? 'Refeição Fixa' : titleCtrl.text,
                'foods': foodCtrl.text,
                'calories': calories,
              });
              Navigator.pop(ctx);
            },
            child: const Text("Salvar"),
          ),
        ],
      ),
    );
  }

  void _showAddMealDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: "08:00");
    final foodCtrl = TextEditingController();
    final calCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2632),
        title: const Text("Nova Refeição do Dia"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Nome da Refeição")),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: "Horário (ex: 08:30)")),
              TextField(controller: foodCtrl, decoration: const InputDecoration(labelText: "Alimentos Consumidos")),
              TextField(
                controller: calCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Calorias Consumidas (kcal)",
                  hintText: "Deixe vazio para autoestimar (150 kcal)",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              int calories = int.tryParse(calCtrl.text) ?? 150;
              onAddMeal({
                'id': DateTime.now().millisecondsSinceEpoch,
                'title': titleCtrl.text.isEmpty ? 'Refeição' : titleCtrl.text,
                'time': timeCtrl.text,
                'foods': foodCtrl.text,
                'calories': calories,
                'done': true,
              });
              Navigator.pop(ctx);
            },
            child: const Text("Salvar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalPlannedCalories = fixedMeals.fold(0, (sum, m) => sum + (m['calories'] as int));
    int totalConsumedCalories = meals.where((m) => m['done'] == true).fold(0, (sum, m) => sum + (m['calories'] as int));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plano de Dieta & Refeições'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Refeições Fixas (Metas)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ElevatedButton.icon(
                  onPressed: () => _showAddFixedMealDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Nova Fixa"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                ),
              ],
            ),
            const SizedBox(height: 10),
            fixedMeals.isEmpty
                ? const Text("Nenhuma refeição fixa cadastrada.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: fixedMeals.length,
                    itemBuilder: (ctx, idx) {
                      final meal = fixedMeals[idx];
                      return Card(
                        color: const Color(0xFF1A2632),
                        child: ListTile(
                          title: Text(meal['title']),
                          subtitle: Text("${meal['foods']}\nMeta: ${meal['calories']} kcal"),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => onDeleteFixedMeal(meal['id']),
                          ),
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 25),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF1A2632), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text("Planejado (Fixas)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text("$totalPlannedCalories kcal", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text("Consumido (Dia)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text("$totalConsumedCalories kcal", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Refeições do Dia", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ElevatedButton.icon(
                  onPressed: () => _showAddMealDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Adicionar Consumida"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                ),
              ],
            ),
            const SizedBox(height: 10),
            meals.isEmpty
                ? const Text("Nenhuma refeição registrada hoje.", style: TextStyle(color: Colors.grey))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: meals.length,
                    itemBuilder: (ctx, idx) {
                      final meal = meals[idx];
                      bool isDone = meal['done'] ?? false;

                      return Card(
                        color: isDone ? Colors.teal.withOpacity(0.15) : const Color(0xFF1A2632),
                        child: ListTile(
                          leading: Checkbox(
                            value: isDone,
                            activeColor: Colors.tealAccent,
                            checkColor: Colors.black,
                            onChanged: (_) => onToggleMealDone(meal['id']),
                          ),
                          title: Text("${meal['time']} - ${meal['title']}", style: TextStyle(decoration: isDone ? TextDecoration.lineThrough : null)),
                          subtitle: Text("${meal['foods']}\nConsumido: ${meal['calories']} kcal"),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () => onDeleteMeal(meal['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
