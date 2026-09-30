cmake_minimum_required(VERSION 3.28...4.4.0)

# https://www.reddit.com/r/cpp_questions/comments/1bsh7nd/undefined_reference_to_std_open_terminal/
if(MINGW AND CMAKE_CXX_COMPILER_ID STREQUAL GNU)
    target_link_libraries(${PROJECT_NAME}-core INTERFACE stdc++exp)
endif()

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
