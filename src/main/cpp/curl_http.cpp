#include <curl/curl.h>
#include <napi/native_api.h>

#include <algorithm>
#include <cctype>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

struct RequestContext {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  std::string url;
  std::string method = "GET";
  std::vector<std::pair<std::string, std::string>> headers;
  std::string body;
  long connectTimeoutMs = 10000;
  long timeoutMs = 10000;
  bool followRedirects = true;
  bool insecure = false;
  CURLcode curlCode = CURLE_OK;
  long statusCode = 0;
  std::string responseBody;
  std::unordered_map<std::string, std::string> responseHeaders;
  std::string effectiveUrl;
  std::string errorMessage;
};

std::once_flag curlInitFlag;

bool HasNamedProperty(napi_env env, napi_value object, const char *name) {
  bool hasProperty = false;
  return napi_has_named_property(env, object, name, &hasProperty) == napi_ok && hasProperty;
}

bool GetNamedString(napi_env env, napi_value object, const char *name, std::string &target) {
  if (!HasNamedProperty(env, object, name)) {
    return false;
  }
  napi_value value = nullptr;
  if (napi_get_named_property(env, object, name, &value) != napi_ok) {
    return false;
  }
  napi_valuetype valueType = napi_undefined;
  if (napi_typeof(env, value, &valueType) != napi_ok || valueType != napi_string) {
    return false;
  }
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
    return false;
  }
  std::vector<char> buffer(length + 1, '\0');
  if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
    return false;
  }
  target.assign(buffer.data(), length);
  return true;
}

bool GetNamedLong(napi_env env, napi_value object, const char *name, long &target) {
  if (!HasNamedProperty(env, object, name)) {
    return false;
  }
  napi_value value = nullptr;
  double number = 0;
  if (napi_get_named_property(env, object, name, &value) != napi_ok ||
      napi_get_value_double(env, value, &number) != napi_ok) {
    return false;
  }
  target = static_cast<long>(number);
  return true;
}

bool GetNamedBool(napi_env env, napi_value object, const char *name, bool &target) {
  if (!HasNamedProperty(env, object, name)) {
    return false;
  }
  napi_value value = nullptr;
  if (napi_get_named_property(env, object, name, &value) != napi_ok ||
      napi_get_value_bool(env, value, &target) != napi_ok) {
    return false;
  }
  return true;
}

std::string ValueToString(napi_env env, napi_value value) {
  napi_value stringValue = nullptr;
  if (napi_coerce_to_string(env, value, &stringValue) != napi_ok) {
    return {};
  }
  size_t length = 0;
  if (napi_get_value_string_utf8(env, stringValue, nullptr, 0, &length) != napi_ok) {
    return {};
  }
  std::vector<char> buffer(length + 1, '\0');
  if (napi_get_value_string_utf8(env, stringValue, buffer.data(), buffer.size(), &length) != napi_ok) {
    return {};
  }
  return std::string(buffer.data(), length);
}

void ReadHeaders(napi_env env, napi_value options, RequestContext &context) {
  if (!HasNamedProperty(env, options, "headers")) {
    return;
  }
  napi_value headers = nullptr;
  napi_valuetype headersType = napi_undefined;
  if (napi_get_named_property(env, options, "headers", &headers) != napi_ok ||
      napi_typeof(env, headers, &headersType) != napi_ok || headersType != napi_object) {
    return;
  }

  napi_value names = nullptr;
  uint32_t length = 0;
  if (napi_get_property_names(env, headers, &names) != napi_ok ||
      napi_get_array_length(env, names, &length) != napi_ok) {
    return;
  }
  for (uint32_t index = 0; index < length; ++index) {
    napi_value key = nullptr;
    napi_value value = nullptr;
    if (napi_get_element(env, names, index, &key) != napi_ok ||
        napi_get_property(env, headers, key, &value) != napi_ok) {
      continue;
    }
    std::string keyString = ValueToString(env, key);
    std::string valueString = ValueToString(env, value);
    if (!keyString.empty()) {
      context.headers.emplace_back(std::move(keyString), std::move(valueString));
    }
  }
}

