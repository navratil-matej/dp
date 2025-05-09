@CodeGen(
  runBefore: [before],
  runAfter: [after],
)
library vlm;

import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'package:ffi/ffi.dart' as ffi_also;
import 'package:ffi/ffi.dart' show malloc;
import 'package:super_annotations/super_annotations.dart';
import 'package:translator/translator.dart';
import 'llama_cpp.dart' as llama_cpp_structs;
import 'llava_cpp.dart' as llava_cpp_structs;

// ignore: non_constant_identifier_names
var llama_cpp_dylib = ffi.DynamicLibrary.open('libllama.so');
// var llama_cpp_dylib = ffi.DynamicLibrary.open('llama');
// ignore: non_constant_identifier_names
var llama_cpp = llama_cpp_structs.llama_cpp(llama_cpp_dylib);
// ignore: non_constant_identifier_names
var llava_cpp_dylib = ffi.DynamicLibrary.open('libllava.so');
// var llava_cpp_dylib = ffi.DynamicLibrary.open('llava');
// ignore: non_constant_identifier_names
var llava_cpp = llava_cpp_structs.llava_cpp(llava_cpp_dylib);


Future<R> compute<R>(Future<R> Function(InferenceTaskChannel) fn, InferenceTaskChannel c) async {
  return Isolate.run(() => fn(c));
}

// This function is to be used when the control flow is not the inverse of data flow
Future<R> computeMsg<M, R>(Future<R> Function(InferenceTaskChannel, M) fn, InferenceTaskChannel c, M msg) async {
  return Isolate.run(() => fn(c, msg));
}

void before(LibraryBuilder output) {
  output.body.add(const Code('import "package:dp_prototype/vlm.dart";\n\nvoid registerModules() {'));
}

void after(LibraryBuilder output) {
  output.body.add(const Code('}'));
}

class Sys extends FunctionAnnotation {
  final String key;
  static var reg = <String, Future<VlmPostSysState> Function(InferenceTaskChannel)>{};

  const Sys(this.key);

  @override
  void apply(Method target, LibraryBuilder output) {
    output.body.add(Code('  Sys.reg["$key"] = ${target.name};\n'));
  }
}

class Img extends FunctionAnnotation {
  final String key;
  static var reg = <String, Future<VlmPostImgState> Function(InferenceTaskChannel, VlmPreImgState)>{};

  const Img(this.key);

  @override
  void apply(Method target, LibraryBuilder output) {
    output.body.add(Code('  Img.reg["$key"] = ${target.name};\n'));
  }
}

class Usr extends FunctionAnnotation {
  final String key;
  static var reg = <String, Future<VlmSamplingState> Function(InferenceTaskChannel, VlmPreUsrState)>{};

  const Usr(this.key);

  @override
  void apply(Method target, LibraryBuilder output) {
    output.body.add(Code('  Usr.reg["$key"] = ${target.name};\n'));
  }
}

class Rec extends FunctionAnnotation {
  final String key;
  static var reg = <String, Future<String> Function(InferenceTaskChannel)>{};

  const Rec(this.key);

  @override
  void apply(Method target, LibraryBuilder output) {
    output.body.add(Code('  Rec.reg["$key"] = ${target.name};\n'));
  }
}

class Tts extends FunctionAnnotation {
  final String key;
  static var reg = <String, Future<void> Function(InferenceTaskChannel, String)>{};

  const Tts(this.key);

  @override
  void apply(Method target, LibraryBuilder output) {
    output.body.add(Code('  Tts.reg["$key"] = ${target.name};\n'));
  }
}

class Sample extends FunctionAnnotation {
  final String key;
  static var reg = <String, Future<VlmSamplingState> Function(InferenceTaskChannel, VlmSamplingState)>{};

  const Sample(this.key);

  @override
  void apply(Method target, LibraryBuilder output) {
    output.body.add(Code('  Sample.reg["$key"] = ${target.name};\n'));
  }
}

class TranslateIn extends FunctionAnnotation {
  final String key;
  static var reg = <String, Future<String> Function(InferenceTaskChannel, String)>{};

  const TranslateIn(this.key);

  @override
  void apply(Method target, LibraryBuilder output) {
    output.body.add(Code('  TranslateIn.reg["$key"] = ${target.name};\n'));
  }
}

