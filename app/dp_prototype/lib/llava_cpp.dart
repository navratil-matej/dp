// ignore_for_file: non_constant_identifier_names, camel_case_types

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart'; // ???

// import 'package:llama_cpp_dart/src/llama_cpp.dart' as llama_cpp;
import 'llama_cpp.dart' as llama_cpp;



final class llava_image_embed extends ffi.Struct {
  external ffi.Pointer<ffi.Float> embed;

  @ffi.Int()
  external int n_image_pos;
}

typedef clip_ctx = ffi.Opaque;

class llava_cpp {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  llava_cpp(ffi.DynamicLibrary dynamicLibrary): _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  llava_cpp.fromLookup(ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup): _lookup = lookup;


  ffi.Pointer<clip_ctx> clip_model_load(String name, int verbosity) {
    return _clip_model_load(name.toNativeUtf8(), verbosity);
  }

  late final _clip_model_loadPtr = 
    _lookup<ffi.NativeFunction<ffi.Pointer<clip_ctx> Function(ffi.Pointer<Utf8>, ffi.Int)>>(
      'clip_model_load'
    );
  late final _clip_model_load = _clip_model_loadPtr
    .asFunction<ffi.Pointer<clip_ctx> Function(ffi.Pointer<Utf8>, int)>();
  

  ffi.Pointer<llava_image_embed> llava_image_embed_make_with_filename(ffi.Pointer<clip_ctx> ctx_clip, int n_threads, String image_path) {
    return _llava_image_embed_make_with_filename(ctx_clip, n_threads, image_path.toNativeUtf8());
  }

  late final _llava_image_embed_make_with_filenamePtr = 
    _lookup<ffi.NativeFunction<ffi.Pointer<llava_image_embed> Function(ffi.Pointer<clip_ctx>, ffi.Int, ffi.Pointer<Utf8>)>>(
      'llava_image_embed_make_with_filename'
    );
  late final _llava_image_embed_make_with_filename = _llava_image_embed_make_with_filenamePtr
    .asFunction<ffi.Pointer<llava_image_embed> Function(ffi.Pointer<clip_ctx>, int, ffi.Pointer<Utf8>)>();


  bool llava_eval_image_embed(ffi.Pointer<llama_cpp.llama_context> ctx_llama, ffi.Pointer<llava_image_embed> embed, int n_batch, ffi.Pointer<ffi.Int> n_past) {
    return _llava_eval_image_embed(ctx_llama, embed, n_batch, n_past);
  }

  late final _llava_eval_image_embedPtr = 
    _lookup<ffi.NativeFunction<ffi.Bool Function(ffi.Pointer<llama_cpp.llama_context>, ffi.Pointer<llava_image_embed>, ffi.Int, ffi.Pointer<ffi.Int>)>>(
      'llava_eval_image_embed'
    );
  late final _llava_eval_image_embed = _llava_eval_image_embedPtr
    .asFunction<bool Function(ffi.Pointer<llama_cpp.llama_context>, ffi.Pointer<llava_image_embed>, int, ffi.Pointer<ffi.Int>)>();
  

  void llava_image_embed_free(ffi.Pointer<llava_image_embed> embed) {
    return _llava_image_embed_free(embed);
  }

  late final _llava_image_embed_freePtr = 
    _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<llava_image_embed>)>>(
      'llava_image_embed_free'
    );
  late final _llava_image_embed_free = _llava_image_embed_freePtr
    .asFunction<void Function(ffi.Pointer<llava_image_embed>)>();
  

  void clip_free(ffi.Pointer<clip_ctx> ctx_clip) {
    return _clip_free(ctx_clip);
  }

  late final _clip_freePtr = 
    _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<clip_ctx>)>>(
      'clip_free'
    );
  late final _clip_free = _clip_freePtr
    .asFunction<void Function(ffi.Pointer<clip_ctx>)>();

  void printStatus() {
    print('$_clip_freePtr, $_clip_model_loadPtr, $_llava_eval_image_embedPtr, $_llava_image_embed_freePtr, $_llava_image_embed_make_with_filenamePtr');
  }
}