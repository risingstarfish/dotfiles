#
# ${USER_CMAKECACHE} contains the *user-specified* dotfiles options so you can
# call cmake on another branch or repository with the same options.
#

file(READ "${BINARY_DIR}/CMakeCache.txt" cache)
# Escape semicolons, so the lines can be safely iterated in CMake
string(REPLACE ";" "\\;" cache "${cache}")
# Turn the contents into a list
string(REPLACE "\n" ";" cache "${cache}")

message(STATUS "${USER_CMAKECACHE}")

file(REMOVE "${USER_CMAKECACHE}")
foreach(line IN LISTS cache)
    if(line MATCHES "^DOTFILES_" AND NOT line MATCHES "^DOTFILES_LIB_")
        file(APPEND "${USER_CMAKECACHE}" "${line}\n")
    endif()
endforeach()