class TranslateOut extends FunctionAnnotation {
  final String key;
  static var reg = <String, Future<VlmSamplingState> Function(InferenceTaskChannel, VlmSamplingState)>{};

  const TranslateOut(this.key);

  @override
  void apply(Method target, LibraryBuilder output) {
    output.body.add(Code('  TranslateOut.reg["$key"] = ${target.name};\n'));
  }
}

// Mandatory for the dicts to be sent to isolates
class VlmModules {
  var sys = Sys.reg;
  var img = Img.reg;
  var usr = Usr.reg;
  var rec = Rec.reg;
  var tts = Tts.reg;
  var sample = Sample.reg;
  var translateIn = TranslateIn.reg;
  var translateOut = TranslateOut.reg;

  VlmModules();
}

@Sys('')
Future<VlmPostSysState> defaultSys(InferenceTaskChannel c) async {
  return c.model.makeState();
}

@Img('')
Future<VlmPostImgState> defaultImg(InferenceTaskChannel c, VlmPreImgState s) async {
  return c.model.processImage(s);
}

@Img('Scaled To 500')


@Usr('')
Future<VlmSamplingState> defaultUsr(InferenceTaskChannel c, VlmPreUsrState s) async {
  return c.model.processPrompt(s);
}

@Rec('')
Future<String> defaultRec(InferenceTaskChannel c) async {
  String ret = '';
  var end = ReceivePort();
  var rp = ReceivePort();
  rp.listen((inbound) {
    if (inbound is String) {
      if(inbound == '!!BEGIN!!') {
        // Send !!REC!! to enable system stt, alternatively use custom stt
        c.out.send(OutMessage('!!REC!!'));
      } else if(inbound == '!!STOP!!') {
        // no-op: After sending !!REC!!, Flutter/System handles speech-to-text
      } else if(inbound == '!!END!!') {
        end.sendPort.send('!!END!!');
      } else {
        ret = inbound;
      }
    } else {
      throw Exception();
    }
  });

  c.out.send(OutMessage('!!READY!!', replyPort: rp.sendPort));
  await end.first; // !!END!!
  return ret;
}

@Tts('')
Future<void> defaultTts(InferenceTaskChannel c, String s) async {
  if(s != '') {
    // return c.systemTts(s);
    ReceivePort rp = ReceivePort();
    c.out.send(OutMessage(s, replyPort: rp.sendPort));
    return rp.first;
  }
}

@Sample('')
Future<VlmSamplingState> defaultSample(InferenceTaskChannel c, VlmSamplingState s) async {
  String soFar = '';
  String piece;
  bool done = false;
  int i;
  for (i = s.sampled; i < 256; i++) { // TODO for deployment: i could also come from config
    piece = c.model.sample(s.sampler, s.ctx_llama, s.n_tokens + i);
    if(piece == '</s>' || piece.contains('###')) {
      done = true;
      break;
    }
    soFar += piece;
    piece = piece.trim();
    if (piece.endsWith('.') || piece.endsWith('?') || piece.endsWith('!')) {
      break;
    }
    if(soFar.contains('<|im_end|>') || soFar.contains('<|im_start|>') || soFar.contains('USER:') || soFar.contains('<user>')) {
      done = true;
      break;
    }
  }
  return VlmSamplingState.next(s, soFar, i - s.sampled + 1, done || (i >= 255)); // TODO for deployment: i could also come from config
}

@TranslateIn('')
Future<String> defaultTranslateIn(InferenceTaskChannel c, String s) async {
  String from = c.model.cfg.userLang.split('-')[0];
  String to   = c.model.cfg.modelLang.split('-')[0];
  print('Translate In From "$s"');
  if (from != to && s != '') {
    var tl = await c.systemTranslate.translate(s, from: from, to: to);
    s = tl.text;
  }
  print('Translate In To   "$s"');
  return s;
}

@TranslateOut('')
Future<VlmSamplingState> defaultTranslateOut(InferenceTaskChannel c, VlmSamplingState s) async {
  String from = c.model.cfg.modelLang.split('-')[0];
  String to   = c.model.cfg.userLang.split('-')[0];
  print('Translate Out From "${s.new_caption}"');
  if (from != to && s.new_caption != '') {
    var tl = await c.systemTranslate.translate(s.new_caption, from: from, to: to);
    s.new_caption = tl.text;
  }
  print('Translate Out To   "${s.new_caption}"');
  return s;
}

