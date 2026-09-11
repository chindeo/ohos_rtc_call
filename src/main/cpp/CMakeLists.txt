cmake_minimum_required(VERSION 3.5.0)
project(curl_http)

if(NOT DEFINED CURL_SOURCE_ROOT)
  message(FATAL_ERROR "CURL_SOURCE_ROOT is required")
endif()
if(NOT DEFINED CURL_BUILD_ROOT)
  message(FATAL_ERROR "CURL_BUILD_ROOT is required")
endif()
if(NOT DEFINED OPENSSL_BUILD_ROOT)
  message(FATAL_ERROR "OPENSSL_BUILD_ROOT is required")
endif()

add_library(curl_http SHARED curl_http.cpp)

add_library(curl_static STATIC IMPORTED)
set_target_properties(curl_static PROPERTIES
  IMPORTED_LOCATION "${CURL_BUILD_ROOT}/lib/libcurl.a")

add_library(ssl_static STATIC IMPORTED)
set_target_properties(ssl_static PROPERTIES
  IMPORTED_LOCATION "${OPENSSL_BUILD_ROOT}/libssl.a")

add_library(crypto_static STATIC IMPORTED)
set_target_properties(crypto_static PROPERTIES
  IMPORTED_LOCATION "${OPENSSL_BUILD_ROOT}/libcrypto.a")

target_compile_features(curl_http PRIVATE cxx_std_17)
target_include_directories(curl_http PRIVATE
  "${CURL_SOURCE_ROOT}/include"
  "${CURL_BUILD_ROOT}/lib"
  "${OPENSSL_BUILD_ROOT}/include")
target_link_libraries(curl_http PRIVATE
  curl_static
  ssl_static
  crypto_static
  ace_napi.z
  dl)
set_target_properties(curl_http PROPERTIES
  OUTPUT_NAME "curl_http")
