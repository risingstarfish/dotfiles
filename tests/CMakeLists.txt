link_libraries(dotfiles)

cpmaddpackage(
    NAME
    Catch2
    VERSION
    3.15.2
    GIT_REPOSITORY
    https://github.com/catchorg/Catch2.git
    GIT_TAG
    191fa38c9b1596cd2576ab531d4ab4d5e8e05190
)

add_executable(config_read config_read.cpp)
# Propagate the embedded config JSON to tests
if(DEFINED CONFIG_JSON_ESCAPED)
    target_compile_definitions(config_read PRIVATE CONFIG_JSON="${CONFIG_JSON_ESCAPED}")
endif()
target_link_libraries(config_read PRIVATE Catch2::Catch2WithMain)
set_target_properties(
    config_read PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/tests"
)
add_test(config_read config_read)
