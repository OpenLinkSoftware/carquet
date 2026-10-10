# Merge a list of static archives into a single output archive.
# Uses Apple libtool on macOS and GNU ar MRI elsewhere.
# Usage (via cmake -P):
#   cmake -DOUTPUT=/path/libcarquet.a
#         "-DINPUTS=/path/libcarquet.a;/path/liblz4.a;..."
#         -P merge_archives.cmake
#
# The first element of INPUTS must be OUTPUT itself (it is renamed to a
# temporary backup so the merge tool can create a fresh OUTPUT from all inputs).

cmake_minimum_required(VERSION 3.16)

get_filename_component(_out_dir  "${OUTPUT}" DIRECTORY)
get_filename_component(_out_name "${OUTPUT}" NAME_WE)

if(NOT CMAKE_AR)
    set(CMAKE_AR ar)
endif()
if(NOT CMAKE_RANLIB)
    set(CMAKE_RANLIB ranlib)
endif()

foreach(_lib IN LISTS INPUTS)
    if(NOT EXISTS "${_lib}")
        message(FATAL_ERROR "Archive merge input does not exist: ${_lib}")
    endif()
    get_filename_component(_ext "${_lib}" EXT)
    if(NOT _ext MATCHES "^\\.(a|lib)$")
        message(FATAL_ERROR
            "Archive merge input is not a static archive: ${_lib}. "
            "Use static dependencies when CARQUET_BUNDLE_STATIC_DEPS is enabled.")
    endif()
endforeach()

# Rename the existing output archive so the merge tool can create a fresh output.
set(_backup "${OUTPUT}.orig")
if(EXISTS "${_backup}")
    file(REMOVE "${_backup}")
endif()
file(RENAME "${OUTPUT}" "${_backup}")

set(_merge_inputs)
foreach(_lib IN LISTS INPUTS)
    if("${_lib}" STREQUAL "${OUTPUT}")
        list(APPEND _merge_inputs "${_backup}")
    else()
        list(APPEND _merge_inputs "${_lib}")
    endif()
endforeach()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    find_program(_libtool libtool)
    if(NOT _libtool)
        file(RENAME "${_backup}" "${OUTPUT}")
        message(FATAL_ERROR "libtool is required to merge static archives on macOS")
    endif()
    execute_process(
        COMMAND "${_libtool}" -static -o "${OUTPUT}" ${_merge_inputs}
        RESULT_VARIABLE _res
        ERROR_VARIABLE  _err
    )
else()
    # Build GNU ar MRI script.
    set(_mri "CREATE ${OUTPUT}\n")
    foreach(_lib IN LISTS _merge_inputs)
        string(APPEND _mri "ADDLIB ${_lib}\n")
    endforeach()
    string(APPEND _mri "SAVE\nEND\n")

    set(_mri_path "${_out_dir}/_merge_${_out_name}.mri")
    file(WRITE "${_mri_path}" "${_mri}")

    execute_process(
        COMMAND "${CMAKE_AR}" -M
        INPUT_FILE "${_mri_path}"
        RESULT_VARIABLE _res
        ERROR_VARIABLE  _err
    )

    file(REMOVE "${_mri_path}")
endif()

if(NOT _res EQUAL 0)
    if(EXISTS "${OUTPUT}")
        file(REMOVE "${OUTPUT}")
    endif()
    file(RENAME "${_backup}" "${OUTPUT}")
    message(FATAL_ERROR "Static archive merge failed (${_res}): ${_err}")
endif()

file(REMOVE "${_backup}")

# Regenerate the symbol table
execute_process(COMMAND "${CMAKE_RANLIB}" "${OUTPUT}")
