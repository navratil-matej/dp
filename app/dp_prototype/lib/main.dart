import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:dp_prototype/vlm.g.dart';
import 'package:file_picker/file_picker.dart';
// import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:translator/translator.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import "package:ini/ini.dart";

import 'vlm.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerModules();
  await Future.wait([
    availableCameras().then((inbound) => _cameras = inbound),
    Settings.init()
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum AppStatus {
  // Something isn't right, the model isn't loaded
  setupInvalid(icon: Icon(Icons.warning)),
  // Waiting to confirm settings, TODO for deployment: It should auto start
  readyToInit(icon: Icon(Icons.check)),
  // Initial step, sys prompt processing
  initState(icon: Icon(Icons.timer)),
  // Waiting for user to begin recording
  readyToRecord(icon: Icon(Icons.mic)),
  // Waiting for the system to confirm that it's listening
  waitingToBeginRecording(icon: Icon(Icons.timer)),
  // Waiting for user to end recording, TODO for deployment: What if OS ends it by itself?
  recording(icon: Icon(Icons.check)),
  // Processing the rest of the pipeline
  processing(icon: Icon(Icons.timer)),
  ;

  final Icon icon;

  const AppStatus({ required this.icon });
}

class _MyHomePageState extends State<MyHomePage> {

  int _idx = 0;
  AppStatus status = AppStatus.setupInvalid;

  XFile? _img;

  bool _sttReady = false;
  SpeechToText _stt = SpeechToText();
  String _sttResult = '';

  FlutterTts _tts = FlutterTts();

  GoogleTranslator _trans = GoogleTranslator(client: ClientType.extensionGT);

  // String _modelLang = 'en';
  // String _userLang  = 'en';

  String? model = Settings.getValue<String>("model");
  String? mmproj = Settings.getValue<String>("mmproj");
  String? mconf;

  InferenceTaskChannel? currentTask;
  ReceivePort? currentTaskRp;
  SendPort? imgSp;
  SendPort? recSp;

  VlmModel? vlm; // Vlm('MobileVLM_V2-1.7B-Q5_K.gguf', 'MobileVLM-V2-1.7B-mmproj-model-f16.gguf')

  late CameraController controller;

  static var presets = <ResolutionPreset> [
    ResolutionPreset.low,
    ResolutionPreset.medium,
    ResolutionPreset.high,
    ResolutionPreset.veryHigh,
    ResolutionPreset.ultraHigh,
    ResolutionPreset.max,
  ];

  @override
  void initState() {
    super.initState();
    var preset = Settings.getValue<int>('resolution', defaultValue: 0)!;
    _initCam(presets[preset]);
    _tts.awaitSpeakCompletion(true);
    _stt.initialize().then((ready) { _sttReady = ready; });
  }

  void _upadteCam() {
    var preset = Settings.getValue<int>('resolution', defaultValue: 0)!;
    if(presets[preset] != controller.resolutionPreset) {
      _initCam(presets[preset]);
    }
  }

  void _initCam(ResolutionPreset preset) {
    controller = CameraController(_cameras[0], preset, enableAudio: false);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            // Handle access errors here.
            break;
          default:
            // Handle other errors here.
            break;
        }
      }
    });
  }

  void _barSelect(int idx) {
    setState(() {
      _idx = idx;
    });
  }

  void _press() {
    switch(status) {
      case AppStatus.readyToInit:
        _initVlm();
        break;
      case AppStatus.readyToRecord:
        setState(() { status = AppStatus.waitingToBeginRecording; });
        _recordBegin();
        break;
      case AppStatus.recording:
        setState(() { status = AppStatus.processing; });
        _recordEnd();
        break;
      case AppStatus.setupInvalid:
      case AppStatus.initState:
      case AppStatus.waitingToBeginRecording:
      case AppStatus.processing:
      default: break;
    }
  }

  Future<void> _initVlm() async {
    var systemTts = _tts.speak;

    if (vlm == null || vlm!.model_path != model || vlm!.mmproj_path != mmproj) {
      vlm?.free();
      vlm = VlmModel(model!, mmproj!); // Shouldn't be null in this state
    }

    vlm!.cfg = await _vlmCfgFromPersistent();
    _tts.setLanguage(vlm!.cfg.userLang);

    currentTaskRp = ReceivePort();
    currentTask = InferenceTaskChannel(vlm!, currentTaskRp!.sendPort, systemTts, _trans);

    currentTaskRp!.listen((inbound) {
      if (inbound is! OutMessage) {
        throw Exception;
      }
      // Ready for user to record
      if (inbound.msg == '!!READY!!') {
        setState(() {
          recSp = inbound.replyPort;
          if(imgSp != null) {
            status = AppStatus.readyToRecord;
          }
        });
      } else
      // Ready for user to take picture (happens alongside recording, so both are needed for app to be ready)
      if (inbound.msg == '!!IMG!!') {
        imgSp = inbound.replyPort;
        if(recSp != null) {
          status = AppStatus.readyToRecord;
        }
      } else
      // Begin system TTS
      if (inbound.msg == '!!REC!!') {
        _stt.listen(
          localeId: vlm!.cfg.userLang,
          onResult: (res) {
            recSp!.send(res.recognizedWords);
            if(res.finalResult) {
              recSp!.send('!!END!!');
            }
          }).then((_) => setState(() {
            status = AppStatus.recording;
          })
        );
      } else
      // Begin custom TTS (no module for this developed)
      if (inbound.msg == '!!CUSTOM!!') {
        setState(() {
          status = AppStatus.recording;
        });
      } else
      // System is done
      if (inbound.msg == '!!DONE!!') {
        setState(() {
          status = AppStatus.readyToInit;
          imgSp = null;
          recSp = null;
          currentTask = null;
          currentTaskRp?.close();
          currentTaskRp = null;
          _img = null;
        });
      } else { // TTS 
        _tts.speak(inbound.msg).then((_) => inbound.replyPort!.send('!!DONE!!'));
      }
    });

    endpoint(currentTask!);
  }

  Future<void> _recordBegin() async {
    // var imgPath = await controller.takePicture();
    controller.takePicture().then((inbound) {
      setState(() {
        _img = inbound;
        imgSp!.send(_img!.path);
      });
    });

    recSp!.send('!!BEGIN!!');
  }

  Future<void> _recordEnd() async {
    _stt.stop(); // no-op if it wasn't started
    recSp!.send('!!STOP!!');
  }

  AppStatus _checkSetup(AppStatus status) {
    if (status == AppStatus.readyToInit || status == AppStatus.setupInvalid) {
      bool modelCheck = model != null && File(model!).existsSync() && model!.endsWith(".gguf");
      bool mmprojCheck = model != null && File(model!).existsSync() && model!.endsWith(".gguf");
      return (modelCheck && mmprojCheck) ? AppStatus.readyToInit : AppStatus.setupInvalid;
    } else {
      return status;
    }
  }

  Future<VlmConfig> _vlmCfgFromPersistent() async {
    return VlmConfig(
      nCtx: Settings.getValue<double>('n-ctx', defaultValue: 2048)!.round(),
      cpuThreads: Settings.getValue<double>('n-cpu', defaultValue: 4)!.round(),
      modelLang: Settings.getValue<String>('model-lang', defaultValue: 'en-US')!,
      userLang: Settings.getValue<String>('user-lang', defaultValue: 'en-US')!,
      systemPrompt: Settings.getValue<String>('system-prompt', defaultValue: "A chat between a curious human and an artificial intelligence assistant. The assistant gives helpful, detailed, and polite answers to the human's questions.\nUSER:")!.replaceAll('\\n', '\n'),
      systemPromptAddBos: Settings.getValue<bool>('system-prompt-add-bos', defaultValue: true)!,
      userPromptPrefix: Settings.getValue<String>('user-prompt-prefix', defaultValue: "")!.replaceAll('\\n', '\n'),
      userPromptSuffix: Settings.getValue<String>('user-prompt-suffix', defaultValue: "\nASSISTANT:")!.replaceAll('\\n', '\n'),
      topK: Settings.getValue<double>('top-k', defaultValue: 40)!.round(),
      topP: Settings.getValue<double>('top-p', defaultValue: 0.95)!,
      minP: Settings.getValue<double>('min-p', defaultValue: 0.05)!,
      temp: Settings.getValue<double>('temp', defaultValue: 0.10)!,
      sysModule: Settings.getValue<String>('sys-module', defaultValue: '')!,
      imgModule: Settings.getValue<String>('img-module', defaultValue: '')!,
      usrModule: Settings.getValue<String>('usr-module', defaultValue: '')!,
      recModule: Settings.getValue<String>('rec-module', defaultValue: '')!,
      ttsModule: Settings.getValue<String>('tts-module', defaultValue: '')!,
      sampleModule: Settings.getValue<String>('sample-module', defaultValue: '')!,
      translateInModule: Settings.getValue<String>('translate-in-module', defaultValue: '')!,
      translateOutModule: Settings.getValue<String>('translate-out-module', defaultValue: '')!,
    );
  }

  Future<String?> pickFile(String ext) async {
    // https://github.com/miguelpruivo/flutter_file_picker/issues/1689
    // FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: [ext]);
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
    return result?.files.single.path;
  }

  Widget _buildBarWidget() {
    switch (_idx) {
      case 0:
        _upadteCam();
        return Scaffold(
          body: (_img == null) ? CameraPreview(controller) : Container(width: double.infinity, child: Image.file(File(_img!.path), fit: BoxFit.contain)),
          floatingActionButton: FloatingActionButton(
            onPressed: _press,
            tooltip: 'Ask!',
            child: status.icon,
          ),
        );
      case 1:
        return Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SliderSettingsTile(
                  title: 'Context window',
                  settingKey: 'n-ctx',
                  defaultValue: 2048,
                  min: 1024,
                  max: 4096,
                  step: 128,
                  leading: Icon(Icons.expand),
                ),
                const RadioModalSettingsTile<int>(
                  title: 'Camera Resolution',
                  settingKey: 'resolution',
                  values: <int, String>{
                    0: 'Low',
                    1: 'Medium',
                    2: 'High',
                    3: 'Very High',
                    4: 'Ultra High',
                    5: 'Max',
                  },
                  selected: 0,
                  leading: Icon(Icons.aspect_ratio),
                ),
                const SliderSettingsTile(
                  title: 'CPU Threads limit',
                  settingKey: 'n-cpu',
                  defaultValue: 4,
                  min: 1,
                  max: 8,
                  step: 1,
                  leading: Icon(Icons.numbers),
                ),
                const ExpandableSettingsTile(
                  title: 'Language selection',
                  // subtitle: 'Expandable Settings',
                  children: [
                    RadioModalSettingsTile<String>(
                      title: 'User language',
                      settingKey: 'user-lang',
                      values: <String, String>{'en-US': 'en-US', 'cs-CZ': 'cs-CZ'},
                      selected: 'en-US',
                    ),
                    RadioModalSettingsTile<String>(
                      title: 'Model language',
                      settingKey: 'model-lang',
                      values: <String, String>{'en-US': 'en-US', 'cs-CZ': 'cs-CZ'},
                      selected: 'en-US',
                    ),
                  ],
                ),
                const ExpandableSettingsTile(
                  title: 'Prompt settings',
                  // subtitle: 'Expandable Settings',
                  children: [
                    TextInputSettingsTile(
                      title: 'System prompt',
                      settingKey: 'system-prompt',
                      initialValue: "A chat between a curious human and an artificial intelligence assistant. The assistant gives helpful, detailed, and polite answers to the human's questions.\\nUSER:",
                    ),
                    SwitchSettingsTile(
                      title: 'Add BoS token',
                      settingKey: 'system-prompt-add-bos',
                      defaultValue: true,
                      leading: Icon(Icons.start),
                    ),
                    TextInputSettingsTile(
                      title: 'User prompt prefix',
                      settingKey: 'user-prompt-prefix',
                      initialValue: "",
                    ),
                    TextInputSettingsTile(
                      title: 'User prompt suffix',
                      settingKey: 'user-prompt-suffix',
                      initialValue: "\\nASSISTANT:",
                    ),
                  ],
                ),
                const ExpandableSettingsTile(
                  title: 'Sampler parameters',
                  // subtitle: 'Expandable Settings',
                  children: [
                    SliderSettingsTile(
                      title: 'Top k',
                      settingKey: 'top-k',
                      defaultValue: 40,
                      min: 10,
                      max: 100,
                      step: 1,
                      leading: Icon(Icons.numbers),
                    ),
                    SliderSettingsTile(
                      title: 'Top p',
                      settingKey: 'top-p',
                      defaultValue: 0.95,
                      min: 0.00,
                      max: 1.00,
                      step: 0.01,
                      leading: Icon(Icons.maximize),
                    ),
                    SliderSettingsTile(
                      title: 'Min p',
                      settingKey: 'min-p',
                      defaultValue: 0.05,
                      min: 0.00,
                      max: 1.00,
                      step: 0.01,
                      leading: Icon(Icons.minimize),
                    ),
                    SliderSettingsTile(
                      title: 'Temperature',
                      settingKey: 'temp',
                      defaultValue: 0.10,
                      min: 0.00,
                      max: 1.00,
                      step: 0.01,
                      leading: Icon(Icons.thermostat),
                    ),
                  ],
                ),
                ExpandableSettingsTile(
                  title: 'Module selection',
                  // subtitle: 'Expandable Settings',
                  children: [
                    RadioModalSettingsTile<String>(
                      title: 'System prompt module',
                      settingKey: 'sys-module',
                      values: Map.fromIterables(Sys.reg.keys, Sys.reg.keys),
                      selected: '',
                    ),
                    RadioModalSettingsTile<String>(
                      title: 'Image processing module',
                      settingKey: 'img-module',
                      values: Map.fromIterables(Img.reg.keys, Img.reg.keys),
                      selected: '',
                    ),
                    RadioModalSettingsTile<String>(
                      title: 'User prompt module',
                      settingKey: 'usr-module',
                      values: Map.fromIterables(Usr.reg.keys, Usr.reg.keys),
                      selected: '',
                    ),
                    RadioModalSettingsTile<String>(
                      title: 'Sampling module',
                      settingKey: 'sample-module',
                      values: Map.fromIterables(Sample.reg.keys, Sample.reg.keys),
                      selected: '',
                    ),
                    RadioModalSettingsTile<String>(
                      title: 'Speech recognition module',
                      settingKey: 'rec-module',
                      values: Map.fromIterables(Rec.reg.keys, Rec.reg.keys),
                      selected: '',
                    ),
                    RadioModalSettingsTile<String>(
                      title: 'Speech synthesis module',
                      settingKey: 'tts-module',
                      values: Map.fromIterables(Tts.reg.keys, Tts.reg.keys),
                      selected: '',
                    ),
                    RadioModalSettingsTile<String>(
                      title: 'User translation module',
                      settingKey: 'translate-in-module',
                      values: Map.fromIterables(TranslateIn.reg.keys, TranslateIn.reg.keys),
                      selected: '',
                    ),
                    RadioModalSettingsTile<String>(
                      title: 'Model translation module',
                      settingKey: 'translate-out-module',
                      values: Map.fromIterables(TranslateOut.reg.keys, TranslateOut.reg.keys),
                      selected: '',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      case 2:
        return Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: const Text("Model (*.gguf)"),
                subtitle: Text(model ?? "None!"),
                trailing: const Icon(Icons.folder),
                leading: (model != null && File(model!).existsSync() && model!.endsWith(".gguf"))
                  ? const Icon(Icons.check)
                  : const Icon(Icons.warning),
                onTap: (() async {
                  model = await pickFile("gguf");
                  await Settings.setValue("model", model);
                  setState(() {});
                })
              ),
              ListTile(
                title: const Text("Projector (*.gguf)"),
                subtitle: Text(mmproj ?? "None!"),
                trailing: const Icon(Icons.folder),
                leading: (mmproj != null && File(mmproj!).existsSync() && model!.endsWith(".gguf"))
                  ? const Icon(Icons.check)
                  : const Icon(Icons.warning),
                onTap: (() async {
                  mmproj = await pickFile("gguf");
                  await Settings.setValue("mmproj", mmproj);
                  setState(() {});
                })
              ),
              // ListTile(
              //   title: const Text("Config (*.cfg)"),
              //   subtitle: Text(mconf ?? "None!"),
              //   trailing: const Icon(Icons.folder),
              //   leading: (mconf != null && File(mconf!).existsSync() && model!.endsWith(".cfg"))
              //     ? const Icon(Icons.check)
              //     : const Icon(Icons.warning),
              //   onTap: (() async => mconf = await pickFile("cfg"))
              // ),
            ],
          ),
        );
      default:
        throw StateError;
    }
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    status = _checkSetup(status);
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: _buildBarWidget(),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const Icon(Icons.camera_alt),
            label: 'Assistant',
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: 'Settings',
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.folder),
            label: 'Load model',
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          ),
        ],
        currentIndex: _idx,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _barSelect,
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}