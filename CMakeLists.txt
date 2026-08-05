cmake_minimum_required(VERSION 3.30.0...4.3.1 FATAL_ERROR)

set(DOTFILES_VERSION_MAJOR 1)
set(DOTFILES_VERSION_MINOR 0)
set(DOTFILES_VERSION_PATCH 0)
set(DOTFILES_VERSION ${DOTFILES_VERSION_MAJOR}.${DOTFILES_VERSION_MINOR}.${DOTFILES_VERSION_PATCH})

project(
    dotfiles
    VERSION ${DOTFILES_VERSION}
    DESCRIPTION "TODO:"
    HOMEPAGE_URL "https://github.com/risingstarfish/dotfiles"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

string(COMPARE EQUAL "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}" is_top_level_project)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

# ---- Options and Variables ----

# Export compile commands if we can (useful in LSPs like clangd)
# https://cmake.org/cmake/help/v3.31/variable/CMAKE_EXPORT_COMPILE_COMMANDS.html
if(CMAKE_GENERATOR STREQUAL "Unix Makefiles" OR CMAKE_GENERATOR MATCHES "^Ninja")
    set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
endif()

set(DOTFILES_LIB_VERSION
    "1.0.0"
    CACHE STRING "dotfiles ABI version"
)
set(DOTFILES_LIB_SOVERSION
    "1"
    CACHE STRING "dotfiles ABI soversion"
)

set(DOTFILES_ACTIVE_TARGETS dotfiles)

option(
    DOTFILES_BUILD_STATIC_LIB
    "Build dotfiles_static library along with dotfiles (only makes sense if BUILD_SHARED_LIBS=ON)"
    OFF
)
if(DOTFILES_BUILD_STATIC_LIB AND NOT BUILD_SHARED_LIBS)
    message(WARNING "DOTFILES_BUILD_STATIC_LIB only makes sense if BUILD_SHARED_LIBS is set to ON")
    message(WARNING "You might be building and installing a two identical static libraries.")
endif()

if(is_top_level_project)
    option(DOTFILES_INSTALL "Enable target install" ON)
    option(DOTFILES_DEVELOPER_MODE "Enable targets for developing dotfiles" OFF)
    option(BUILD_SHARED_LIBS "Build dotfiles as a shared library" OFF)
else()
    option(DOTFILES_INSTALL "Enable target install" ${BUILD_SHARED_LIBS})
endif(is_top_level_project)

include(cmake/developer-options.cmake)

# ---- CPM ----
include(cmake/CPM.cmake)

cpmaddpackage(
    NAME
    simdjson
    VERSION
    4.6.6
    GIT_REPOSITORY
    https://github.com/simdjson/simdjson.git
    GIT_TAG
    9392a55f76ad9838efd1cdc1529f2607b3d613fb
    OPTIONS 
    "SIMDJSON_STATIC_REFLECTION=1"
    "SIMDJSON_DISABLE_DEPRECATED_API=1"
)

# ---- dotfiles library ----

set(DOTFILES_SOURCES src/dotfiles.cpp)

add_library(dotfiles ${DOTFILES_SOURCES})
add_library(dotfiles::dotfiles ALIAS dotfiles)

set(DOTFILES_LIBRARIES dotfiles)
#FIXME:
target_link_libraries(dotfiles PRIVATE simdjson::simdjson)

# Enable precompiled headers for faster builds
set(DOTFILES_PRECOMPILE_HEADERS
    # FIXME: proper headers
    # <concepts>
    # <cstdint>
    # <expected>
    # <limits>
    # <type_traits>
    # <utility>
    # =====
    # <atomic>
    # <cassert>
    # <cctype>
    # <cerrno>
    # <cstddef>
    # <cstdint>
    # <cstdlib>
    # <cstring>
    # <memory>
    # <string>
    # <utility>
    # <vector>
)

target_precompile_headers(dotfiles PRIVATE ${DOTFILES_PRECOMPILE_HEADERS})

if(DOTFILES_BUILD_STATIC_LIB)
    add_library(dotfiles_static STATIC ${DOTFILES_SOURCES})
    add_library(dotfiles::dotfiles_static ALIAS dotfiles_static)
    list(APPEND DOTFILES_LIBRARIES dotfiles_static)

    # Reuse precompiled headers for static library
    target_precompile_headers(dotfiles_static REUSE_FROM dotfiles)
endif(DOTFILES_BUILD_STATIC_LIB)

set_target_properties(
    dotfiles PROPERTIES VERSION "${DOTFILES_LIB_VERSION}" SOVERSION "${DOTFILES_LIB_SOVERSION}"
)

target_include_directories(
    dotfiles
    PUBLIC "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>"
    PRIVATE "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/src>"
    PRIVATE "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/configs>"
)

if(DOTFILES_BUILD_STATIC_LIB)
    target_include_directories(
        dotfiles_static
        PUBLIC "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>"
        PRIVATE "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/src>"
        PRIVATE "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/configs>"
    )
endif(DOTFILES_BUILD_STATIC_LIB)

include(cmake/compiler-flags.cmake)
apply_standard_flags(dotfiles)
if(DOTFILES_BUILD_STATIC_LIB)
    apply_standard_flags(dotfiles_static)
endif()

# ---- Install ----

if(DOTFILES_INSTALL)
    include(CMakePackageConfigHelpers)
    include(GNUInstallDirs)

    install(
        TARGETS dotfiles simdjson
        EXPORT dotfilesTargets
        RUNTIME COMPONENT dotfiles_Runtime
        LIBRARY COMPONENT dotfiles_Runtime NAMELINK_COMPONENT dotfiles_Development
        ARCHIVE COMPONENT dotfiles_Development
        INCLUDES
        DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
    )
    configure_file(cmake/dotfiles-config.cmake.in dotfiles-config.cmake @ONLY)

    write_basic_package_version_file(dotfiles-config-version.cmake COMPATIBILITY SameMinorVersion)

    set(DOTFILES_INSTALL_CMAKEDIR
        "${CMAKE_INSTALL_LIBDIR}/cmake/dotfiles"
        CACHE STRING "CMake package config location relative to the install prefix"
    )
    mark_as_advanced(DOTFILES_INSTALL_CMAKEDIR)

    install(
        FILES "${PROJECT_BINARY_DIR}/dotfiles-config.cmake"
              "${PROJECT_BINARY_DIR}/dotfiles-config-version.cmake"
        DESTINATION "${DOTFILES_INSTALL_CMAKEDIR}"
        COMPONENT dotfiles_Development
    )

    install(
        EXPORT dotfilesTargets
        NAMESPACE dotfiles::
        DESTINATION "${DOTFILES_INSTALL_CMAKEDIR}"
        COMPONENT dotfiles_Development
    )

    if(DOTFILES_BUILD_STATIC_LIB)
        install(
            TARGETS dotfiles_static
            EXPORT dotfiles_staticTargets
            ARCHIVE COMPONENT dotfiles_Development
            INCLUDES
            DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
        )
        install(
            EXPORT dotfiles_staticTargets
            NAMESPACE dotfiles::
            DESTINATION "${DOTFILES_INSTALL_CMAKEDIR}"
            COMPONENT dotfiles_Development
        )
    endif(DOTFILES_BUILD_STATIC_LIB)

    # pkg-config
    include(cmake/JoinPaths.cmake)
    join_paths(PKGCONFIG_INCLUDEDIR "\${prefix}" "${CMAKE_INSTALL_INCLUDEDIR}")
    join_paths(PKGCONFIG_LIBDIR "\${prefix}" "${CMAKE_INSTALL_LIBDIR}")

    configure_file("dotfiles.pc.in" "dotfiles.pc" @ONLY)
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/dotfiles.pc"
            DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig"
    )
