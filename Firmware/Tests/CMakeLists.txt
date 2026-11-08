set(NXS_REPOSITORY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(NXS_TINYUSB_SOURCE "${NXS_REPOSITORY_ROOT}/.tools/pico-sdk/lib/tinyusb/src")
if(NOT EXISTS "${NXS_REPOSITORY_ROOT}/.build/firmware/i2s.pio.h" OR NOT EXISTS "${NXS_TINYUSB_SOURCE}/tusb.h")
    message(FATAL_ERROR "Run bash Scripts/firmware.sh before firmware integration tests.")
endif()

nxs_add_host_test(pio pio_tests.c nxs_device)
target_include_directories(nxs_pio_tests PRIVATE "${NXS_REPOSITORY_ROOT}/.build/firmware")
target_compile_definitions(nxs_pio_tests PRIVATE PICO_NO_HARDWARE=1)

function(nxs_add_usb_test name source)
    nxs_add_host_test("${name}" "${source}" nxs_device ${ARGN})
    set(target "nxs_${name}_tests")
    target_sources("${target}" PRIVATE ../USB/descriptors.c)
    target_include_directories("${target}" PRIVATE ../USB ../Platform)
    target_include_directories("${target}" SYSTEM PRIVATE "${NXS_TINYUSB_SOURCE}"
        "${NXS_REPOSITORY_ROOT}/.tools/pico-sdk/src/common/pico_usb_reset_interface_headers/include")
    target_compile_definitions("${target}" PRIVATE CFG_TUSB_MCU=OPT_MCU_NONE CFG_TUSB_OS=OPT_OS_NONE TUP_DCD_ENDPOINT_MAX=16)
endfunction()

nxs_add_usb_test(descriptor descriptor_tests.c)

# TinyUSB's own audio class driver, compiled for the host so the feedback packet format is read at
# the usbd boundary. The pinned checkout carries Firmware/ThirdParty's feedback patch, and this build
# is what catches a TinyUSB bump dropping it. TinyUSB is not held to the firmware's pedantic flags.
add_library(nxs_tinyusb_audio_host STATIC
    "${NXS_TINYUSB_SOURCE}/class/audio/audio_device.c"
    "${NXS_TINYUSB_SOURCE}/common/tusb_fifo.c")
target_include_directories(nxs_tinyusb_audio_host PRIVATE ../USB $<TARGET_PROPERTY:nxs_device,INTERFACE_INCLUDE_DIRECTORIES>)
target_include_directories(nxs_tinyusb_audio_host SYSTEM PUBLIC "${NXS_TINYUSB_SOURCE}")
target_compile_definitions(nxs_tinyusb_audio_host PUBLIC CFG_TUSB_MCU=OPT_MCU_NONE CFG_TUSB_OS=OPT_OS_NONE TUP_DCD_ENDPOINT_MAX=16)
nxs_add_usb_test(feedback feedback_tests.c)
target_link_libraries(nxs_feedback_tests PRIVATE nxs_tinyusb_audio_host)

nxs_add_usb_test(reset reset_tests.c)
target_sources(nxs_reset_tests PRIVATE ../USB/reset.c)
nxs_add_usb_test(control control_tests.c basic)
target_sources(nxs_control_tests PRIVATE ../USB/control.c)
foreach(case mount packet short-read inflight storage-status storage-flow reset-flow)
    add_test(NAME "control_${case}" COMMAND nxs_control_tests "${case}")
    set_tests_properties("control_${case}" PROPERTIES TIMEOUT 30)
endforeach()

# The pinned TinyUSB's own RP2 device port, which aborts a pending transfer before it reactivates an ISO
# endpoint. These tests are what catch a TinyUSB bump that loses that. Like the audio driver above, the
# port is not held to the firmware's pedantic flags.
set(NXS_RP2_PORT_SOURCES "${NXS_TINYUSB_SOURCE}/portable/raspberrypi/rp2040/dcd_rp2040.c"
    "${NXS_TINYUSB_SOURCE}/portable/raspberrypi/rp2040/rp2040_usb.c")
nxs_add_host_test(rp2_iso usb_iso_tests.c nxs_device)
target_sources(nxs_rp2_iso_tests PRIVATE ${NXS_RP2_PORT_SOURCES})
set_source_files_properties(${NXS_RP2_PORT_SOURCES} TARGET_DIRECTORY nxs_rp2_iso_tests PROPERTIES COMPILE_OPTIONS "-Wno-error")
target_include_directories(nxs_rp2_iso_tests PRIVATE Support/pico ../USB)
target_include_directories(nxs_rp2_iso_tests SYSTEM PRIVATE "${NXS_TINYUSB_SOURCE}"
    "${NXS_TINYUSB_SOURCE}/portable/raspberrypi/rp2040"
    "${NXS_REPOSITORY_ROOT}/.tools/pico-sdk/src/rp2350/hardware_regs/include"
    "${NXS_REPOSITORY_ROOT}/.tools/pico-sdk/src/rp2350/hardware_structs/include")
target_compile_definitions(nxs_rp2_iso_tests PRIVATE CFG_TUSB_MCU=OPT_MCU_RP2040 CFG_TUSB_OS=OPT_OS_NONE
    PICO_RP2040_USB_DEVICE_UFRAME_FIX=0 PICO_RP2040_USB_DEVICE_ENUMERATION_FIX=0)
