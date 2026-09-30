cmake_minimum_required(VERSION 3.28)

#
# sanitizers
#
if(NOT DEFINED CMAKE_POSITION_INDEPENDENT_CODE)
    # We default to ON for all targets, so that we can use the library in shared libraries.
    set_target_properties(internal-flags PROPERTIES INTERFACE_POSITION_INDEPENDENT_CODE ON)
endif()

if(DOTFILES_SANITIZE_ADDRESS AND DOTFILES_SANITIZE_THREAD)
    message(FATAL_ERROR "DOTFILES_SANITIZE_ADDRESS and DOTFILES_SANITIZE_THREAD are incompatible")
endif()

if(DOTFILES_SANITIZE_UNDEFINED)
    message(STATUS "Setting the undefined sanitizer")
    target_compile_options(internal-flags INTERFACE -fsanitize=undefined -fno-sanitize-recover=all)
    target_link_options(internal-flags INTERFACE -fsanitize=undefined -fno-sanitize-recover=all)
endif()
if(DOTFILES_SANITIZE_ADDRESS)
    message(STATUS "Setting both the address and undefined sanitizers")
    target_compile_options(
        internal-flags INTERFACE -fsanitize=address -fno-omit-frame-pointer -fsanitize=undefined
                                 -fno-sanitize-recover=all
    )
    target_link_ibraries(
        internal-flags INTERFACE -fsanitize=address -fno-omit-frame-pointer -fsanitize=undefined
        -fno-sanitize-recover=all
    )
endif()
if(DOTFILES_SANITIZE_THREAD)
    message(STATUS "Setting the both the thread and undefined sanitizers")
    target_compile_options(
        internal-flags INTERFACE -fsanitize=thread -fsanitize=undefined -fno-sanitize-recover=all
    )
    target_link_options(
        internal-flags INTERFACE -fsanitize=thread -fsanitize=undefined -fno-sanitize-recover=all
    )
endif()

if(DOTFILES_SANITIZE_ADDRESS
   OR DOTFILES_SANITIZE_THREAD
   OR DOTFILES_SANITIZE_UNDEFINED
)
    # Ubuntu bug for GCC 5.0+ (safe for all versions)
    if(CMAKE_COMPILER_IS_GNUCC)
        target_link_libraries(internal-flags INTERFACE -fuse-ld=gold)
    endif()
endif()

get_cmake_property(is_multi_config GENERATOR_IS_MULTI_CONFIG)
if(NOT is_multi_config AND NOT CMAKE_BUILD_TYPE)
    # Deliberately not including DOTFILES_SANITIZE_THREADS
    # since thread behavior depends on the build type.
    if(DOTFILES_SANITIZE_ADDRESS OR DOTFILES_SANITIZE_UNDEFINED)
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
