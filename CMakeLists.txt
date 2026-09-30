cmake_minimum_required(VERSION 3.28...4.4.0)

if(DOTFILES_MODULE_IMPORT_STD
   AND DOTFILES_CXX_MODULES_ENABLED
   AND NOT CMAKE_CXX_STANDARD
)
    message(FATAL_ERROR "DOTFILES_MODULE_IMPORT_STD requires an explicit CMAKE_CXX_STANDARD")
endif()

set(DOTFILES_VERSION_MAJOR 0)
set(DOTFILES_VERSION_MINOR 1)
set(DOTFILES_VERSION_PATCH 0)
set(DOTFILES_VERSION ${DOTFILES_VERSION_MAJOR}.${DOTFILES_VERSION_MINOR}.${DOTFILES_VERSION_PATCH})

project(
    dotfiles
    VERSION ${DOTFILES_VERSION}
    HOMEPAGE_URL "https://github.com/risingstarfish/dotfiles"
    DESCRIPTION "Dotfiles installer for Mac, Linux, Windows, and WSL."
    LANGUAGES CXX
)
set(CPACK_PACKAGE_VENDOR "Pierce Katai")

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_SCAN_FOR_MODULES OFF) # DIXME: cache bool
set(CMAKE_THREAD_PREFER_PTHREAD ON)
set(THREADS_PREFER_PTHREAD_FLAG ON)
# TODO: cpack

if(${PROJECT_IS_TOP_LEVEL})
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
endif()

include(GNUInstallDirs)

set(DOTFILES_CMAKE_DIR "${CMAKE_CURRENT_LIST_DIR}/cmake")
list(APPEND CMAKE_MODULE_PATH "${DOTFILES_CMAKE_DIR}")

message(STATUS "CXX: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")

# Export compile commands if we can (useful in LSPs like clangd)
# https://cmake.org/cmake/help/v3.31/variable/CMAKE_EXPORT_COMPILE_COMMANDS.html
if(CMAKE_GENERATOR STREQUAL "Unix Makefiles" OR CMAKE_GENERATOR MATCHES "^Ninja")
    set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
endif()

#
# option list
#

# debug
option(DOTFILES_ALL_WARNINGS "dotfiles: enable all compiler warnings" ON)
#option(DOTFILES_ALL_WARNINGS_3RD_PARTY "dotfiles: enable all compiler warnings in 3rd party libs" OFF)

# build
option(
    DOTFILES_BUILD_STATIC_LIB
    "Build dotfiles_static library along with dotfiles (only makes sense if BUILD_SHARED_LIBS=ON)"
    OFF
)
option(BUILD_SHARED_LIBS "dotfiles: build dotfiles as a shared library" ${PROJECT_IS_TOP_LEVEL})
if(DOTFILES_BUILD_STATIC_LIB AND NOT BUILD_SHARED_LIBS)
    message(WARNING "DOTFILES_BUILD_STATIC_LIB only makes sense if BUILD_SHARED_LIBS is set to ON")
    message(WARNING "You might be building and installing two identical static libraries.")
endif()
option(DOTFILES_OPT_INSTALL "dotfiles: generate and install dotfiles target"
       ${PROJECT_IS_TOP_LEVEL}
)
option(DOTFILES_OPT_INSTALL_PACKAGE_XML "dotfiles: include package.xml when installing" OFF)
option(DOTFILES_FATAL_WARNINGS "dotfiles: enable -Werror flag" OFF)
option(DOTFILES_USE_LIBCPP "Use the libc++ library" OFF)
option(DOTFILES_ENABLE_HARDENING "Enable standard library hardening" ON)
option(DOTFILES_ENABLE_CONTRACTS "Enable contract assertions" OFF)

# sanitizers
option(DOTFILES_SANITIZE_ADDRESS "dotfiles: enable address sanitizer" OFF)
option(DOTFILES_SANITIZE_UNDEFINED "dotfiles: enable undefined sanitizer" OFF)
option(DOTFILES_SANITIZE_THREAD "dotfiles: enable thread sanitizer" OFF)

# extra artifacts
option(DOTFILES_OPT_BUILD_TESTS "dotfiles: build tests" ${PROJECT_IS_TOP_LEVEL})
option(DOTFILES_OPT_BUILD_EXAMPLES "dotfiles: build examples" ${PROJECT_IS_TOP_LEVEL})

# modules
option(DOTFILES_CXX_MODULES_ENABLED "dotfiles: build the dotfiles C++26 module target" OFF)
option(DOTFILES_MODULE_IMPORT_STD "dotfiles: build the module target with import std" OFF)
if(DOTFILES_MODULE_IMPORT_STD AND NOT DOTFILES_CXX_MODULES_ENABLED)
    message(FATAL_ERROR "DOTFILES_MODULE_IMPORT_STD requires DOTFILES_CXX_MODULES_ENABLED=ON")
endif()

include("${DOTFILES_CMAKE_DIR}/CPM.cmake")

add_library(internal-flags INTERFACE)

cpmaddpackage(
    NAME
    reflex
    VERSION
    0.1.3
    SYSTEM
    YES
    GIT_REPOSITORY
    https://github.com/Garcia6l20/reflex.git
    GIT_TAG
    075e37633a2008b9286744588e408e750e9196e1
    OPTIONS
    "REFLEX_CLI_ENABLED ON"
    "REFLEX_POLY_ENABLED OFF"
    "REFLEX_SERDE_ENABLED OFF"
    "REFLEX_JINJA_ENABLED OFF"
    "REFLEX_PY_ENABLED OFF"
)

target_link_libraries(internal-flags INTERFACE reflex.common_flags)

if(DOTFILES_ENABLE_CONTRACTS)
    include(CheckCXXSourceCompiles)
    set(CMAKE_REQUIRED_FLAGS "-fcontracts -std=c++26")
    check_cxx_source_compiles(
        "
    #include <contracts>
    void fun(int x) pre(x >= 0) { return 0; }
    int main() { return fun(1); }
"
        DOTFILES_SUPPORT_CONTRACTS
    )
    unset(CMAKE_REQUIRED_FLAGS)

    if(NOT DOTFILES_SUPPORT_CONTRACTS)
        message(WARNING "Contracts detection test returned false but has been explicitly enabled")
    else()
        message(STATUS "Enabling contract assertions")
        target_compile_options(internal-flags INTERFACE -fcontracts)
    endif()
endif()

set(DOTFILES_PRECOMPILE_HEADERS
    # NOTE: keep alphabetical
    <array>
    <concepts>
    <cstddef>
    <cstdint>
    <cstdlib>
    <filesystem>
    <format>
    <iterator>
    <meta>
    <print>
    <ranges>
    <string>
    <string_view>
    <type_traits>
    <utility>
)
target_precompile_headers(internal-flags INTERFACE ${DOTFILES_PRECOMPILE_HEADERS})

include(reflection)
include(compiler-flags)
include(sanitizers)

target_include_directories(internal-flags INTERFACE include)

add_subdirectory(src)

if(DOTFILES_OPT_BUILD_EXAMPLES)
    add_subdirectory(examples)
endif()

if(DOTFILES_OPT_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

include(ccache)
enable_ccache(BASE_DIR ${PROJECT_SOURCE_DIR})
