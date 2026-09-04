# project wide flags

# SANITIZE_UNDEFINED
# SANITIZE_ADDRESS
# USE_LIBCPP
# VISUAL_STUDIO_BUILD_WITH_DEBUG_INFO_FOR_PROFILING

add_library(internal-flags INTERFACE)
if(NOT DEFINED CMAKE_POSITION_INDEPENDENT_CODE)
    # We default to ON for all targets, so that we can use the library in shared libraries.
    set_target_properties(internal-flags PROPERTIES INTERFACE_POSITION_INDEPENDENT_CODE ON)
endif()

option(SANITIZE_UNDEFINED "Sanitize undefined behavior" OFF)
if(SANITIZE_UNDEFINED)
    target_compile_options(internal-flags INTERFACE -fsanitize=undefined -fno-sanitize-recover=all)
    target_link_options(internal-flags INTERFACE -fsanitize=undefined -fno-sanitize-recover=all)
endif()

option(SANITIZE_ADDRESS "Sanitize addresses" OFF)
if(SANITIZE_ADDRESS)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
        message(STATUS "The address sanitizer under Apple's clang appears to be \
incompatible with the undefined-behavior sanitizer."
        )
        message(STATUS "You may set SANITIZE_UNDEFINED to sanitize \
undefined behavior."
        )
        target_compile_options(
            internal-flags INTERFACE -fsanitize=address -fno-omit-frame-pointer
                                     -fno-sanitize-recover=all
        )
        target_compile_definitions(internal-flags INTERFACE ASAN_OPTIONS=detect_leaks=1)
        target_link_libraries(
            internal-flags INTERFACE -fsanitize=address -fno-omit-frame-pointer
                                     -fno-sanitize-recover=all
        )
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        target_compile_options(internal-flags INTERFACE -fsanitize=address)
        target_link_libraries(internal-flags INTERFACE -fsanitize=address)
    else()
        message(STATUS "Setting both the address sanitizer and the undefined sanitizer.")
        target_compile_options(
            internal-flags INTERFACE -fsanitize=address -fno-omit-frame-pointer
                                     -fsanitize=undefined -fno-sanitize-recover=all
        )
        target_link_libraries(
            internal-flags INTERFACE -fsanitize=address -fno-omit-frame-pointer
                                     -fsanitize=undefined -fno-sanitize-recover=all
        )
    endif()

    # Ubuntu bug for GCC 5.0+ (safe for all versions)
    if(CMAKE_COMPILER_IS_GNUCC)
        target_link_libraries(internal-flags INTERFACE -fuse-ld=gold)
    endif()
endif(SANITIZE_ADDRESS)

if(SANITIZE_MEMORY)
    message(STATUS "Setting the memory sanitizer.")
    target_compile_options(internal-flags INTERFACE -fsanitize=memory -fno-sanitize-recover=all)
    target_link_libraries(internal-flags INTERFACE -fsanitize=memory -fno-sanitize-recover=all)
    # Ubuntu bug for GCC 5.0+ (safe for all versions)
    if(CMAKE_COMPILER_IS_GNUCC)
        target_link_libraries(internal-flags INTERFACE -fuse-ld=gold)
    endif()
endif()

if(SANITIZE_THREADS)
    message(STATUS "Setting both the thread sanitizer \
and the undefined-behavior sanitizer."
    )
    target_compile_options(
        internal-flags INTERFACE -fsanitize=thread -fsanitize=undefined -fno-sanitize-recover=all
    )
    target_link_libraries(
        internal-flags INTERFACE -fsanitize=thread -fsanitize=undefined -fno-sanitize-recover=all
    )

    # Ubuntu bug for GCC 5.0+ (safe for all versions)
    if(CMAKE_COMPILER_IS_GNUCC)
        target_link_libraries(internal-flags INTERFACE -fuse-ld=gold)
    endif()
endif()

get_cmake_property(is_multi_config GENERATOR_IS_MULTI_CONFIG)
if(NOT is_multi_config AND NOT CMAKE_BUILD_TYPE)
    # Deliberately not including SANITIZE_THREADS since thread behavior
    # depends on the build type.
    if(SANITIZE_ADDRESS OR SANITIZE_UNDEFINED)
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

set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
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