class VlmModel {
  final String model_path;
  final String mmproj_path;
  VlmConfig cfg = VlmConfig();

  final ffi.Pointer<llama_cpp_structs.llama_model> llama_model;
  final ffi.Pointer<llava_cpp_structs.clip_ctx> ctx_clip;

  VlmModel(this.model_path, this.mmproj_path) : 
    llama_model = llama_cpp.llama_load_model_from_file(model_path.toNativeUtf8().cast<ffi.Char>(), llama_cpp.llama_model_default_params()),
    ctx_clip = llava_cpp.clip_model_load(mmproj_path, 1);
    
  VlmPostSysState makeState() {
    var ctx_params = llama_cpp.llama_context_default_params();
    ctx_params.n_ctx = cfg.nCtx;
    ctx_params.n_threads = cfg.cpuThreads;
    ctx_params.n_threads_batch = cfg.cpuThreads;

    var ctx_llama = llama_cpp.llama_new_context_with_model(llama_model, ctx_params);

    // var embed = llava_cpp.llava_image_embed_make_with_filename(ctx_clip, cpu_threads, img);

    var sysPromptNative = cfg.systemPrompt.toNativeUtf8();
    // var usrPromptNative = (user_prompt_prefix + prompt + user_prompt_suffix).toNativeUtf8();

    int n_tokens = sysPromptNative.length + 2 * (cfg.systemPromptAddBos ? 1 : 0);
    var tokensPtr = malloc.allocate<llama_cpp_structs.llama_token>(4 * n_tokens);
    var vocab = llama_cpp.llama_model_get_vocab(llama_model);
    n_tokens = llama_cpp.llama_tokenize(vocab, sysPromptNative.cast<ffi.Char>(), sysPromptNative.length, tokensPtr, n_tokens, cfg.systemPromptAddBos, true);
    llama_cpp.llama_decode(ctx_llama, llama_cpp.llama_batch_get_one(tokensPtr, n_tokens/*, 0, 0*/));
    malloc.free(tokensPtr);

    return VlmPostSysState(ctx_params, ctx_llama, n_tokens);
  }

  VlmPostImgState processImage(VlmPreImgState state)
  {
    var embed = llava_cpp.llava_image_embed_make_with_filename(ctx_clip, cfg.cpuThreads, state.image_path);

    var n_pastPtr = malloc.allocate<ffi.Int>(4);
    n_pastPtr.value = state.n_tokens;
    llava_cpp.llava_eval_image_embed(state.ctx_llama, embed, state.params.n_batch, n_pastPtr);
    state.n_tokens = n_pastPtr.value;
    malloc.free(n_pastPtr);

    return VlmPostImgState(state, embed);
  }

  VlmSamplingState processPrompt(VlmPreUsrState state)
  {
    var usrPromptNative = (cfg.userPromptPrefix + state.user_prompt + cfg.userPromptSuffix).toNativeUtf8();

    var tokensPtr = malloc.allocate<llama_cpp_structs.llama_token>(4 * usrPromptNative.length);
    var vocab = llama_cpp.llama_model_get_vocab(llama_model);
    var n_tokens = llama_cpp.llama_tokenize(vocab, usrPromptNative.cast<ffi.Char>(), usrPromptNative.length, tokensPtr, usrPromptNative.length, false, true);
    llama_cpp.llama_decode(state.ctx_llama, llama_cpp.llama_batch_get_one(tokensPtr, n_tokens/*, state.n_tokens, 0*/));
    state.n_tokens += n_tokens;
    malloc.free(tokensPtr);

    var sampler = makeSampler(seed: cfg.seed, temp: cfg.temp, top_k: cfg.topK, top_p: cfg.topP, min_p: cfg.minP);

    return VlmSamplingState(state, sampler);
  }

