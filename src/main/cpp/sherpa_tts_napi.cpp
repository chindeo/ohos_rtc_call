// napi shim for sherpa-onnx offline TTS on OpenHarmony (armeabi-v7a / softfp).
//
// Struct layouts are copied from sherpa-onnx v1.12.18
// sherpa-onnx/c-api/c-api.h:1019-1100 and must stay in sync with the shipped
// libsherpa-onnx-c-api.so, otherwise SherpaOnnxCreateOfflineTts reads garbage.
#include <dlfcn.h>
#include <hilog/log.h>
#include <napi/native_api.h>

#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

constexpr uint32_t kLogDomain = 0;
const char* kTag = "SherpaShim";

struct SherpaOnnxOfflineTtsVitsModelConfig {
  const char* model;
  const char* lexicon;
  const char* tokens;
  const char* data_dir;
  float noise_scale;
  float noise_scale_w;
  float length_scale;
  const char* dict_dir;
};

struct SherpaOnnxOfflineTtsMatchaModelConfig {
  const char* acoustic_model;
  const char* vocoder;
  const char* lexicon;
  const char* tokens;
  const char* data_dir;
  float noise_scale;
  float length_scale;
  const char* dict_dir;
};

struct SherpaOnnxOfflineTtsKokoroModelConfig {
  const char* model;
  const char* voices;
  const char* tokens;
  const char* data_dir;
  float length_scale;
  const char* dict_dir;
  const char* lexicon;
  const char* lang;
};

struct SherpaOnnxOfflineTtsKittenModelConfig {
  const char* model;
  const char* voices;
  const char* tokens;
  const char* data_dir;
  float length_scale;
};

struct SherpaOnnxOfflineTtsZipvoiceModelConfig {
  const char* tokens;
  const char* text_model;
  const char* flow_matching_model;
  const char* vocoder;
  const char* data_dir;
  const char* pinyin_dict;
  float feat_scale;
  float t_shift;
  float target_rms;
  float guidance_scale;
};

struct SherpaOnnxOfflineTtsModelConfig {
  SherpaOnnxOfflineTtsVitsModelConfig vits;
  int32_t num_threads;
  int32_t debug;
  const char* provider;
  SherpaOnnxOfflineTtsMatchaModelConfig matcha;
  SherpaOnnxOfflineTtsKokoroModelConfig kokoro;
  SherpaOnnxOfflineTtsKittenModelConfig kitten;
  SherpaOnnxOfflineTtsZipvoiceModelConfig zipvoice;
};

struct SherpaOnnxOfflineTtsConfig {
  SherpaOnnxOfflineTtsModelConfig model;
  const char* rule_fsts;
  int32_t max_num_sentences;
  const char* rule_fars;
  float silence_scale;
};

struct SherpaOnnxGeneratedAudio {
  const float* samples;
  int32_t n;
  int32_t sample_rate;
};

struct SherpaOnnxOfflineTts;

using TtsEngine = const SherpaOnnxOfflineTts*;
using CreateFn = TtsEngine (*)(const SherpaOnnxOfflineTtsConfig*);
using DestroyFn = void (*)(TtsEngine);
using GenerateFn = const SherpaOnnxGeneratedAudio* (*)(TtsEngine, const char*, int32_t, float);
using DestroyAudioFn = void (*)(const SherpaOnnxGeneratedAudio*);
using SampleRateFn = int32_t (*)(TtsEngine);
using NumSpeakersFn = int32_t (*)(TtsEngine);

CreateFn FnCreate = nullptr;
DestroyFn FnDestroy = nullptr;
GenerateFn FnGenerate = nullptr;
DestroyAudioFn FnDestroyAudio = nullptr;
SampleRateFn FnSampleRate = nullptr;
NumSpeakersFn FnNumSpeakers = nullptr;

// The HAP app namespace ignores RUNPATH=$ORIGIN, so sibling app .so files are
// not resolvable through DT_NEEDED. They are dlopened from this module's own
// directory in dependency order, then the C API is bound from RTLD_DEFAULT.
const char* kLoadOrder[] = {
  "libc++_shared.so",
  "libonnxruntime.so",
  "libcargs.so",
  "libsherpa-onnx-c-api.so",
};

// create and generate share one engine instance and sherpa's generate is not
// thread-safe, so every call into the C API is serialized here.
std::mutex gApiMutex;
bool gBound = false;

// Handles are index + 1 so that 0 keeps meaning "no engine" for the ArkTS side.
std::vector<TtsEngine> gEngines;