option(
    VISUAL_STUDIO_BUILD_WITH_DEBUG_INFO_FOR_PROFILING
    "\
Under Visual Studio, add Zi to the compile flag and DEBUG to the link file to \
add debugging information to the release build for easier profiling inside \
tools like VTune"
    OFF
)
if(MSVC)
    target_compile_options(
        internal-flags
        INTERFACE /EHs- # NOTE: disable exceptions
                  /WX # warnings as errors
                  /W4 # warning level 4
                  /MP # build with multiple processors
                  /Zc:__cplusplus
                  # Granular Type / Conversion Warnings
                  /w14242 # -Wconversion
                  /w14287 # unsigned/negative constant mismatch
                  /w14296 # expression is always true/false
                  /w14365 # -Wsign-conversion
                  /w15062 # -Wimplicit-fallthrough
                  # Hardening / Security Flags
                  /GS # Buffer security check
                  /sdl # upgrades warnings to errors, zeroes some uninitialized memory
                  /guard:cf # Control Flow Guard
                  /permissive-
                  /Zc:preprocessor
                  /bigobj
                  /utf-8
    )
    if(VISUAL_STUDIO_BUILD_WITH_DEBUG_INFO_FOR_PROFILING)
        target_link_options(internal-flags INTERFACE /DEBUG)
        target_compile_options(internal-flags INTERFACE /Zi)
    endif()

    target_link_options(internal-flags INTERFACE /NXCOMPAT /DYNAMICBASE /CETCOMPAT /OPT:REF)

else()

    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
        set(ARCH_HARDENING_FLAGS -fcf-protection=full)
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
        set(ARCH_HARDENING_FLAGS -mbranch-protection=standard)
    else()
        set(ARCH_HARDENING_FLAGS)
    endif()

    set(UNIX_FLAGS
        -Werror
        -Wall
        -Wextra
        -Wsign-compare
        -Wshadow
        -Wformat
        -Wformat=2
        -Wconversion
        -Wsign-conversion
        -Wimplicit-fallthrough
        -Winit-self
        -Wctad-maybe-unsupported
        -Werror=format-security
        -fno-exceptions
        -fstack-protector-strong
        -fstack-clash-protection
        -ftrivial-auto-var-init=zero
        -fno-strict-overflow
        -fstrict-flex-arrays=3
    )

    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        set(COMPILER_FLAGS -fzero-init-padding-bits=all -fzero-init-padding-bits=unions
                           -Wbidi-chars=any -Wtrampolines
        )
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        set(COMPILER_FLAGS)
    endif()

    target_compile_options(
        internal-flags INTERFACE ${UNIX_FLAGS} ${COMPILER_FLAGS} ${ARCH_HARDENING_FLAGS}
    )

    if(UNIX AND NOT APPLE)
        target_link_options(
            internal-flags
            INTERFACE
            -Wl,-z,nodlopen
            -Wl,-z,noexecstack
            -Wl,-z,relro
            -Wl,-z,now
            -Wl,--as-needed
            -Wl,--no-copy-dt-needed-entries
        )
    endif()

    target_compile_definitions(internal-flags INTERFACE _GLIBCXX_ASSERTIONS)
endif()

if(NOT MSVC)
    option(USE_LIBCPP "Use the libc++ library" OFF)
    if(USE_LIBCPP)
        target_link_libraries(internal-flags INTERFACE -stdlib=libc++ -lc++abi)
        # instead of the above line, we could have used
        # set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -stdlib=libc++
        # -lc++abi")
        # The next line is needed empirically.
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
        # we update CMAKE_SHARED_LINKER_FLAGS, this gets updated later as well
        set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -lc++abi")
    endif()
endif()

# https://www.reddit.com/r/cpp_questions/comments/1bsh7nd/undefined_reference_to_std_open_terminal/
if(MINGW AND CMAKE_CXX_COMPILER_ID STREQUAL GNU)
    target_link_libraries(internal-flags INTERFACE stdc++exp)
endif()

# ---- Build Type Flags ----
# FIXME: msvc
if(NOT SANITIZE_ADDRESS)
    set(FORTIFY_FLAGS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3)
else()
    set(FORTIFY_FLAGS)
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(
        internal-flags
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
        internal-flags INTERFACE -Wl,--gc-sections -ffunction-sections -fdata-sections
    )
    target_compile_options(
        internal-flags
        INTERFACE -O2
                  -flto
                  -DNDEBUG
                  -fsanitize-trap=undefined
                  -fno-delete-null-pointer-checks
                  -fno-strict-aliasing
                  ${FORTIFY_FLAGS}
    )
elseif(CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
    target_compile_options(internal-flags INTERFACE -Os ${FORTIFY_FLAGS})
endif()