size_t WriteBody(char *data, size_t size, size_t count, void *userData) {
  const size_t bytes = size * count;
  auto *context = static_cast<RequestContext *>(userData);
  context->responseBody.append(data, bytes);
  return bytes;
}

std::string Trim(std::string value) {
  const auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char character) {
    return std::isspace(character) != 0;
  });
  const auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char character) {
    return std::isspace(character) != 0;
  }).base();
  if (first >= last) {
    return {};
  }
  return std::string(first, last);
}

size_t WriteHeader(char *data, size_t size, size_t count, void *userData) {
  const size_t bytes = size * count;
  auto *context = static_cast<RequestContext *>(userData);
  std::string line(data, bytes);
  const size_t separator = line.find(':');
  if (separator == std::string::npos) {
    return bytes;
  }
  std::string name = Trim(line.substr(0, separator));
  std::string value = Trim(line.substr(separator + 1));
  if (name.empty()) {
    return bytes;
  }
  std::transform(name.begin(), name.end(), name.begin(), [](unsigned char character) {
    return static_cast<char>(std::tolower(character));
  });
  auto existing = context->responseHeaders.find(name);
  if (existing == context->responseHeaders.end()) {
    context->responseHeaders.emplace(std::move(name), std::move(value));
  } else {
    existing->second.append(", ").append(value);
  }
  return bytes;
}

void ExecuteRequest(napi_env, void *data) {
  auto *context = static_cast<RequestContext *>(data);
  CURL *curl = curl_easy_init();
  if (curl == nullptr) {
    context->curlCode = CURLE_FAILED_INIT;
    context->errorMessage = "curl_easy_init failed";
    return;
  }

  char errorBuffer[CURL_ERROR_SIZE] = {0};
  curl_slist *headerList = nullptr;
  for (const auto &header : context->headers) {
    const std::string line = header.first + ": " + header.second;
    headerList = curl_slist_append(headerList, line.c_str());
  }

  curl_easy_setopt(curl, CURLOPT_URL, context->url.c_str());
  curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(curl, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
  curl_easy_setopt(curl, CURLOPT_PROXY, "");
  curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, std::max(1L, context->connectTimeoutMs));
  curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, std::max(1L, context->timeoutMs));
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, context->followRedirects ? 1L : 0L);
  curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 10L);
  curl_easy_setopt(curl, CURLOPT_USERAGENT, "chindeo-ohos-curl/1.0");
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, context->insecure ? 0L : 1L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, context->insecure ? 0L : 2L);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteBody);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, context);
  curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, WriteHeader);
  curl_easy_setopt(curl, CURLOPT_HEADERDATA, context);
  curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errorBuffer);
  if (headerList != nullptr) {
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headerList);
  }

  if (context->method == "HEAD") {
    curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
  } else if (context->method == "POST") {
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
  } else if (context->method != "GET") {
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, context->method.c_str());
  }
  if (!context->body.empty() && context->method != "GET" && context->method != "HEAD") {
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, context->body.data());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(context->body.size()));
  }

  context->curlCode = curl_easy_perform(curl);
  if (context->curlCode == CURLE_OK) {
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &context->statusCode);
    char *effectiveUrl = nullptr;
    if (curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &effectiveUrl) == CURLE_OK && effectiveUrl != nullptr) {
      context->effectiveUrl = effectiveUrl;
    }
  } else if (errorBuffer[0] != '\0') {
    context->errorMessage = errorBuffer;
  } else {
    context->errorMessage = curl_easy_strerror(context->curlCode);
  }

  curl_slist_free_all(headerList);
  curl_easy_cleanup(curl);
}

void SetNamedString(napi_env env, napi_value object, const char *name, const std::string &value) {
  napi_value jsValue = nullptr;
  napi_create_string_utf8(env, value.c_str(), value.size(), &jsValue);
  napi_set_named_property(env, object, name, jsValue);
}

void SetNamedInt(napi_env env, napi_value object, const char *name, int32_t value) {
  napi_value jsValue = nullptr;
  napi_create_int32(env, value, &jsValue);
  napi_set_named_property(env, object, name, jsValue);
}