std::string SelfDir() {
  Dl_info info;
  if (dladdr(reinterpret_cast<void*>(&SelfDir), &info) == 0 || info.dli_fname == nullptr) {
    return "";
  }
  const std::string path(info.dli_fname);
  const size_t pos = path.find_last_of('/');
  return pos == std::string::npos ? std::string("./") : path.substr(0, pos + 1);
}

bool BindSherpa() {
  if (gBound) {
    return true;
  }
  const std::string dir = SelfDir();
  if (dir.empty()) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kTag, "dladdr gave no path");
    return false;
  }
  for (const char* name : kLoadOrder) {
    const std::string full = dir + name;
    if (dlopen(full.c_str(), RTLD_LAZY | RTLD_GLOBAL) == nullptr) {
      OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kTag, "dlopen %{public}s failed: %{public}s",
                   full.c_str(), dlerror());
      return false;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, kTag, "dlopen %{public}s ok", full.c_str());
  }
  FnCreate = reinterpret_cast<CreateFn>(dlsym(RTLD_DEFAULT, "SherpaOnnxCreateOfflineTts"));
  FnDestroy = reinterpret_cast<DestroyFn>(dlsym(RTLD_DEFAULT, "SherpaOnnxDestroyOfflineTts"));
  FnGenerate = reinterpret_cast<GenerateFn>(dlsym(RTLD_DEFAULT, "SherpaOnnxOfflineTtsGenerate"));
  FnDestroyAudio =
    reinterpret_cast<DestroyAudioFn>(dlsym(RTLD_DEFAULT, "SherpaOnnxDestroyOfflineTtsGeneratedAudio"));
  FnSampleRate = reinterpret_cast<SampleRateFn>(dlsym(RTLD_DEFAULT, "SherpaOnnxOfflineTtsSampleRate"));
  FnNumSpeakers =
    reinterpret_cast<NumSpeakersFn>(dlsym(RTLD_DEFAULT, "SherpaOnnxOfflineTtsNumSpeakers"));
  if (FnCreate == nullptr || FnDestroy == nullptr || FnGenerate == nullptr ||
      FnDestroyAudio == nullptr || FnSampleRate == nullptr || FnNumSpeakers == nullptr) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kTag, "sherpa symbols not bound");
    return false;
  }
  gBound = true;
  OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, kTag, "sherpa symbols bound");
  return true;
}

bool ValueToString(napi_env env, napi_value value, std::string& out) {
  napi_valuetype type = napi_undefined;
  if (napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
    return false;
  }
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
    return false;
  }
  std::vector<char> buffer(length + 1, '\0');
  size_t written = 0;
  if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &written) != napi_ok) {
    return false;
  }
  out.assign(buffer.data(), written);
  return true;
}

bool ReadString(napi_env env, napi_value object, const char* name, std::string& out) {
  bool has = false;
  if (napi_has_named_property(env, object, name, &has) != napi_ok || !has) {
    return false;
  }
  napi_value value = nullptr;
  return napi_get_named_property(env, object, name, &value) == napi_ok && ValueToString(env, value, out);
}

bool ReadNumber(napi_env env, napi_value object, const char* name, double& out) {
  bool has = false;
  if (napi_has_named_property(env, object, name, &has) != napi_ok || !has) {
    return false;
  }
  napi_value value = nullptr;
  if (napi_get_named_property(env, object, name, &value) != napi_ok) {
    return false;
  }
  napi_valuetype type = napi_undefined;
  if (napi_typeof(env, value, &type) != napi_ok || type != napi_number) {
    return false;
  }
  return napi_get_value_double(env, value, &out) == napi_ok;
}

struct CreateRequest {
  std::string acousticModel;
  std::string vocoder;
  std::string lexicon;
  std::string tokens;
  std::string dataDir;
  std::string ruleFsts;
  float noiseScale = 0.666f;
  float lengthScale = 1.0f;
  int32_t numThreads = 4;
  TtsEngine engine = nullptr;
  std::string error;
};

struct GenerateRequest {
  TtsEngine engine = nullptr;
  std::string text;
  int32_t sid = 0;
  float speed = 1.0f;
  const SherpaOnnxGeneratedAudio* audio = nullptr;
  std::string error;
};

template <typename Request>
struct AsyncCall {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  Request request;
};

