cmake_minimum_required(3.25)

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
        ${PROJECT_NAME} PRIVATE -freflection -fexpansion-statements -stdlib=libc++
    )
else()
    target_compile_options(${PROJECT_NAME} PRIVATE -freflection)
endif()