  String sample(sampler, ctx_llama, n_past) {
    var token = llama_cpp.llama_sampler_sample(sampler, ctx_llama, -1);
    String piece;
    var vocab = llama_cpp.llama_model_get_vocab(llama_cpp.llama_get_model(ctx_llama));
    if(!llama_cpp.llama_token_is_eog(vocab, token))
    {
      var piecePtr = malloc.allocate<ffi.Char>(15);
      var n_char = llama_cpp.llama_token_to_piece(vocab, token, piecePtr, 15, 0, true);
      piece = piecePtr.cast<ffi_also.Utf8>().toDartString(length: n_char);
      malloc.free(piecePtr);
    }
    else
    {
      piece = '</s>';
    }
    var tokenPtr = malloc.allocate<llama_cpp_structs.llama_token>(4);
    tokenPtr.value = token;
    llama_cpp.llama_decode(ctx_llama, llama_cpp.llama_batch_get_one(tokenPtr, 1/*, n_past, 0*/));
    malloc.free(tokenPtr);
    return piece;
  }

  ffi.Pointer<llama_cpp_structs.llama_sampler> makeSampler({int seed=0, double temp=0.1, int top_k=40, double top_p=0.95, double min_p=0.05})
  {
    var chain = llama_cpp.llama_sampler_chain_init(llama_cpp.llama_sampler_chain_default_params());
    llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_top_k(top_k));
    llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_top_p(top_p, 0));
    llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_min_p(min_p, 0));
    llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_temp_ext(temp, 0.0, 1.0));
    llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_softmax());
    llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_dist(seed));
    return chain;
  }

  void free() {
    llava_cpp.clip_free(ctx_clip);
    llama_cpp.llama_model_free(llama_model);
  }
}

// Isolate message objs

class VlmPostSysState {
  llama_cpp_structs.llama_context_params params;
  ffi.Pointer<llama_cpp_structs.llama_context> ctx_llama;
  int n_tokens;

  VlmPostSysState(this.params, this.ctx_llama, this.n_tokens);
}

class VlmPreImgState {
  llama_cpp_structs.llama_context_params params;
  ffi.Pointer<llama_cpp_structs.llama_context> ctx_llama;
  int n_tokens;
  String image_path;

  VlmPreImgState(VlmPostSysState prev, this.image_path)
    : params = prev.params,
      ctx_llama = prev.ctx_llama,
      n_tokens = prev.n_tokens;
}

class VlmPostImgState {
  llama_cpp_structs.llama_context_params params;
  ffi.Pointer<llama_cpp_structs.llama_context> ctx_llama;
  int n_tokens;
  ffi.Pointer<llava_cpp_structs.llava_image_embed> embed;

  VlmPostImgState(VlmPreImgState prev, this.embed)
    : params = prev.params,
      ctx_llama = prev.ctx_llama,
      n_tokens = prev.n_tokens;
}

class VlmPreUsrState {
  llama_cpp_structs.llama_context_params params;
  ffi.Pointer<llama_cpp_structs.llama_context> ctx_llama;
  int n_tokens;
  ffi.Pointer<llava_cpp_structs.llava_image_embed> embed;
  String user_prompt;

  VlmPreUsrState(VlmPostImgState prev, this.user_prompt)
    : params = prev.params,
      ctx_llama = prev.ctx_llama,
      n_tokens = prev.n_tokens,
      embed = prev.embed;
}

class VlmSamplingState {
  llama_cpp_structs.llama_context_params params;
  ffi.Pointer<llama_cpp_structs.llama_context> ctx_llama;
  int n_tokens;
  ffi.Pointer<llava_cpp_structs.llava_image_embed> embed;

  ffi.Pointer<llama_cpp_structs.llama_sampler> sampler;
  String total_caption = '';
  String new_caption = '';
  int sampled = 0;
  bool done = false;

  VlmSamplingState(VlmPreUsrState prev, this.sampler)
    : params = prev.params,
      ctx_llama = prev.ctx_llama,
      n_tokens = prev.n_tokens,
      embed = prev.embed;

  VlmSamplingState.next(VlmSamplingState prev, String n_caption, int n_sampled, this.done)
    : params = prev.params,
      ctx_llama = prev.ctx_llama,
      n_tokens = prev.n_tokens,
      embed = prev.embed,
      sampler = prev.sampler,
      new_caption = n_caption,
      total_caption = prev.total_caption + n_caption,
      sampled = prev.sampled + n_sampled;
      
