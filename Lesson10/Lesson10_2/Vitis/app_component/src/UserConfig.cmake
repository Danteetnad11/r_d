set(USER_LINKER_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/lscript.ld")

# Configure with -DAPP_TIME_SCALE=1000 for the accelerated simulation ELF.
set(APP_TIME_SCALE "1" CACHE STRING "Application time acceleration (1 for hardware)")
if(NOT APP_TIME_SCALE MATCHES "^[1-9][0-9]*$")
    message(FATAL_ERROR "APP_TIME_SCALE must be a positive integer")
endif()
list(APPEND USER_COMPILE_DEFINITIONS APP_TIME_SCALE=${APP_TIME_SCALE})
if(APP_TIME_SCALE GREATER 1)
    string(APPEND USER_COMPILE_OPTIONS " -O2")
endif()
