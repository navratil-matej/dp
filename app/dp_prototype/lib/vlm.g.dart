import "package:dp_prototype/vlm.dart";

void registerModules() {
  Sys.reg[""] = defaultSys;
  Img.reg[""] = defaultImg;
  Usr.reg[""] = defaultUsr;
  Rec.reg[""] = defaultRec;
  Tts.reg[""] = defaultTts;
  Sample.reg[""] = defaultSample;
  TranslateIn.reg[""] = defaultTranslateIn;
  TranslateOut.reg[""] = defaultTranslateOut;
}