  void free() {
    llama_cpp.llama_free(ctx_llama);
    llava_cpp.llava_image_embed_free(embed);
    llama_cpp.llama_sampler_free(sampler);
  }
}

// Due to limitations on sending ReceivePort, this is the format used for outgoing messages.
// replyPort is an optional way for the UI to respond to this signal.
final class OutMessage {
  final String msg;
  final SendPort? replyPort;

  OutMessage(this.msg, {this.replyPort});
}

final class InferenceTaskChannel {
  final VlmModel model;
  final VlmModules modules = VlmModules();

  // Comms protocol: Send OutMessage(msg), attach reply port where needed
  // '!!IMG!!'   + rp_img - Request image, rp_img will receive path when ready
  // '!!READY!!' + rp_rec - Signal that VLM is ready and awaiting user inputs
  //    rp_rec spec:
  //    '!!BEGIN!!' - user input to begin recording
  //    '!!STOP!!'  - user input to end recording
  //    '!!END!!'   - if system speech-to-text was requested, this symbol is sent at the end
  //    Other       - if system speech-to-text was requested, contains intermediary results
  // '!!REC!!'    - Request system speech-to-text
  // '!!CUSTOM!!' - If using custom speech-to-text, this signals to the app that it's ready
  // '!!DONE!!'   - Task is finished
  final SendPort out;

  // This must not be FlutterTts as it breaks build_runner dep
  Future<void> Function(String) systemTts;
  GoogleTranslator systemTranslate;

  InferenceTaskChannel(this.model, this.out, this.systemTts, this.systemTranslate); // : gotImg = ReceivePort(), gotUsr = ReceivePort();
}

// Inference dependency network, dynamically loading impl modules

Future<VlmPostSysState> runnerSys(InferenceTaskChannel c) async {
  var module = c.modules.sys[c.model.cfg.sysModule]!;
  return module(c);
}

Future<String> runnerRec(InferenceTaskChannel c) async {
  var module = c.modules.rec[c.model.cfg.recModule]!;
  return module(c);
}

Future<VlmPostImgState> runnerImg(InferenceTaskChannel c, VlmPostSysState msg) async {
  var module = c.modules.img[c.model.cfg.imgModule]!;
  ReceivePort rp = ReceivePort();
  c.out.send(OutMessage('!!IMG!!', replyPort: rp.sendPort));
  return rp.first.then((inbound) => module(c, VlmPreImgState(msg, inbound)));
}

Future<String> runnerTranslateIn(InferenceTaskChannel c) async {
  var inRec = await compute(runnerRec, c);

  var module = c.modules.translateIn[c.model.cfg.translateInModule]!;
  return module(c, inRec);
}

Future<VlmSamplingState> runnerSample(InferenceTaskChannel c, VlmSamplingState msg) async {
  var module = c.modules.sample[c.model.cfg.sampleModule]!;
  return module(c, msg);
}

Future<VlmSamplingState> runnerTranslateOut(InferenceTaskChannel c, VlmSamplingState msg) async {
  var inSmp = await computeMsg(runnerSample, c, msg);

  var module = c.modules.translateOut[c.model.cfg.translateOutModule]!;
  return module(c, inSmp);
}

Future<void> runnerTts(InferenceTaskChannel c, String msg) async {
  var module = c.modules.tts[c.model.cfg.ttsModule]!;
  return module(c, msg);
}

Future<VlmSamplingState> runnerUsr(InferenceTaskChannel c) async {
  var inSys = await compute(runnerSys, c);

  var tsRec = compute   (runnerTranslateIn, c);
  var tsImg = computeMsg(runnerImg, c, inSys);

  late String inRec;
  late VlmPostImgState inImg;
  await Future.wait([
    tsRec.then((inbound) => inRec = inbound),
    tsImg.then((inbound) => inImg = inbound)
  ]);

  var module = c.modules.usr[c.model.cfg.usrModule]!;
  return module(c, VlmPreUsrState(inImg, inRec));
}