bool ParseCreateRequest(napi_env env, napi_value arg, CreateRequest& req, std::string& error) {
  napi_valuetype type = napi_undefined;
  if (napi_typeof(env, arg, &type) != napi_ok || type != napi_object) {
    error = "config must be an object";
    return false;
  }
  ReadString(env, arg, "acousticModel", req.acousticModel);
  ReadString(env, arg, "vocoder", req.vocoder);
  ReadString(env, arg, "lexicon", req.lexicon);
  ReadString(env, arg, "tokens", req.tokens);
  ReadString(env, arg, "ruleFsts", req.ruleFsts);
  // data_dir points at the folder holding espeak-ng-data; matcha-icefall-zh-en
  // needs it to pronounce Latin letters at all.
  ReadString(env, arg, "dataDir", req.dataDir);
  double number = 0;
  if (ReadNumber(env, arg, "noiseScale", number)) {
    req.noiseScale = static_cast<float>(number);
  }
  if (ReadNumber(env, arg, "lengthScale", number)) {
    req.lengthScale = static_cast<float>(number);
  }
  if (ReadNumber(env, arg, "numThreads", number)) {
    req.numThreads = static_cast<int32_t>(number);
  }
  if (req.acousticModel.empty() || req.vocoder.empty() || req.lexicon.empty() || req.tokens.empty()) {
    error = "acousticModel/vocoder/lexicon/tokens are required";
    return false;
  }
  return true;
}

void RunCreate(CreateRequest& req) {
  SherpaOnnxOfflineTtsConfig config = {};
  config.model.matcha.acoustic_model = req.acousticModel.c_str();
  config.model.matcha.vocoder = req.vocoder.c_str();
  config.model.matcha.lexicon = req.lexicon.c_str();
  config.model.matcha.tokens = req.tokens.c_str();
  config.model.matcha.data_dir = req.dataDir.empty() ? nullptr : req.dataDir.c_str();
  config.model.matcha.noise_scale = req.noiseScale;
  config.model.matcha.length_scale = req.lengthScale;
  config.model.num_threads = req.numThreads;
  config.rule_fsts = req.ruleFsts.empty() ? nullptr : req.ruleFsts.c_str();
  // 上游把这两个标量给了默认值（offline-tts.h: max_num_sentences=1, silence_scale=0.2），
  // 但 C API 的结构体没有默认值，零初始化会让 OfflineTts::Validate 直接判
  // "Errors in config" 并返回 null —— 真机上表现成"TTS 未初始化"。
  config.max_num_sentences = 1;
  config.silence_scale = 0.2f;
  {
    const std::lock_guard<std::mutex> lock(gApiMutex);
    req.engine = FnCreate(&config);
  }
  if (req.engine == nullptr) {
    req.error = "SherpaOnnxCreateOfflineTts returned null";
  }
}

void RunGenerate(GenerateRequest& req) {
  const std::lock_guard<std::mutex> lock(gApiMutex);
  req.audio = FnGenerate(req.engine, req.text.c_str(), req.sid, req.speed);
  if (req.audio == nullptr) {
    req.error = "SherpaOnnxOfflineTtsGenerate returned null";
  }
}

uint32_t RegisterEngine(TtsEngine engine) {
  const std::lock_guard<std::mutex> lock(gApiMutex);
  gEngines.push_back(engine);
  return static_cast<uint32_t>(gEngines.size());
}

TtsEngine EngineAt(uint32_t handle) {
  const std::lock_guard<std::mutex> lock(gApiMutex);
  if (handle == 0 || handle > gEngines.size()) {
    return nullptr;
  }
  return gEngines[handle - 1];
}

bool ReadHandleAndText(napi_env env, napi_callback_info info, uint32_t& handle,
                       GenerateRequest& req, std::string& error) {
  size_t argc = 4;
  napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2) {
    error = "generate(handle, text, sid, speed) expected";
    return false;
  }
  if (napi_get_value_uint32(env, argv[0], &handle) != napi_ok || handle == 0) {
    error = "invalid handle";
    return false;
  }
  if (!ValueToString(env, argv[1], req.text)) {
    error = "text must be a string";
    return false;
  }
  double number = 0;
  if (argc > 2 && napi_get_value_double(env, argv[2], &number) == napi_ok) {
    req.sid = static_cast<int32_t>(number);
  }
  if (argc > 3 && napi_get_value_double(env, argv[3], &number) == napi_ok) {
    req.speed = static_cast<float>(number);
  }
  req.engine = EngineAt(handle);
  if (req.engine == nullptr) {
    error = "unknown handle";
    return false;
  }
  return true;
}

