cmake_minimum_required(VERSION 3.16)
project(poolrad C)

# The C translation of Pool of Radiance (SPEC 7.4, Phase 7). Builds on macOS, Linux and Windows.
#
#   cmake -S . -B build/cmake && cmake --build build/cmake
#
# targets: poolrad         the game (needs SDL3: window, keyboard, audio)
#          poolrad_replay  headless; replays recordings of the original and checks the screen (tests)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)

option(POOLRAD_TRACE "log every routine call (replay --trace-calls)" OFF)
if(POOLRAD_TRACE)
  add_compile_definitions(POOL_TRACE_CALLS)
endif()
option(POOLRAD_COVERAGE "instrument the translated game for clang source coverage (tools/c/coverage.py)" OFF)
if(POOLRAD_COVERAGE)
  add_compile_options(-fprofile-instr-generate -fcoverage-mapping)
  add_link_options(-fprofile-instr-generate)
endif()
option(POOLRAD_FETCH_SDL3 "download and build SDL3 when it is not installed" OFF)

if(MSVC)
  add_compile_options(/W3 /wd4244 /wd4267 /wd4996 /wd4101 /wd4146 /wd4018 /wd4305)
else()
  add_compile_options(-Wall -Wextra -Wno-unused-variable -Wno-unused-label -Wno-unused-parameter
                      -Wno-unused-but-set-variable -Wno-parentheses -Wno-pragma-pack -Wno-sign-compare
                      -Wno-comment -fno-strict-aliasing -fwrapv)
endif()

set(ENGINE_RTL
  c/rtl/core.c c/rtl/heap.c c/rtl/file.c c/rtl/crt.c c/rtl/ega.c c/rtl/sha256.c c/rtl/soundtrace.c c/rtl/vm.c)
# The translated game: c/game (the PC profile), or another directory written by `pas2c.py --profile coco --out DIR`
# (CoCo port, step 8.2: ports/coco3 builds and tests the CoCo profile on the host this way).
set(POOLRAD_GAME_DIR "c/game" CACHE PATH "directory of the translated game (game.h and the units)")
file(GLOB ENGINE_GAME CONFIGURE_DEPENDS ${POOLRAD_GAME_DIR}/*.c c/driver/*.c)

add_library(poolrad_engine STATIC ${ENGINE_RTL} ${ENGINE_GAME})
target_include_directories(poolrad_engine PUBLIC c/include ${POOLRAD_GAME_DIR})

add_executable(poolrad_replay c/platform/replay.c)
target_link_libraries(poolrad_replay PRIVATE poolrad_engine)
if(UNIX)
  target_link_libraries(poolrad_replay PRIVATE m)
endif()

# a headless host that plays a key script fast and writes screens: finds things before a session is recorded (c/platform/explore.c)
add_executable(poolrad_explore c/platform/explore.c)
target_link_libraries(poolrad_explore PRIVATE poolrad_engine)
if(UNIX)
  target_link_libraries(poolrad_explore PRIVATE m)
endif()

find_package(SDL3 QUIET)
if(NOT SDL3_FOUND AND POOLRAD_FETCH_SDL3)
  include(FetchContent)
  set(SDL_SHARED OFF CACHE BOOL "" FORCE)
  set(SDL_STATIC ON CACHE BOOL "" FORCE)
  set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(SDL3 GIT_REPOSITORY https://github.com/libsdl-org/SDL.git GIT_TAG release-3.2.20 GIT_SHALLOW TRUE)
  FetchContent_MakeAvailable(SDL3)
  set(SDL3_FOUND TRUE)
endif()
if(SDL3_FOUND AND EXISTS ${CMAKE_SOURCE_DIR}/c/platform/sdl_host.c)
  add_executable(poolrad c/platform/sdl_host.c c/platform/psg.c)
  target_link_libraries(poolrad PRIVATE poolrad_engine SDL3::SDL3)
  if(UNIX)
    target_link_libraries(poolrad PRIVATE m)
  endif()
else()
  message(STATUS "SDL3 not found: only poolrad_replay is built (install SDL3 to build the game)")
endif()

# ---- every tune of the sound driver to WAV files through the host's synthesiser ----
add_executable(tune_wav c/tests/tune_wav.c c/platform/psg.c)
target_link_libraries(tune_wav PRIVATE poolrad_engine)
if(UNIX)
  target_link_libraries(tune_wav PRIVATE m)
endif()

# ---- sound driver probe (tools/c/sound_check.py runs it against the oracle's golden) ----
add_executable(sound_probe c/tests/sound_probe.c c/platform/null.c)
target_link_libraries(sound_probe PRIVATE poolrad_engine)
if(UNIX)
  target_link_libraries(sound_probe PRIVATE m)
endif()
