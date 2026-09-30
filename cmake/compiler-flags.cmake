cmake_minimum_required(VERSION 3.28)

#
# flags
#
# Disable IPO for GCC on macOS because gcc generates DWARF info
# that causes Apple Clang's dsymutil to crash with "invalid abbreviation" errors.
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

if(DOTFILES_USE_LIBCPP)
    target_link_libraries(internal-flags INTERFACE -stdlib=libc++ -lc++abi)
    # instead of the above line, we could have used
    # set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -stdlib=libc++
    # -lc++abi")
    # The next line is needed empirically.
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
    # we update CMAKE_SHARED_LINKER_FLAGS, this gets updated later as well
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -lc++abi")
endif()

# https://www.reddit.com/r/cpp_questions/comments/1bsh7nd/undefined_reference_to_std_open_terminal/
if(MINGW AND CMAKE_CXX_COMPILER_ID STREQUAL GNU)
    target_link_libraries(internal-flags INTERFACE stdc++exp)
endif()

set(CMAKE_VERBOSE_MAKEFILE ON)
set(STANDARD_FLAGS
    -Wall
    -Wextra
    -Wshadow
    -Wsign-compare
    -Wpedantic
    -Wswitch
    -Wconversion
    -Wimplicit-fallthrough
    -Winit-self
    -Wsign-conversion
    -Wshift-overflow
    -Wstrict-overflow=5
    -Wundef
)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    list(APPEND STANDARD_FLAGS -Wtype-limits -Wlogical-op)
endif()
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang" AND NOT MINGW)
    list(APPEND STANDARD_FLAGS -Wnewline-eof)
endif()
if(DOTFILES_FATAL_WARNINGS)
    list(APPEND STANDARD_FLAGS -Werror -Wno-comment) # suppress warnings for DOTFILES ascii art
endif()

set(HARDENING_FLAGS)
if(DOTFILES_ENABLE_HARDENING)
    set(HARDENING_FLAGS -Wformat -Wformat=2 -Werror=format-security -fstack-protector-strong
                        -fstrict-flex-arrays=3
    )
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        list(
            APPEND
            HARDENING_FLAGS
            -fzero-init-padding-bits=all
            -fzero-init-padding-bits=unions
            -Wbidi-chars=any
            -Wtrampolines
            -fstack-clash-protection
        )
    endif()
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
        list(APPEND HARDENING_FLAGS -fcf-protection=full -fzero-call-used-regs=used-gpr)
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
        list(APPEND HARDENING_FLAGS -mbranch-protection=standard -fzero-call-used-regs=used-gpr)
    endif()
endif()

if(NOT DOTFILES_SANITIZE_ADDRESS)
    set(FORTIFY_FLAGS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3)
else()
    set(FORTIFY_FLAGS)
endif()

set(BUILD_FLAGS)
set(LINK_FLAGS -pie)
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(BUILD_FLAGS
        -O1
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
    set(BUILD_FLAGS
        -O2
        -ffunction-sections
        -fdata-sections
        -fno-strict-overflow
        -fno-delete-null-pointer-checks
        -fno-strict-aliasing
        -ftrivial-auto-var-init=zero
        -flto=auto
        -DNDEBUG
        -fsanitize-trap=undefined
        ${FORTIFY_FLAGS}
    )
    list(APPEND LINK_FLAGS -Wl, --gc-sections)
elseif(CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
    set(BUILD_FLAGS -Os ${FORTIFY_FLAGS})
endif()

target_compile_options(internal-flags INTERFACE ${STANDARD_FLAGS} ${HARDENING_FLAGS} ${BUILD_FLAGS})

if(UNIX AND NOT APPLE)
    target_link_options(
        internal-flags
        INTERFACE
        ${LINK_FLAGS}
        -Wl,-z,nodlopen
        -Wl,-z,noexecstack
        -Wl,-z,relro
        -Wl,-z,now
        -Wl,--as-needed
        -Wl,--no-copy-dt-needed-entries
    )
endif()