Future<void> endpoint(InferenceTaskChannel c) async {
  var inUsr = await compute(runnerUsr, c);

  var inSmp = await computeMsg(runnerTranslateOut, c, inUsr);

  while(!inSmp.done) {
    var tsTts = computeMsg(runnerTts, c, inSmp.new_caption);
    var tsSmp = computeMsg(runnerTranslateOut, c, inUsr);

    await Future.wait([
      tsSmp.then((inbound) => inSmp = inbound),
      tsTts
    ]);
  }

  // The final one (may be empty if terminated with a properly punctuated sentence, like "word.</s>")
  await computeMsg(runnerTts, c, inSmp.new_caption);
  inSmp.free();
  c.out.send(OutMessage('!!DONE!!'));
}

// class VlmPrePromptState {
//   ffi.Pointer<llama_cpp_structs.llama_context> ctx_llama;
//   int n_tokens;

//   VlmPrePromptState(this.ctx_llama, this.n_tokens);
// }

class VlmConfig {
  int seed;
  double temp;
  int topK;
  double topP;
  double minP;
  int cpuThreads;
  int nCtx;
  bool systemPromptAddBos;
  String systemPrompt;
  String userPromptPrefix;
  String userPromptSuffix;
  String modelLang = 'en-US';
  String userLang = 'en-US'; // 'cs-CZ'
  String sysModule = '';
  String imgModule = '';
  String usrModule = '';
  String recModule = '';
  String ttsModule = '';
  String sampleModule = '';
  String translateInModule = '';
  String translateOutModule = '';

  VlmConfig({
    this.seed=0, this.temp=0.1, this.topK=40, this.topP=0.95, this.minP=0.05,
    this.cpuThreads=4, this.nCtx=2048,
    this.systemPromptAddBos = true,
    this.systemPrompt="A chat between a curious human and an artificial intelligence assistant. The assistant gives helpful, detailed, and polite answers to the human's questions.\nUSER:",
    this.userPromptPrefix = "",
    this.userPromptSuffix = "\nASSISTANT:",
    this.modelLang = 'en-US', this.userLang = 'en-US', 
    this.sysModule = '', this.imgModule = '', this.usrModule = '', this.recModule = '', this.ttsModule = '', this.sampleModule = '', this.translateInModule = '', this.translateOutModule = ''
  });
}

// class Vlm {
//   final String model_path;
//   final String mmproj_path;
//   final int seed;
//   final double temp;
//   final int top_k;
//   final double top_p;
//   final double min_p;
//   final int cpu_threads;
//   final int n_ctx;
//   final bool system_prompt_add_bos;
//   final String system_prompt;
//   final String user_prompt_prefix;
//   final String user_prompt_suffix;

//   final ffi.Pointer<llama_cpp_structs.llama_model> llama_model;
//   final ffi.Pointer<llava_cpp_structs.clip_ctx> ctx_clip;

//   // ffi.Pointer<llama_cpp_structs.llama_context_params> ctx_params;

//   // ffi.Pointer<llama_cpp_structs.llama_context> ctx_llama;
//   // ffi.Pointer<llama_cpp_structs.llama_context> ctx_llava;

//   Vlm(this.model_path, this.mmproj_path, {
//     this.seed=0, this.temp=0.1, this.top_k=40, this.top_p=0.95, this.min_p=0.05,
//     this.cpu_threads=4, this.n_ctx=2048,
//     this.system_prompt_add_bos = true,
//     this.system_prompt="A chat between a curious human and an artificial intelligence assistant. The assistant gives helpful, detailed, and polite answers to the human's questions.\nUSER:",
//     this.user_prompt_prefix = "",
//     this.user_prompt_suffix = "\nASSISTANT:",
//   }) : 
//     llama_model = llama_cpp.llama_load_model_from_file(model_path.toNativeUtf8().cast<ffi.Char>(), llama_cpp.llama_model_default_params()),
//     ctx_clip = llava_cpp.clip_model_load(mmproj_path, 1);

  

//   String processPrompt(String prompt, String img) {
//     var ctx_params = llama_cpp.llama_context_default_params();
//     ctx_params.n_ctx = n_ctx;
//     ctx_params.n_threads = cpu_threads;
//     ctx_params.n_threads_batch = cpu_threads;

//     llava_cpp.printStatus();