napi_value BuildAudioResult(napi_env env, const SherpaOnnxGeneratedAudio* audio) {
  const int32_t count = audio != nullptr ? audio->n : 0;
  napi_value result = nullptr;
  napi_create_object(env, &result);

  napi_value sampleRate = nullptr;
  napi_create_int32(env, audio != nullptr ? audio->sample_rate : 0, &sampleRate);
  napi_set_named_property(env, result, "sampleRate", sampleRate);

  void* data = nullptr;
  napi_value buffer = nullptr;
  const size_t bytes = count > 0 ? static_cast<size_t>(count) * sizeof(float) : 0;
  if (napi_create_arraybuffer(env, bytes, &data, &buffer) != napi_ok) {
    return result;
  }
  if (bytes > 0) {
    std::memcpy(data, audio->samples, bytes);
  }
  napi_value samples = nullptr;
  if (napi_create_typedarray(env, napi_float32_array, count > 0 ? count : 0, buffer, 0, &samples) ==
      napi_ok) {
    napi_set_named_property(env, result, "samples", samples);
  }
  return result;
}

void FreeAudio(const SherpaOnnxGeneratedAudio* audio) {
  if (audio == nullptr) {
    return;
  }
  const std::lock_guard<std::mutex> lock(gApiMutex);
  FnDestroyAudio(audio);
}

napi_value Throw(napi_env env, const std::string& message) {
  napi_throw_error(env, nullptr, message.c_str());
  return nullptr;
}

void Reject(napi_env env, napi_deferred deferred, const std::string& message) {
  // 真机上这里曾经是唯一的失败出口，之前 reject 的是裸字符串，宿主侧 catch 到的
  // error.message 打成 undefined，排查时看不出到底哪一步失败，所以先落一条原生日志。
  OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kTag, "reject: %{public}s", message.c_str());
  napi_value reason = nullptr;
  napi_value messageValue = nullptr;
  if (napi_create_string_utf8(env, message.c_str(), NAPI_AUTO_LENGTH, &messageValue) == napi_ok &&
      napi_create_error(env, nullptr, messageValue, &reason) == napi_ok) {
    napi_reject_deferred(env, deferred, reason);
    return;
  }
  napi_create_string_utf8(env, message.c_str(), NAPI_AUTO_LENGTH, &reason);
  napi_reject_deferred(env, deferred, reason);
}

bool QueueWork(napi_env env, const char* name, napi_async_execute_callback execute,
               napi_async_complete_callback complete, void* data, napi_async_work* work) {
  napi_value resourceName = nullptr;
  if (napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &resourceName) != napi_ok) {
    return false;
  }
  return napi_create_async_work(env, nullptr, resourceName, execute, complete, data, work) ==
    napi_ok;
}

napi_value Create(napi_env env, napi_callback_info info) {
  if (!BindSherpa()) {
    return Throw(env, "sherpa libraries unavailable");
  }
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
    return Throw(env, "create(config) expected");
  }
  CreateRequest req;
  std::string error;
  if (!ParseCreateRequest(env, argv[0], req, error)) {
    return Throw(env, error);
  }
  RunCreate(req);
  if (req.engine == nullptr) {
    return Throw(env, req.error);
  }
  napi_value value = nullptr;
  napi_create_uint32(env, RegisterEngine(req.engine), &value);
  return value;
}

napi_value Generate(napi_env env, napi_callback_info info) {
  if (!BindSherpa()) {
    return Throw(env, "sherpa libraries unavailable");
  }
  uint32_t handle = 0;
  GenerateRequest req;
  std::string error;
  if (!ReadHandleAndText(env, info, handle, req, error)) {
    return Throw(env, error);
  }
  RunGenerate(req);
  napi_value result = BuildAudioResult(env, req.audio);
  FreeAudio(req.audio);
  return result;
}

napi_value Destroy(napi_env env, napi_callback_info info) {
  if (!BindSherpa()) {
    return nullptr;
  }
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  uint32_t handle = 0;
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1 ||
      napi_get_value_uint32(env, argv[0], &handle) != napi_ok) {
    return nullptr;
  }
  TtsEngine engine = EngineAt(handle);
  if (engine != nullptr) {
    const std::lock_guard<std::mutex> lock(gApiMutex);
    FnDestroy(engine);
    gEngines[handle - 1] = nullptr;
  }
  return nullptr;
}

napi_value SampleRate(napi_env env, napi_callback_info info) {
  if (!BindSherpa()) {
    return Throw(env, "sherpa libraries unavailable");
  }
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  uint32_t handle = 0;
  int32_t rate = 0;
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) == napi_ok && argc >= 1 &&
      napi_get_value_uint32(env, argv[0], &handle) == napi_ok) {
    TtsEngine engine = EngineAt(handle);
    if (engine != nullptr) {
      const std::lock_guard<std::mutex> lock(gApiMutex);
      rate = FnSampleRate(engine);
    }
  }
  napi_value value = nullptr;
  napi_create_int32(env, rate, &value);
  return value;
}

