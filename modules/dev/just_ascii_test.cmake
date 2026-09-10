if(WIN32)
    find_program(POWERSHELL_CMD NAMES pwsh powershell)
    if(POWERSHELL_CMD)
        add_test(
            NAME just_ascii
            COMMAND ${POWERSHELL_CMD} -NoProfile -ExecutionPolicy Bypass -File
                    "${PROJECT_SOURCE_DIR}/scripts/just_ascii.ps1"
            WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
        )
    else()
        message(
            WARNING "just_ascii test disabled: Powershell not detected on Windows. "
                    "Please install Powershell7 (pwsh) or ensure Windows Powershell is available."
        )
    endif()
else() # unix
    find_program(FIND_CMD find)
    find_program(FILE_CMD file)
    find_program(GREP_CMD grep)
    if(FIND_CMD
       AND FILE_CMD
       AND GREP_CMD
    )
        add_test(
            NAME just_ascii
            COMMAND sh "${PROJECT_SOURCE_DIR}/scripts/just_ascii.sh"
            WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
        )
    else()
        message(WARNING "just_ascii test disabled: required Unix tools not found. "
                        "Please install 'find', 'file', and 'grep'."
        )
    endif() # unix
endif(WIN32)
