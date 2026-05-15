cmake_minimum_required(VERSION 3.14)
project(qr_steam_example LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(BINARY_NAME "qr_steam_example")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/run" CACHE PATH "..." FORCE)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/run" CACHE PATH "..." FORCE)
endif()

set(PROJECT_BUILD_DIR "${PROJECT_NAME}/")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner")

include(flutter/generated_plugins.cmake)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
add_subdirectory(flutter)

# === Installation ===

# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of having a separate bundle step, as it
# mirrors how the original installer packages the files.
set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
endif()

install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/cpp_client_wrapper/"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/flutter_assets/")