void CompleteRequest(napi_env env, napi_status status, void *data) {
  auto *context = static_cast<RequestContext *>(data);
  if (status != napi_ok || context->curlCode != CURLE_OK) {
    const int32_t curlCode = status == napi_ok ? static_cast<int32_t>(context->curlCode) : -1;
    const int32_t errorCode = curlCode > 0 ? 2300000 + curlCode : 2300999;
    const std::string message = context->errorMessage.empty() ? "Native curl request failed" : context->errorMessage;
    napi_value jsMessage = nullptr;
    napi_value error = nullptr;
    napi_create_string_utf8(env, message.c_str(), message.size(), &jsMessage);
    napi_create_error(env, nullptr, jsMessage, &error);
    SetNamedString(env, error, "code", std::to_string(errorCode));
    SetNamedInt(env, error, "curlCode", curlCode);
    SetNamedString(env, error, "url", context->url);
    napi_reject_deferred(env, context->deferred, error);
  } else {
    napi_value response = nullptr;
    napi_value headers = nullptr;
    napi_create_object(env, &response);
    napi_create_object(env, &headers);
    SetNamedInt(env, response, "status", static_cast<int32_t>(context->statusCode));
    SetNamedString(env, response, "body", context->responseBody);
    SetNamedString(env, response, "effectiveUrl", context->effectiveUrl);
    for (const auto &header : context->responseHeaders) {
      SetNamedString(env, headers, header.first.c_str(), header.second);
    }
    napi_set_named_property(env, response, "headers", headers);
    napi_resolve_deferred(env, context->deferred, response);
  }
  napi_delete_async_work(env, context->work);
  delete context;
}

napi_value Request(napi_env env, napi_callback_info info) {
  size_t argumentCount = 1;
  napi_value arguments[1] = {nullptr};
  napi_get_cb_info(env, info, &argumentCount, arguments, nullptr, nullptr);
  if (argumentCount != 1) {
    napi_throw_type_error(env, nullptr, "request(options) requires one argument");
    return nullptr;
  }
  napi_valuetype argumentType = napi_undefined;
  napi_typeof(env, arguments[0], &argumentType);
  if (argumentType != napi_object) {
    napi_throw_type_error(env, nullptr, "request options must be an object");
    return nullptr;
  }

  auto *context = new RequestContext();
  if (!GetNamedString(env, arguments[0], "url", context->url) || context->url.empty()) {
    delete context;
    napi_throw_type_error(env, nullptr, "request options.url must be a non-empty string");
    return nullptr;
  }
  GetNamedString(env, arguments[0], "method", context->method);
  std::transform(context->method.begin(), context->method.end(), context->method.begin(), [](unsigned char character) {
    return static_cast<char>(std::toupper(character));
  });
  GetNamedString(env, arguments[0], "body", context->body);
  GetNamedLong(env, arguments[0], "connectTimeoutMs", context->connectTimeoutMs);
  GetNamedLong(env, arguments[0], "timeoutMs", context->timeoutMs);
  GetNamedBool(env, arguments[0], "followRedirects", context->followRedirects);
  GetNamedBool(env, arguments[0], "insecure", context->insecure);
  ReadHeaders(env, arguments[0], *context);

  napi_value promise = nullptr;
  napi_value resourceName = nullptr;
  napi_create_promise(env, &context->deferred, &promise);
  napi_create_string_utf8(env, "curl-http-request", NAPI_AUTO_LENGTH, &resourceName);
  napi_create_async_work(env, nullptr, resourceName, ExecuteRequest, CompleteRequest, context, &context->work);
  napi_queue_async_work(env, context->work);
  return promise;
}

napi_value Init(napi_env env, napi_value exports) {
  std::call_once(curlInitFlag, []() {
    curl_global_init(CURL_GLOBAL_DEFAULT);
  });
  napi_property_descriptor properties[] = {
    {"request", nullptr, Request, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  return exports;
}

}  // namespace

extern "C" {
static napi_module curlHttpModule = {
  1,
  0,
  nullptr,
  Init,
  "curl_http",
  nullptr,
  {0}
};

__attribute__((constructor)) void RegisterCurlHttpModule() {
  napi_module_register(&curlHttpModule);
}
}
