cmake_minimum_required(VERSION 3.25)

# assumes GCC 16 or Clang-p2996 compiler
function(apply_reflection_flags)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND CMAKE_CXX_COMPILER_VERSION MATCHES "^21")
        execute_process(
            COMMAND ${CMAKE_CXX_COMPILER} --version
            OUTPUT_VARIABLE CLANG_VERSION_OUTPUT
            ERROR_VARIABLE CLANG_VERSION_ERROR
            RESULT_VARIABLE CLANG_VERSION_RESULT
        )
        if(CLANG_VERSION_RESULT EQUAL 0 AND CLANG_VERSION_OUTPUT MATCHES
                                            "https://github.com/bloomberg/clang-p2996.git"
        )
            set(IS_BLOOMBERG_P2996_CLANG ON)
            message(STATUS "Using Bloomberg P2996 Clang fork")
        endif()
    endif()

    if(IS_BLOOMBERG_P2996_CLANG)
        target_compile_options(
            ${PROJECT_NAME}-core INTERFACE -freflection -fexpansion-statements -stdlib=libc++
        )
    else()
        target_compile_options(${PROJECT_NAME}-core INTERFACE -freflection)
    endif()
endfunction()