endif(DOTFILES_INSTALL)

# ---- CPack ----

if(is_top_level_project)
    set(CPACK_PACKAGE_VENDOR "Pierce Katai")
    set(CPACK_PACKAGE_CONTACT "169690632+risingstarfish@users.noreply.github.com")
    set(CPACK_RESOURCE_FILE_LICENSE "${PROJECT_SOURCE_DIR}/LICENSE")
    set(CPACK_RESOURCE_FILE_README "${PROJECT_SOURCE_DIR}/README.md")
    set(CPACK_RPM_PACKAGE_LICENSE "${PROJECT_SOURCE_DIR}/LICENSE")
    set(CPACK_SOURCE_GENERATOR "TGZ;ZIP")

    include(CPack)
endif(is_top_level_project)

# ---- Developer mode extras ----

if(is_top_level_project AND NOT DOTFILES_DEVELOPER_MODE)
    message(
        STATUS
            "Building only the library. Advanced users and contributors may want to turn DOTFILES_DEVELOPER_MODE to ON, e.g., via -D DOTFILES_DEVELOPER_MODE=ON."
    )
elseif(DOTFILES_DEVELOPER_MODE AND NOT is_top_level_project)
    message(AUTHOR_WARNING "Developer mode in dotfiles is intended for the developers of dotfiles")
endif()

if(NOT DOTFILES_DEVELOPER_MODE)
    return()
endif()

apply_standard_flags(dotfiles-internal-flags)

set(DOTFILES_USER_CMAKECACHE "${CMAKE_BINARY_DIR}/.dotfiles-user-CMakeCache.txt")
add_custom_target(
    dotfiles-user-cmakecache
    COMMAND
        "${CMAKE_COMMAND}" -D "BINARY_DIR=${CMAKE_BINARY_DIR}" -D
        "USER_CMAKECACHE=${DOTFILES_USER_CMAKECACHE}" -P
        "${PROJECT_SOURCE_DIR}/cmake/dotfiles-user-cmakecache.cmake"
    VERBATIM
)

enable_testing()
# So we can build just tests with "make all_tests"
add_custom_target(all_tests)

# ---- Compile tools / tests ----

add_subdirectory(tests)

# ---- Source files should be just ASCII ----

find_program(FIND_CMD find)
find_program(FILE_CMD file)
find_program(GREP_CMD grep)
if(FIND_CMD
   AND FILE_CMD
   AND GREP_CMD
)
    add_test(
        NAME just_ascii
        COMMAND
            sh -c "\
non_ascii=$(${FIND_CMD} include tests \
  -name '*.hpp' -o -name '*.cpp' \
  -type f -exec ${FILE_CMD} '{}' \; | ${GREP_CMD} -v ASCII); \
if [ -n \"$non_ascii\" ]; then \
  echo 'The following files contain non-ASCII characters:'; \
  echo \"$non_ascii\"; \
  exit 1; \
fi"
        WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    )
else()
    message(
        WARNING
            "just_ascii test disabled because required tools were not found: find='${FIND_CMD}', file='${FILE_CMD}', grep='${GREP_CMD}'"
    )
endif()