napi_value NumSpeakers(napi_env env, napi_callback_info info) {
  if (!BindSherpa()) {
    return Throw(env, "sherpa libraries unavailable");
  }
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  uint32_t handle = 0;
  int32_t speakers = 0;
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) == napi_ok && argc >= 1 &&
      napi_get_value_uint32(env, argv[0], &handle) == napi_ok) {
    TtsEngine engine = EngineAt(handle);
    if (engine != nullptr) {
      const std::lock_guard<std::mutex> lock(gApiMutex);
      speakers = FnNumSpeakers(engine);
    }
  }
  napi_value value = nullptr;
  napi_create_int32(env, speakers, &value);
  return value;
}

void CreateExecute(napi_env, void* data) {
  auto* call = static_cast<AsyncCall<CreateRequest>*>(data);
  RunCreate(call->request);
}

void CreateComplete(napi_env env, napi_status, void* data) {
  auto* call = static_cast<AsyncCall<CreateRequest>*>(data);
  if (call->request.engine == nullptr) {
    Reject(env, call->deferred, call->request.error);
  } else {
    napi_value value = nullptr;
    napi_create_uint32(env, RegisterEngine(call->request.engine), &value);
    napi_resolve_deferred(env, call->deferred, value);
  }
  napi_delete_async_work(env, call->work);
  delete call;
}

void GenerateExecute(napi_env, void* data) {
  auto* call = static_cast<AsyncCall<GenerateRequest>*>(data);
  RunGenerate(call->request);
}

void GenerateComplete(napi_env env, napi_status, void* data) {
  auto* call = static_cast<AsyncCall<GenerateRequest>*>(data);
  napi_value result = BuildAudioResult(env, call->request.audio);
  FreeAudio(call->request.audio);
  napi_resolve_deferred(env, call->deferred, result);
  napi_delete_async_work(env, call->work);
  delete call;
}

napi_value CreateAsync(napi_env env, napi_callback_info info) {
  napi_value promise = nullptr;
  napi_deferred deferred = nullptr;
  if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
    return nullptr;
  }
  if (!BindSherpa()) {
    Reject(env, deferred, "sherpa libraries unavailable");
    return promise;
  }
  auto* call = new AsyncCall<CreateRequest>();
  call->deferred = deferred;
  std::string error;
  size_t argc = 1;
  napi_value argv[1] = {nullptr};
  const bool parsed = napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) == napi_ok &&
    argc >= 1 && ParseCreateRequest(env, argv[0], call->request, error);
  if (!parsed) {
    if (error.empty()) {
      error = "createAsync(config) expected";
    }
    delete call;
    Reject(env, deferred, error);
    return promise;
  }
  if (!QueueWork(env, "sherpa_tts_create", CreateExecute, CreateComplete, call, &call->work)) {
    delete call;
    Reject(env, deferred, "napi_create_async_work failed");
    return promise;
  }
  napi_queue_async_work(env, call->work);
  return promise;
}

napi_value GenerateAsync(napi_env env, napi_callback_info info) {
  napi_value promise = nullptr;
  napi_deferred deferred = nullptr;
  if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
    return nullptr;
  }
  if (!BindSherpa()) {
    Reject(env, deferred, "sherpa libraries unavailable");
    return promise;
  }
  auto* call = new AsyncCall<GenerateRequest>();
  call->deferred = deferred;
  std::string error;
  uint32_t handle = 0;
  if (!ReadHandleAndText(env, info, handle, call->request, error)) {
    delete call;
    Reject(env, deferred, error);
    return promise;
  }
  if (!QueueWork(env, "sherpa_tts_generate", GenerateExecute, GenerateComplete, call,
                 &call->work)) {
    delete call;
    Reject(env, deferred, "napi_create_async_work failed");
    return promise;
  }
  napi_queue_async_work(env, call->work);
  return promise;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor props[] = {
    {"create", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"createAsync", nullptr, CreateAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"destroy", nullptr, Destroy, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"generate", nullptr, Generate, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"generateAsync", nullptr, GenerateAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"sampleRate", nullptr, SampleRate, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"numSpeakers", nullptr, NumSpeakers, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(props) / sizeof(props[0]), props);
  return exports;
}

}  // namespace

extern "C" {
static napi_module sherpaOnnxModule = {
  1,
  0,
  nullptr,
  Init,
  "sherpa_onnx",
  nullptr,
  {0}
};

__attribute__((constructor)) void RegisterSherpaOnnxModule() {
  napi_module_register(&sherpaOnnxModule);
}
}