//     var ctx_llama = llama_cpp.llama_new_context_with_model(llama_model, ctx_params);
//     var embed = llava_cpp.llava_image_embed_make_with_filename(ctx_clip, cpu_threads, img);

//     var sysPromptNative = system_prompt.toNativeUtf8();
//     var usrPromptNative = (user_prompt_prefix + prompt + user_prompt_suffix).toNativeUtf8();

//     int n_tokens = sysPromptNative.length + 2 * (system_prompt_add_bos ? 1 : 0);
//     var tokensPtr = malloc.allocate<llama_cpp_structs.llama_token>(4 * n_tokens);
//     n_tokens = llama_cpp.llama_tokenize(llama_model, sysPromptNative.cast<ffi.Char>(), sysPromptNative.length, tokensPtr, n_tokens, system_prompt_add_bos, true);
//     llama_cpp.llama_decode(ctx_llama, llama_cpp.llama_batch_get_one(tokensPtr, n_tokens/*, 0, 0*/));
//     malloc.free(tokensPtr);

//     var n_pastPtr = malloc.allocate<ffi.Int>(4);
//     n_pastPtr.value = n_tokens;
//     llava_cpp.llava_eval_image_embed(ctx_llama, embed, ctx_params.n_batch, n_pastPtr);
//     var n_past = n_pastPtr.value;
//     malloc.free(n_pastPtr);

//     tokensPtr = malloc.allocate<llama_cpp_structs.llama_token>(4 * usrPromptNative.length);
//     n_tokens = llama_cpp.llama_tokenize(llama_model, usrPromptNative.cast<ffi.Char>(), usrPromptNative.length, tokensPtr, usrPromptNative.length, false, true);
//     llama_cpp.llama_decode(ctx_llama, llama_cpp.llama_batch_get_one(tokensPtr, n_tokens/*, n_past, 0*/));
//     n_past += n_tokens;
//     malloc.free(tokensPtr);

//     var sampler = makeSampler(seed: seed, temp: temp, top_k: top_k, top_p: top_p, min_p: min_p);
//     String caption = '';

//     int i = 0;
//     for (; i < 256; i++) {
//       var piece = sample(sampler, ctx_llama, n_past + i);
//       if(piece == '</s>' || piece.contains('###')) break;
//       caption += piece;
//       if(caption.contains('<|im_end|>') || caption.contains('<|im_start|>') || caption.contains('USER:') || caption.contains('<user>')) break;
//     }
//     print('sampling result: n_past $n_past, i $i');

//     return caption;
//   }

//   String sample(sampler, ctx_llama, n_past) {
//     var token = llama_cpp.llama_sampler_sample(sampler, ctx_llama, -1);
//     String piece;
//     if(!llama_cpp.llama_token_is_eog(llama_cpp.llama_get_model(ctx_llama), token))
//     {
//       var piecePtr = malloc.allocate<ffi.Char>(15);
//       var n_char = llama_cpp.llama_token_to_piece(llama_cpp.llama_get_model(ctx_llama), token, piecePtr, 15, 0, true);
//       piece = piecePtr.cast<ffi_also.Utf8>().toDartString(length: n_char);
//       malloc.free(piecePtr);
//     }
//     else
//     {
//       piece = '</s>';
//     }
//     var tokenPtr = malloc.allocate<llama_cpp_structs.llama_token>(4);
//     tokenPtr.value = token;
//     llama_cpp.llama_decode(ctx_llama, llama_cpp.llama_batch_get_one(tokenPtr, 1/*, n_past, 0*/));
//     malloc.free(tokenPtr);
//     return piece;
//   }

//   ffi.Pointer<llama_cpp_structs.llama_sampler> makeSampler({int seed=0, double temp=0.1, int top_k=40, double top_p=0.95, double min_p=0.05})
//   {
//     var chain = llama_cpp.llama_sampler_chain_init(llama_cpp.llama_sampler_chain_default_params());
//     llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_top_k(top_k));
//     llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_top_p(top_p, 0));
//     llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_min_p(min_p, 0));
//     llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_temp_ext(temp, 0.0, 1.0));
//     llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_softmax());
//     llama_cpp.llama_sampler_chain_add(chain, llama_cpp.llama_sampler_init_dist(seed));
//     return chain;
//   }
// }