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
nxs_add_usb_test(reset reset_tests.c)
target_sources(nxs_reset_tests PRIVATE ../USB/reset.c)
nxs_add_usb_test(control control_tests.c basic)
target_sources(nxs_control_tests PRIVATE ../USB/control.c)
foreach(case mount packet short-read inflight storage-status storage-flow reset-flow)
    add_test(NAME "control_${case}" COMMAND nxs_control_tests "${case}")
    set_tests_properties("control_${case}" PROPERTIES TIMEOUT 30)
endforeach()

function(nxs_add_rp2_iso_test name driver)
    nxs_add_host_test("${name}" usb_iso_tests.c nxs_device)
    set(target "nxs_${name}_tests")
    target_sources("${target}" PRIVATE "${driver}" "${NXS_TINYUSB_SOURCE}/portable/raspberrypi/rp2040/rp2040_usb.c")
    target_include_directories("${target}" PRIVATE Support/Pico ../USB)
    target_include_directories("${target}" SYSTEM PRIVATE "${NXS_TINYUSB_SOURCE}"
        "${NXS_TINYUSB_SOURCE}/portable/raspberrypi/rp2040"
        "${NXS_REPOSITORY_ROOT}/.tools/pico-sdk/src/rp2350/hardware_regs/include"
        "${NXS_REPOSITORY_ROOT}/.tools/pico-sdk/src/rp2350/hardware_structs/include")
    target_compile_definitions("${target}" PRIVATE CFG_TUSB_MCU=OPT_MCU_RP2040 CFG_TUSB_OS=OPT_OS_NONE
        PICO_RP2040_USB_DEVICE_UFRAME_FIX=0 PICO_RP2040_USB_DEVICE_ENUMERATION_FIX=0)
endfunction()
nxs_add_rp2_iso_test(rp2_iso "${CMAKE_CURRENT_SOURCE_DIR}/../ThirdParty/TinyUSB/rp2040/dcd_rp2040.c")
nxs_add_rp2_iso_test(rp2_iso_unpatched "${NXS_TINYUSB_SOURCE}/portable/raspberrypi/rp2040/dcd_rp2040.c")
set_tests_properties(rp2_iso_unpatched PROPERTIES WILL_FAIL TRUE)
