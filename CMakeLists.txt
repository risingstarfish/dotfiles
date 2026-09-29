cmake_minimum_required(VERSION 3.28...4.4)

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

if(PROJECT_IS_TOP_LEVEL)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
endif()

include(GNUInstallDirs)

set(DOTFILES_CMAKE_DIR "${CMAKE_CURRENT_LIST_DIR}/cmake")
list(APPEND CMAKE_MODULE_PATH "${DOTFILES_CMAKE_DIR}")

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_SCAN_FOR_MODULES OFF) # FIXME:

message(STATUS "CXX: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")

set(CMAKE_EXPORT_COMPILE_COMMANDS OFF)
# Export compile commands if we can (useful in LSPs like clangd)
# https://cmake.org/cmake/help/v3.31/variable/CMAKE_EXPORT_COMPILE_COMMANDS.html
if(CMAKE_GENERATOR STREQUAL "Unix Makefiles" OR CMAKE_GENERATOR MATCHES "^Ninja")
    set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
endif()

option(
    DOTFILES_BUILD_STATIC_LIB
    "Build dotfiles_static library along with dotfiles (only makes sense if BUILD_SHARED_LIBS=ON)"
    OFF
)
if(DOTFILES_BUILD_STATIC_LIB AND NOT BUILD_SHARED_LIBS)
    message(WARNING "DOTFILES_BUILD_STATIC_LIB only makes sense if BUILD_SHARED_LIBS is set to ON")
    message(WARNING "You might be building and installing a two identical static libraries.")
endif()

if(${PROJECT_IS_TOP_LEVEL})
    option(DOTFILES_DEVELOPER_MODE "Enable targets for developing dotfiles" OFF)
    option(BUILD_SHARED_LIBS "Build dotfiles as a shared library" OFF)
endif()

option(DOTFILES_OPT_BUILD_TESTS "Build and perform dotfiles tests" ${PROJECT_IS_TOP_LEVEL})
option(DOTFILES_OPT_INSTALL "Generate and install dotfiles target" ${PROJECT_IS_TOP_LEVEL})
option(DOTFILES_CXX_MODULES_ENABLED "Build the dotfiles C++26 module target" OFF)
option(DOTFILES_MODULE_IMPORT_STD "Build the module target with import std" OFF)
option(DOTFILES_OPT_INSTALL_PACKAGE_XML "Include package.xml when installing"
       ${DOTFILES_OPT_INSTALL}
)

if(DOTFILES_MODULE_IMPORT_STD AND NOT DOTFILES_CXX_MODULES_ENABLED)
    message(FATAL_ERROR "DOTFILES_MODULE_IMPORT_STD requires DOTFILES_CXX_MODULES_ENABLED=ON")
endif()
option(DOTFILES_OPT_TEST_INSTALLED_VERSION "Test against an installed dotfiles CMake package" OFF)
option(DOTFILES_OPT_TEST_INSTALLED_VERSION_PKGCONFIG
       "Test against an installed dotfiles pkg-config package" OFF
)

if(DOTFILES_OPT_TEST_INSTALLED_VERSION AND DOTFILES_OPT_TEST_INSTALLED_VERSION_PKGCONFIG)
    message(
        FATAL_ERROR
            "DOTFILES_OPT_TEST_INSTALLED_VERSION and DOTFILES_OPT_TEST_INSTALLED_VERSION_PKGCONFIG are mutually exclusive"
    )
endif()
if(DOTFILES_OPT_TEST_INSTALLED_VERSION_PKGCONFIG AND DOTFILES_CXX_MODULES_ENABLED)
    message(
        FATAL_ERROR
            "DOTFILES_OPT_TEST_INSTALLED_VERSION_PKGCONFIG does not support DOTFILES_CXX_MODULES_ENABLED"
    )
endif()

add_executable(${PROJECT_NAME} src/dotfiles.cpp)
target_include_directories(${PROJECT_NAME} PRIVATE include)
target_compile_options(${PROJECT_NAME} PRIVATE -freflection)

if(DOTFILES_OPT_TEST_INSTALLED_VERSION
   OR DOTFILES_OPT_TEST_INSTALLED_VERSION_PKGCONFIG
   OR DOTFILES_OPT_BUILD_TESTS
)
    include("${DOTFILES_CMAKE_DIR}/CPM.cmake")
endif()

if(DOTFILES_OPT_TEST_INSTALLED_VERSION OR DOTFILES_OPT_TEST_INSTALLED_VERSION_PKGCONFIG)
    if(DOTFILES_OPT_TEST_INSTALLED_VERSION OR DOTFILES_OPT_TEST_INSTALLED_VERSION_PKGCONFIG)
        enable_testing()
        add_subdirectory(tests)
    endif()
    return()
endif()

include(ccache)
enable_ccache(BASE_DIR ${PROJECT_SOURCE_DIR})
