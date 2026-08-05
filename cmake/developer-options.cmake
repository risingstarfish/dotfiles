# ---- Flags used by exes and by the dotfiles library (project-wide flags) ----

add_library(dotfiles-internal-flags INTERFACE)
if(NOT DEFINED CMAKE_POSITION_INDEPENDENT_CODE)
    # We default to ON for all targets, so that we can use the library in shared libraries.
    set_target_properties(dotfiles-internal-flags PROPERTIES INTERFACE_POSITION_INDEPENDENT_CODE ON)
endif(NOT DEFINED CMAKE_POSITION_INDEPENDENT_CODE)

option(DOTFILES_SANITIZE_UNDEFINED "Sanitize undefined behavior" OFF)
if(DOTFILES_SANITIZE_UNDEFINED)
    add_compile_options(-fsanitize=undefined -fno-sanitize-recover=all)
    add_link_options(-fsanitize=undefined -fno-sanitize-recover=all)
endif()

option(DOTFILES_SANITIZE "Sanitize addresses" OFF)
if(DOTFILES_SANITIZE)
        message(STATUS "Setting both the address sanitizer and the undefined sanitizer.")
        add_compile_options(
            -fsanitize=address -fno-omit-frame-pointer -fsanitize=undefined
            -fno-sanitize-recover=all
        )
        link_libraries(
            -fsanitize=address -fno-omit-frame-pointer -fsanitize=undefined
            -fno-sanitize-recover=all -fuse-ld=gold
        )
endif()

if(DOTFILES_SANITIZE_MEMORY)
    message(STATUS "Setting the memory sanitizer.")
    add_compile_options(-fsanitize=memory -fno-sanitize-recover=all)
    link_libraries(-fsanitize=memory -fno-sanitize-recover=all -fuse-ld=gold)
endif()

if(DOTFILES_SANITIZE_THREADS)
    message(STATUS "Setting both the thread sanitizer \
and the undefined-behavior sanitizer."
    )
    add_compile_options(-fsanitize=thread -fsanitize=undefined -fno-sanitize-recover=all)
    link_libraries(-fsanitize=thread -fsanitize=undefined -fno-sanitize-recover=all -fuse-ld=gold)
endif()

get_cmake_property(is_multi_config GENERATOR_IS_MULTI_CONFIG)
if(NOT is_multi_config AND NOT CMAKE_BUILD_TYPE)
    # Deliberately not including DOTFILES_SANITIZE_THREADS since thread behavior
    # depends on the build type.
    if(DOTFILES_SANITIZE OR DOTFILES_SANITIZE_UNDEFINED)
        message(STATUS "No build type selected and you have enabled the sanitizer, \
default to Debug. Consider setting CMAKE_BUILD_TYPE."
        )
        message(STATUS "Setting debug optimization flag to -O1 to help sanitizer.")
        set(CMAKE_CXX_FLAGS_DEBUG
            "-O1"
            CACHE STRING "" FORCE
        )
        set(CMAKE_BUILD_TYPE
            Debug
            CACHE STRING "Choose the type of build." FORCE
        )
    else()
        message(STATUS "No build type selected, default to Release")
        set(CMAKE_BUILD_TYPE
            Release
            CACHE STRING "Choose the type of build." FORCE
        )
    endif()
endif()

set(CMAKE_THREAD_PREFER_PTHREAD ON)
set(THREADS_PREFER_PTHREAD_FLAG ON)

# Disable IPO for GCC on macOS because gcc-trunk generates DWARF info
# that causes clang-trunk's dsymutil to crash with "invalid abbreviation" errors.
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    message(STATUS "Disabling IPO for GCC on macOS due to dsymutil compatibility issues.")
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION FALSE)
else()
    include(CheckIPOSupported)
    check_ipo_supported(RESULT ltoresult)
    if(ltoresult)
        set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
    endif()
endif()

if(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
    set(ARCH_HARDENING_FLAGS -fcf-protection=full)
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
    set(ARCH_HARDENING_FLAGS -mbranch-protection=standard)
else()
    set(ARCH_HARDENING_FLAGS)
endif()

if(NOT DOTFILES_SANITIZE)
    set(FORTIFY_FLAGS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3)
else()
    set(FORTIFY_FLAGS)
endif()

# FIXME: gcc vs clang flags
target_compile_options(
    dotfiles-internal-flags
    INTERFACE
        -fno-exceptions
        -Werror
        -Wall
        -Wextra
        -Wsign-compare
        -Wshadow
        -Winit-self
        -Wctad-maybe-unsupported
        ${FORTIFY_FLAGS}
        # Hardening flags
        # https://github.com/ossf/wg-best-practices-os-developers/blob/main/docs/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C%2B%2B.md
        # https://gcc.gnu.org/pipermail/gcc-patches/2023-August/628748.html
        ${ARCH_HARDENING_FLAGS}
        -ftrivial-auto-var-init=zero
        -fstack-protector-strong
        -fstack-clash-protection
        -Wformat
        -Wformat=2
        -Wconversion
        -Wsign-conversion
        -Wtrampolines
        -Wimplicit-fallthrough
        -Werror=format-security
        -fstrict-flex-arrays=3
        -fno-strict-overflow
        -fzero-init-padding-bits=all
        -fzero-init-padding-bits=unions
        -Wbidi-chars=any
)

target_link_options(
    dotfiles-internal-flags
    INTERFACE
    -Wl,-z,nodlopen
    -Wl,-z,noexecstack
    -Wl,-z,relro
    -Wl,-z,now
    -Wl,--as-needed
    -Wl,--no-copy-dt-needed-entries
)

option(DOTFILES_GLIBCXX_ASSERTIONS "Set _GLIBCXX_ASSERTIONS" OFF)
if(DOTFILES_GLIBCXX_ASSERTIONS)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D_GLIBCXX_ASSERTIONS")
endif()

# https://www.reddit.com/r/cpp_questions/comments/1bsh7nd/undefined_reference_to_std_open_terminal/
if(MINGW AND CMAKE_CXX_COMPILER_ID STREQUAL GNU)
    link_libraries(stdc++exp) #FIXME: check if needed
endif()

# ---- Build Type Flags ----

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(
        dotfiles-internal-flags
        INTERFACE -O1
                  -g2
                  -fno-optimize-sibling-calls
                  -fno-common
                  -fno-inline-functions
                  -fno-delete-null-pointer-checks
                  -Wpedantic
                  -Wswitch
                  -Wcast-align
                  -Wunused
                  -Wold-style-cast
                  -Wpointer-arith
                  -Wcast-qual
    )
elseif(CMAKE_BUILD_TYPE MATCHES "Release|RelWithDebInfo")
    target_link_options(
        dotfiles-internal-flags INTERFACE -Wl,--gc-sections -ffunction-sections -fdata-sections
    )
    target_compile_options(
        dotfiles-internal-flags INTERFACE -O2 -flto -DNDEBUG -fsanitize-trap=undefined
                                          -fno-delete-null-pointer-checks -fno-strict-aliasing
    )
elseif(CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
    target_compile_options(dotfiles-internal-flags INTERFACE -Os)
endif()
