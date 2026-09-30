cmake_minimum_required(VERSION 3.28...4.4.0)

add_executable(${PROJECT_NAME} ${PROJECT_NAME}.cpp)
target_link_libraries(${PROJECT_NAME} PRIVATE internal-flags)
