cmake_minimum_required(VERSION 3.25...4.4)

if(DOTFILES_USE_MODULES AND CMAKE_VERSION VERSION_LESS "3.28")
    message(FATAL_ERROR "DOTFILES_USE_MODULES requires CMake >= 3.28")
endif()

if(DOTFILES_MODULE_IMPORT_STD
   AND DOTFILES_USE_MODULES
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

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(${PROJECT_NAME} src/dotfiles.cpp)
target_include_directories(${PROJECT_NAME} PRIVATE include)
target_compile_options(${PROJECT_NAME} PRIVATE -freflection)
