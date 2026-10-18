cmake_minimum_required(VERSION 3.22)

file(READ "${CMAKE_CURRENT_LIST_DIR}/../toolchain.json" NXS_TOOLCHAIN)
string(JSON PICO_BOARD GET "${NXS_TOOLCHAIN}" firmware board)
string(JSON PICOTOOL_GIT_BRANCH GET "${NXS_TOOLCHAIN}" firmware picotool commit)

if(NOT PICO_SDK_PATH)
    message(FATAL_ERROR "Run bash Scripts/firmware.sh from the repository root.")
endif()
include("${PICO_SDK_PATH}/pico_sdk_init.cmake")
project(NeXTsoundFirmware LANGUAGES C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
pico_sdk_init()

# Backport TinyUSB 102c199 without changing the SDK's other tested USB sources.
set(NXS_RP2_PORT "${CMAKE_CURRENT_LIST_DIR}/ThirdParty/TinyUSB/rp2040/dcd_rp2040.c")
set(NXS_PINNED_RP2_PORT "${PICO_TINYUSB_PATH}/src/portable/raspberrypi/rp2040/dcd_rp2040.c")
get_target_property(NXS_USB_DEVICE_SOURCES tinyusb_device_base INTERFACE_SOURCES)
list(FIND NXS_USB_DEVICE_SOURCES "${NXS_PINNED_RP2_PORT}" NXS_RP2_PORT_INDEX)
if(NXS_RP2_PORT_INDEX EQUAL -1)
    message(FATAL_ERROR "The pinned TinyUSB device source list changed; review the RP2 ISO backport.")
endif()
list(REMOVE_AT NXS_USB_DEVICE_SOURCES ${NXS_RP2_PORT_INDEX})
list(INSERT NXS_USB_DEVICE_SOURCES ${NXS_RP2_PORT_INDEX} "${NXS_RP2_PORT}")
set_property(TARGET tinyusb_device_base PROPERTY INTERFACE_SOURCES "${NXS_USB_DEVICE_SOURCES}")
target_include_directories(tinyusb_device_base SYSTEM INTERFACE "${PICO_TINYUSB_PATH}/src/portable/raspberrypi/rp2040")

pico_define_boot_stage2(nxs_read_only_boot2 "${PICO_SDK_PATH}/src/rp2350/boot_stage2/boot2_generic_03h.S")
target_compile_definitions(nxs_read_only_boot2 PRIVATE PICO_FLASH_SPI_CLKDIV=4)

add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../Shared" "${CMAKE_CURRENT_BINARY_DIR}/shared")
add_subdirectory(Core)
add_executable(nxs_dsp_probe probe.c)
pico_set_boot_stage2(nxs_dsp_probe nxs_read_only_boot2)
target_link_libraries(nxs_dsp_probe PRIVATE nxs_dsp pico_stdlib hardware_clocks)
target_compile_options(nxs_dsp_probe PRIVATE -Wall -Wextra -Werror)
pico_enable_stdio_usb(nxs_dsp_probe 0)
pico_enable_stdio_uart(nxs_dsp_probe 0)
pico_set_program_name(nxs_dsp_probe "NeXTsound DSP build probe")
pico_set_program_description(nxs_dsp_probe "Muted DSP cross-build probe; no USB or audio output")
pico_add_extra_outputs(nxs_dsp_probe)

find_package(Git REQUIRED)
execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --short=8 HEAD
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/.." OUTPUT_VARIABLE NXS_GIT_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND "${GIT_EXECUTABLE}" diff-index --quiet HEAD --
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/.." RESULT_VARIABLE NXS_GIT_DIRTY)
if(NXS_GIT_DIRTY)
    string(APPEND NXS_GIT_VERSION "-dirty")
endif()

add_executable(nxs_firmware main.c Platform/engine.c Platform/i2s.c Platform/flash_storage.c USB/control.c USB/descriptors.c USB/reset.c)
pico_set_boot_stage2(nxs_firmware nxs_read_only_boot2)
target_include_directories(nxs_firmware PRIVATE Platform USB)
target_link_libraries(nxs_firmware PRIVATE nxs_device pico_stdlib pico_multicore pico_unique_id pico_util
    tinyusb_device tinyusb_board pico_flash pico_usb_reset_interface_headers hardware_flash hardware_clocks hardware_pio hardware_dma)
target_compile_options(nxs_firmware PRIVATE -Wall -Wextra -Werror -fstack-usage)
foreach(NXS_LIBRARY nxs_protocol nxs_dsp nxs_device nxs_storage)
    target_compile_options(${NXS_LIBRARY} PRIVATE -fstack-usage)
endforeach()
target_compile_definitions(nxs_firmware PRIVATE NXS_FIRMWARE_VERSION="${NXS_GIT_VERSION}"
    PICO_STACK_SIZE=0x1000 PICO_CORE1_STACK_SIZE=0x1000
    PICO_FLASH_ASSUME_CORE0_SAFE=0 PICO_FLASH_ASSUME_CORE1_SAFE=0 PICO_FLASH_ASSERT_ON_UNSAFE=0)
pico_generate_pio_header(nxs_firmware "${CMAKE_CURRENT_LIST_DIR}/Platform/i2s.pio")
pico_enable_stdio_usb(nxs_firmware 0)
pico_enable_stdio_uart(nxs_firmware 0)
pico_set_program_name(nxs_firmware "NeXTsound development firmware")
pico_set_program_version(nxs_firmware "${NXS_GIT_VERSION}")
pico_set_program_description(nxs_firmware "USB audio and HID control; mono I2S; muted start")
pico_add_extra_outputs(nxs_firmware)

add_executable(nxs_flash_probe Probes/flash_probe.c)
pico_set_binary_type(nxs_flash_probe no_flash)
target_include_directories(nxs_flash_probe PRIVATE ../Shared/Sources/NeXTsoundProtocol/include)
target_link_libraries(nxs_flash_probe PRIVATE pico_stdlib pico_stdio_usb pico_unique_id hardware_clocks hardware_flash hardware_sync)
target_compile_options(nxs_flash_probe PRIVATE -Wall -Wextra -Werror -fstack-usage)
pico_enable_stdio_usb(nxs_flash_probe 1)
pico_enable_stdio_uart(nxs_flash_probe 0)
pico_set_program_name(nxs_flash_probe "NeXTsound RAM flash metadata probe")
pico_set_program_version(nxs_flash_probe "${NXS_GIT_VERSION}")
pico_set_program_description(nxs_flash_probe "RAM-only JEDEC and SFDP reader; no audio or flash programming")
pico_add_extra_outputs(nxs_flash_probe)

set(NXS_STORAGE_BOUNDS "${CMAKE_CURRENT_BINARY_DIR}/storage_bounds.ld")
add_custom_command(OUTPUT "${NXS_STORAGE_BOUNDS}"
    COMMAND "${CMAKE_C_COMPILER}" -E -P -x c -I "${CMAKE_CURRENT_LIST_DIR}/Core/include"
        "${CMAKE_CURRENT_LIST_DIR}/Platform/storage_bounds.ld.S" -o "${NXS_STORAGE_BOUNDS}"
    DEPENDS Platform/storage_bounds.ld.S Core/include/nxs_storage_layout.h
    VERBATIM)
add_custom_target(nxs_storage_bounds DEPENDS "${NXS_STORAGE_BOUNDS}")
foreach(NXS_TARGET nxs_firmware nxs_dsp_probe)
    add_dependencies(${NXS_TARGET} nxs_storage_bounds)
    target_link_options(${NXS_TARGET} PRIVATE "LINKER:--script=${NXS_STORAGE_BOUNDS}")
    pico_add_link_depend(${NXS_TARGET} "${NXS_STORAGE_BOUNDS}")
endforeach()
