// sherpa-onnx/csrc/offline-whisper-model-config.cc
//
// Copyright (c)  2023  Xiaomi Corporation

#include "sherpa-onnx/csrc/offline-whisper-model-config.h"

#include "sherpa-onnx/csrc/file-utils.h"
#include "sherpa-onnx/csrc/macros.h"

namespace sherpa_onnx {

void OfflineWhisperModelConfig::Register(ParseOptions *po) {
  po->Register("whisper-encoder", &encoder,
               "Path to onnx encoder of whisper, e.g., tiny-encoder.onnx, "
               "medium.en-encoder.onnx.");

  po->Register("whisper-decoder", &decoder,
               "Path to onnx decoder of whisper, e.g., tiny-decoder.onnx, "
               "medium.en-decoder.onnx.");

  po->Register(
      "whisper-language", &language,
      "The spoke language in the input audio file. Example values: "
      "en, de, fr, zh, jp. If it is not given for a multilingual model, we will"
      " infer the language from the input audio file. "
      "Please refer to "
      "https://github.com/openai/whisper/blob/main/whisper/tokenizer.py#L10"
      " for valid values. Note that for non-multilingual models, it supports "
      "only 'en'");

  po->Register("whisper-task", &task,
               "Valid values: transcribe, translate. "
               "Note that for non-multilingual models, it supports "
               "only 'transcribe'");
}

bool OfflineWhisperModelConfig::Validate() const {
  if (!FileExists(encoder)) {
    SHERPA_ONNX_LOGE("whisper encoder file %s does not exist", encoder.c_str());
    return false;
  }

  if (!FileExists(decoder)) {
    SHERPA_ONNX_LOGE("whisper decoder file %s does not exist", decoder.c_str());
    return false;
  }

  if (task != "translate" && task != "transcribe") {
    SHERPA_ONNX_LOGE(
        "--whisper-task supports only translate and transcribe. Given: %s",
        task.c_str());

    return false;
  }

  return true;
}

std::string OfflineWhisperModelConfig::ToString() const {
  std::ostringstream os;

  os << "OfflineWhisperModelConfig(";
  os << "encoder=\"" << encoder << "\", ";
  os << "decoder=\"" << decoder << "\", ";
  os << "language=\"" << language << "\", ";
  os << "task=\"" << task << "\")";

  return os.str();
}

}  // namespace sherpa_onnx
