import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.quran_player.audio',
    androidNotificationChannelName: 'تشغيل الصوت',
    androidNotificationOngoing: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final player = AudioPlayer();
  List<File> files = [];
  String? folder;
  Timer? sleepTimer;
  Timer? tick;
  DateTime? endAt;
  Duration? left;

  LoopMode loop = LoopMode.off;
  bool autoNext = true;
  bool userSkip = false;
  int? lastIndex;

  static const presets = <String, int>{
    '30 دقيقة': 30,
    'ساعة': 60,
    'ساعة ونص': 90,
    'ساعتين': 120,
  };

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) Permission.notification.request();
    player.currentIndexStream.listen((i) {
      if (i != null &&
          lastIndex != null &&
          i != lastIndex &&
          !autoNext &&
          !userSkip) {
        player.pause();
        player.seek(Duration.zero, index: i);
      }
      lastIndex = i;
    });
  }

  @override
  void dispose() {
    sleepTimer?.cancel();
    tick?.cancel();
    player.dispose();
    super.dispose();
  }

  String nameOf(File f) {
    final n = f.path.split(Platform.pathSeparator).last;
    return n.toLowerCase().endsWith('.mp3') ? n.substring(0, n.length - 4) : n;
  }

  String fmt(Duration d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${t(d.inHours)}:${t(d.inMinutes % 60)}:${t(d.inSeconds % 60)}';
  }

  void msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  void userAction(void Function() f) {
    userSkip = true;
    f();
    Future.delayed(const Duration(milliseconds: 800), () => userSkip = false);
  }

  String get loopLabel => loop == LoopMode.off
      ? 'التكرار: مغلق'
      : loop == LoopMode.all
          ? 'التكرار: كل الملفات'
          : 'التكرار: الملف الحالي';

  IconData get loopIcon =>
      loop == LoopMode.one ? Icons.repeat_one : Icons.repeat;

  void cycleLoop() {
    final next = loop == LoopMode.off
        ? LoopMode.all
        : loop == LoopMode.all
            ? LoopMode.one
            : LoopMode.off;
    player.setLoopMode(next);
    setState(() => loop = next);
  }

  Future<void> pickFolder() async {
    try {
      if (Platform.isAndroid) {
        final st = await Permission.manageExternalStorage.request();
        if (!st.isGranted) {
          await [Permission.audio, Permission.storage].request();
        }
      }
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) return;

      final found = Directory(dir)
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.mp3'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      if (found.isEmpty) {
        msg('مفيش ملفات mp3 في الفولدر ده');
        return;
      }

      await player.stop();
      lastIndex = null;
      final sources = found
          .map((f) => AudioSource.file(
                f.path,
                tag: MediaItem(id: f.path, title: nameOf(f)),
              ))
          .toList();
      userSkip = true;
      await player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: 0,
        initialPosition: Duration.zero,
      );
      await player.setLoopMode(loop);
      setState(() {
        folder = dir;
        files = found;
      });
      player.play();
      Future.delayed(
          const Duration(milliseconds: 800), () => userSkip = false);
    } catch (e) {
      msg('حصل خطأ: $e');
    }
  }

  void setSleep(Duration d) {
    cancelSleep();
    endAt = DateTime.now().add(d);
    sleepTimer = Timer(d, finish);
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && endAt != null) {
        setState(() => left = endAt!.difference(DateTime.now()));
      }
    });
    setState(() => left = d);
    msg('التطبيق هيقفل بعد ${fmt(d)}');
  }

  Future<void> customTime() async {
    final h = TextEditingController(text: '0');
    final m = TextEditingController(text: '30');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حدد الوقت'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: h,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ساعات'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: m,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'دقائق'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ابدأ')),
        ],
      ),
    );
    if (ok != true) return;
    final d = Duration(
      hours: int.tryParse(h.text) ?? 0,
      minutes: int.tryParse(m.text) ?? 0,
    );
    if (d.inSeconds <= 0) {
      msg('اكتب وقت صحيح');
      return;
    }
    setSleep(d);
  }

  void cancelSleep() {
    sleepTimer?.cancel();
    tick?.cancel();
    sleepTimer = null;
    tick = null;
    endAt = null;
    if (mounted) setState(() => left = null);
  }

  Future<void> finish() async {
    cancelSleep();
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {}
    SystemNavigator.pop();
    await Future.delayed(const Duration(milliseconds: 600));
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مشغل القرآن')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: pickFolder,
                icon: const Icon(Icons.folder_open),
                label: Text(folder == null
                    ? 'اختار الفولدر'
                    : 'غيّر الفولدر (${files.length} ملف)'),
              ),
            ),
            Expanded(
              child: StreamBuilder<int?>(
                stream: player.currentIndexStream,
                builder: (context, snap) {
                  final cur = snap.data;
                  return ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      selected: i == cur,
                      leading: Icon(
                          i == cur ? Icons.graphic_eq : Icons.music_note),
                      title: Text(nameOf(files[i])),
                      onTap: () {
                        userAction(() => player.seek(Duration.zero, index: i));
                        player.play();
                      },
                    ),
                  );
                },
              ),
            ),
            StreamBuilder<PlayerState>(
              stream: player.playerStateStream,
              builder: (context, snap) {
                final playing = snap.data?.playing ?? false;
                return Row(
                  textDirection: TextDirection.ltr,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.skip_previous),
                      onPressed: () => userAction(player.seekToPrevious),
                    ),
                    IconButton(
                      iconSize: 68,
                      icon: Icon(
                          playing ? Icons.pause_circle : Icons.play_circle),
                      onPressed: playing ? player.pause : player.play,
                    ),
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.skip_next),
                      onPressed: () => userAction(player.seekToNext),
                    ),
                  ],
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ActionChip(
                    avatar: Icon(loopIcon, size: 18),
                    label: Text(loopLabel),
                    onPressed: cycleLoop,
                  ),
                  FilterChip(
                    label: const Text('تشغيل التالي تلقائياً'),
                    selected: autoNext,
                    onSelected: (v) => setState(() => autoNext = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  Text(
                    left == null
                        ? 'مؤقت النوم: مش شغال'
                        : 'هيقفل بعد ${fmt(left!)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final e in presets.entries)
                        ActionChip(
                          label: Text(e.key),
                          onPressed: () =>
                              setSleep(Duration(minutes: e.value)),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.edit, size: 18),
                        label: const Text('وقت مخصص'),
                        onPressed: customTime,
                      ),
                      if (left != null)
                        ActionChip(
                          label: const Text('إلغاء المؤقت'),
                          onPressed: cancelSleep,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
