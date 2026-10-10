cmake_minimum_required(VERSION 3.20)
project(poolrad C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Engine portability (SPEC 7.2): no float, strict warnings. The lint
# (tools/lint/portability.py) enforces the type and libc rules.
add_compile_options(-Wall -Wextra -Werror -fno-common)

find_package(SDL3 REQUIRED)

include_directories(src/include src/platform)

# --- engine (portable; also compiled into the hybrid library) ---
set(ENGINE_SRCS
  src/rtl/rtl_memory.c
  src/rtl/rtl_random.c
  src/game/res00_system.c
)

# --- native host binary (SPEC 11) ---
add_executable(poolrad
  src/platform/host/main.c
  src/platform/host/host_sdl.c
  ${ENGINE_SRCS}
)
target_link_libraries(poolrad PRIVATE SDL3::SDL3)

# --- hybrid shared library for the oracle (SPEC 8.4) ---
add_library(poolrad_hybrid SHARED
  src/hybrid/hybrid.c
  ${ENGINE_SRCS}
)
set_target_properties(poolrad_hybrid PROPERTIES OUTPUT_NAME poolrad_hybrid)
