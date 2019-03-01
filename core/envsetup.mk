# Variables we check:
#     HOST_BUILD_TYPE = { release debug }
#     TARGET_BUILD_TYPE = { release debug }
# and we output a bunch of variables, see the case statement at
# the bottom for the full list
#     OUT_DIR is also set to "out" if it's not already set.
#         this allows you to set it to somewhere else if you like
#     SCAN_EXCLUDE_DIRS is an optional, whitespace separated list of
#         directories that will also be excluded from full checkout tree
#         searches for source or make files, in addition to OUT_DIR.
#         This can be useful if you set OUT_DIR to be a different directory
#         than other outputs of your build system.

# Returns all words in $1 up to and including $2
define find_and_earlier
  $(strip $(if $(1),
    $(firstword $(1))
    $(if $(filter $(firstword $(1)),$(2)),,
      $(call find_and_earlier,$(wordlist 2,$(words $(1)),$(1)),$(2)))))
endef

#$(warning $(call find_and_earlier,A B C,A))
#$(warning $(call find_and_earlier,A B C,B))
#$(warning $(call find_and_earlier,A B C,C))
#$(warning $(call find_and_earlier,A B C,D))

define version-list
$(1)PR1 $(1)PD1 $(1)PD2 $(1)PM1 $(1)PM2
endef

ALL_VERSIONS := O P Q R S T U V W X Y Z
ALL_VERSIONS := $(foreach v,$(ALL_VERSIONS),$(call version-list,$(v)))

# Filters ALL_VERSIONS down to the range [$1, $2], and errors if $1 > $2 or $3 is
# not in [$1, $2]
# $(1): min platform version
# $(2): max platform version
# $(3): default platform version
define allowed-platform-versions
$(strip \
  $(if $(filter $(ALL_VERSIONS),$(1)),,
    $(error Invalid MIN_PLATFORM_VERSION '$(1)'))
  $(if $(filter $(ALL_VERSIONS),$(2)),,
    $(error Invalid MAX_PLATFORM_VERSION '$(2)'))
  $(if $(filter $(ALL_VERSIONS),$(3)),,
    $(error Invalid DEFAULT_PLATFORM_VERSION '$(3)'))

  $(eval allowed_versions_ := $(call find_and_earlier,$(ALL_VERSIONS),$(2)))

  $(if $(filter $(allowed_versions_),$(1)),,
    $(error MIN_PLATFORM_VERSION '$(1)' must be before MAX_PLATFORM_VERSION '$(2)'))

  $(eval allowed_versions_ := $(1) \
    $(filter-out $(call find_and_earlier,$(allowed_versions_),$(1)),$(allowed_versions_)))

  $(if $(filter $(allowed_versions_),$(3)),,
    $(error DEFAULT_PLATFORM_VERSION '$(3)' must be between MIN_PLATFORM_VERSION '$(1)' and MAX_PLATFORM_VERSION '$(2)'))

  $(allowed_versions_))
endef

#$(warning $(call allowed-platform-versions,OPR1,PPR1,OPR1))
#$(warning $(call allowed-platform-versions,OPM1,PPR1,OPR1))

# Set up version information.
include $(BUILD_SYSTEM)/version_defaults.mk

ENABLED_VERSIONS := $(call find_and_earlier,$(ALL_VERSIONS),$(TARGET_PLATFORM_VERSION))

$(foreach v,$(ENABLED_VERSIONS), \
  $(eval IS_AT_LEAST_$(v) := true))

# ---------------------------------------------------------------
# If you update the build system such that the environment setup
# or buildspec.mk need to be updated, increment this number, and
# people who haven't re-run those will have to do so before they
# can build.  Make sure to also update the corresponding value in
# buildspec.mk.default and envsetup.sh.
CORRECT_BUILD_ENV_SEQUENCE_NUMBER := 13

# ---------------------------------------------------------------
# The product defaults to generic on hardware
# NOTE: This will be overridden in product_config.mk if make
# was invoked with a PRODUCT-xxx-yyy goal.
ifeq ($(TARGET_PRODUCT),)
TARGET_PRODUCT := aosp_arm
endif


# the variant -- the set of files that are included for a build
ifeq ($(strip $(TARGET_BUILD_VARIANT)),)
TARGET_BUILD_VARIANT := eng
endif

# ---------------------------------------------------------------
# Set up configuration for host machine.  We don't do cross-
# compiles except for arm/mips, so the HOST is whatever we are
# running on

# HOST_OS
ifneq (,$(findstring Linux,$(UNAME)))
  HOST_OS := linux
endif
ifneq (,$(findstring Darwin,$(UNAME)))
  HOST_OS := darwin
endif
ifneq (,$(findstring Macintosh,$(UNAME)))
  HOST_OS := darwin
endif

HOST_OS_EXTRA := $(shell uname -rsm)
ifeq ($(HOST_OS),linux)
  ifneq ($(wildcard /etc/os-release),)
    HOST_OS_EXTRA += $(shell source /etc/os-release; echo $$PRETTY_NAME)
  endif
else ifeq ($(HOST_OS),darwin)
  HOST_OS_EXTRA += $(shell sw_vers -productVersion)
endif
HOST_OS_EXTRA := $(subst $(space),-,$(HOST_OS_EXTRA))

# BUILD_OS is the real host doing the build.
BUILD_OS := $(HOST_OS)

HOST_CROSS_OS :=
# We can cross-build Windows binaries on Linux
ifeq ($(HOST_OS),linux)
ifeq ($(BUILD_HOST_static),)
HOST_CROSS_OS := windows
HOST_CROSS_ARCH := x86
HOST_CROSS_2ND_ARCH := x86_64
2ND_HOST_CROSS_IS_64_BIT := true
endif
endif

ifeq ($(HOST_OS),)
$(error Unable to determine HOST_OS from uname -sm: $(UNAME)!)
endif

# HOST_ARCH
ifneq (,$(findstring x86_64,$(UNAME)))
  HOST_ARCH := x86_64
  HOST_2ND_ARCH := x86
  HOST_IS_64_BIT := true
else
ifneq (,$(findstring i686,$(UNAME))$(findstring x86,$(UNAME)))
$(error Building on a 32-bit x86 host is not supported: $(UNAME)!)
endif
endif

ifeq ($(HOST_OS),darwin)
  # Mac no longer supports 32-bit executables
  HOST_2ND_ARCH :=
endif

HOST_2ND_ARCH_VAR_PREFIX := 2ND_
HOST_2ND_ARCH_MODULE_SUFFIX := _32
HOST_CROSS_2ND_ARCH_VAR_PREFIX := 2ND_
HOST_CROSS_2ND_ARCH_MODULE_SUFFIX := _64
TARGET_2ND_ARCH_VAR_PREFIX := 2ND_
.KATI_READONLY := \
  HOST_ARCH \
  HOST_2ND_ARCH \
  HOST_IS_64_BIT \
  HOST_2ND_ARCH_VAR_PREFIX \
  HOST_2ND_ARCH_MODULE_SUFFIX \
  HOST_CROSS_2ND_ARCH_VAR_PREFIX \
  HOST_CROSS_2ND_ARCH_MODULE_SUFFIX \
  TARGET_2ND_ARCH_VAR_PREFIX \

combo_target := HOST_
combo_2nd_arch_prefix :=
include $(BUILD_COMBOS)/select.mk

ifdef HOST_2ND_ARCH
  combo_2nd_arch_prefix := $(HOST_2ND_ARCH_VAR_PREFIX)
  include $(BUILD_SYSTEM)/combo/select.mk
endif

# Load the windows cross compiler under Linux
ifdef HOST_CROSS_OS
  combo_target := HOST_CROSS_
  combo_2nd_arch_prefix :=
  include $(BUILD_SYSTEM)/combo/select.mk

  ifdef HOST_CROSS_2ND_ARCH
    combo_2nd_arch_prefix := $(HOST_CROSS_2ND_ARCH_VAR_PREFIX)
    include $(BUILD_SYSTEM)/combo/select.mk
  endif
endif

# on windows, the tools have .exe at the end, and we depend on the
# host config stuff being done first

BUILD_ARCH := $(HOST_ARCH)
BUILD_2ND_ARCH := $(HOST_2ND_ARCH)

ifeq ($(HOST_ARCH),)
$(error Unable to determine HOST_ARCH from uname -sm: $(UNAME)!)
endif

# the host build defaults to release, and it must be release or debug
ifeq ($(HOST_BUILD_TYPE),)
HOST_BUILD_TYPE := release
endif

ifneq ($(HOST_BUILD_TYPE),release)
ifneq ($(HOST_BUILD_TYPE),debug)
$(error HOST_BUILD_TYPE must be either release or debug, not '$(HOST_BUILD_TYPE)')
endif
endif

# We don't want to move all the prebuilt host tools to a $(HOST_OS)-x86_64 dir.
HOST_PREBUILT_ARCH := x86
# This is the standard way to name a directory containing prebuilt host
# objects. E.g., prebuilt/$(HOST_PREBUILT_TAG)/cc
HOST_PREBUILT_TAG := $(BUILD_OS)-$(HOST_PREBUILT_ARCH)

# TARGET_COPY_OUT_* are all relative to the staging directory, ie PRODUCT_OUT.
# Define them here so they can be used in product config files.
TARGET_COPY_OUT_SYSTEM := system
TARGET_COPY_OUT_SYSTEM_OTHER := system_other
TARGET_COPY_OUT_DATA := data
TARGET_COPY_OUT_ASAN := $(TARGET_COPY_OUT_DATA)/asan
TARGET_COPY_OUT_OEM := oem
TARGET_COPY_OUT_RAMDISK := ramdisk
TARGET_COPY_OUT_ROOT := root
TARGET_COPY_OUT_RECOVERY := recovery
# The directory used for optional partitions depend on the BoardConfig, so
# they're defined to placeholder values here and swapped after reading the
# BoardConfig, to be either the partition dir, or a subdir within 'system'.
_vendor_path_placeholder := ||VENDOR-PATH-PH||
_product_path_placeholder := ||PRODUCT-PATH-PH||
_product_services_path_placeholder := ||PRODUCT_SERVICES-PATH-PH||
_odm_path_placeholder := ||ODM-PATH-PH||
TARGET_COPY_OUT_VENDOR := $(_vendor_path_placeholder)
TARGET_COPY_OUT_PRODUCT := $(_product_path_placeholder)
TARGET_COPY_OUT_PRODUCT_SERVICES := $(_product_services_path_placeholder)
TARGET_COPY_OUT_ODM := $(_odm_path_placeholder)

# Returns the non-sanitized version of the path provided in $1.
define get_non_asan_path
$(patsubst $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/%,$(PRODUCT_OUT)/%,$1)
endef

#################################################################
# Set up minimal BOOTCLASSPATH list of jars to build/execute
# java code with dalvikvm/art.
# Jars present in the runtime apex. These should match exactly the list of
# Java libraries in the runtime apex build rule.
RUNTIME_APEX_JARS := core-oj core-libart okhttp bouncycastle apache-xml
TARGET_CORE_JARS := $(RUNTIME_APEX_JARS) conscrypt
ifeq ($(EMMA_INSTRUMENT),true)
  ifneq ($(EMMA_INSTRUMENT_STATIC),true)
    # For instrumented build, if Jacoco is not being included statically
    # in instrumented packages then include Jacoco classes into the
    # bootclasspath.
    TARGET_CORE_JARS += jacocoagent
  endif # EMMA_INSTRUMENT_STATIC
endif # EMMA_INSTRUMENT
HOST_CORE_JARS := $(addsuffix -hostdex,$(TARGET_CORE_JARS))
#################################################################

# Read the product specs so we can get TARGET_DEVICE and other
# variables that we need in order to locate the output files.
include $(BUILD_SYSTEM)/product_config.mk

build_variant := $(filter-out eng user userdebug,$(TARGET_BUILD_VARIANT))
ifneq ($(build_variant)-$(words $(TARGET_BUILD_VARIANT)),-1)
$(warning bad TARGET_BUILD_VARIANT: $(TARGET_BUILD_VARIANT))
$(error must be empty or one of: eng user userdebug)
endif

SDK_HOST_ARCH := x86
TARGET_OS := linux

include $(BUILD_SYSTEM)/board_config.mk

# the target build type defaults to release
ifneq ($(TARGET_BUILD_TYPE),debug)
TARGET_BUILD_TYPE := release
endif

# ---------------------------------------------------------------
# figure out the output directories

SOONG_OUT_DIR := $(OUT_DIR)/soong

TARGET_OUT_ROOT := $(OUT_DIR)/target

HOST_OUT_ROOT := $(OUT_DIR)/host

.KATI_READONLY := SOONG_OUT_DIR TARGET_OUT_ROOT HOST_OUT_ROOT

# We want to avoid two host bin directories in multilib build.
HOST_OUT := $(HOST_OUT_ROOT)/$(HOST_OS)-$(HOST_PREBUILT_ARCH)
SOONG_HOST_OUT := $(SOONG_OUT_DIR)/host/$(HOST_OS)-$(HOST_PREBUILT_ARCH)

HOST_CROSS_OUT := $(HOST_OUT_ROOT)/windows-$(HOST_PREBUILT_ARCH)

.KATI_READONLY := HOST_OUT SOONG_HOST_OUT HOST_CROSS_OUT

TARGET_PRODUCT_OUT_ROOT := $(TARGET_OUT_ROOT)/product

TARGET_COMMON_OUT_ROOT := $(TARGET_OUT_ROOT)/common
HOST_COMMON_OUT_ROOT := $(HOST_OUT_ROOT)/common

PRODUCT_OUT := $(TARGET_PRODUCT_OUT_ROOT)/$(TARGET_DEVICE)

.KATI_READONLY := TARGET_PRODUCT_OUT_ROOT TARGET_COMMON_OUT_ROOT HOST_COMMON_OUT_ROOT PRODUCT_OUT

OUT_DOCS := $(TARGET_COMMON_OUT_ROOT)/docs
OUT_NDK_DOCS := $(TARGET_COMMON_OUT_ROOT)/ndk-docs
.KATI_READONLY := OUT_DOCS OUT_NDK_DOCS

$(call KATI_obsolete,BUILD_OUT,Use HOST_OUT instead)

BUILD_OUT_EXECUTABLES := $(HOST_OUT)/bin
SOONG_HOST_OUT_EXECUTABLES := $(SOONG_HOST_OUT)/bin
.KATI_READONLY := BUILD_OUT_EXECUTABLES SOONG_HOST_OUT_EXECUTABLES

HOST_OUT_EXECUTABLES := $(HOST_OUT)/bin
HOST_OUT_SHARED_LIBRARIES := $(HOST_OUT)/lib64
HOST_OUT_RENDERSCRIPT_BITCODE := $(HOST_OUT_SHARED_LIBRARIES)
HOST_OUT_JAVA_LIBRARIES := $(HOST_OUT)/framework
HOST_OUT_SDK_ADDON := $(HOST_OUT)/sdk_addon
HOST_OUT_NATIVE_TESTS := $(HOST_OUT)/nativetest64
HOST_OUT_COVERAGE := $(HOST_OUT)/coverage
HOST_OUT_TESTCASES := $(HOST_OUT)/testcases
.KATI_READONLY := \
  HOST_OUT_EXECUTABLES \
  HOST_OUT_SHARED_LIBRARIES \
  HOST_OUT_RENDERSCRIPT_BITCODE \
  HOST_OUT_JAVA_LIBRARIES \
  HOST_OUT_SDK_ADDON \
  HOST_OUT_NATIVE_TESTS \
  HOST_OUT_COVERAGE \
  HOST_OUT_TESTCASES

HOST_CROSS_OUT_EXECUTABLES := $(HOST_CROSS_OUT)/bin
HOST_CROSS_OUT_SHARED_LIBRARIES := $(HOST_CROSS_OUT)/lib
HOST_CROSS_OUT_NATIVE_TESTS := $(HOST_CROSS_OUT)/nativetest
HOST_CROSS_OUT_COVERAGE := $(HOST_CROSS_OUT)/coverage
HOST_CROSS_OUT_TESTCASES := $(HOST_CROSS_OUT)/testcases
.KATI_READONLY := \
  HOST_CROSS_OUT_EXECUTABLES \
  HOST_CROSS_OUT_SHARED_LIBRARIES \
  HOST_CROSS_OUT_NATIVE_TESTS \
  HOST_CROSS_OUT_COVERAGE \
  HOST_CROSS_OUT_TESTCASES

HOST_OUT_INTERMEDIATES := $(HOST_OUT)/obj
HOST_OUT_NOTICE_FILES := $(HOST_OUT_INTERMEDIATES)/NOTICE_FILES
HOST_OUT_COMMON_INTERMEDIATES := $(HOST_COMMON_OUT_ROOT)/obj
HOST_OUT_FAKE := $(HOST_OUT)/fake_packages
.KATI_READONLY := \
  HOST_OUT_INTERMEDIATES \
  HOST_OUT_NOTICE_FILES \
  HOST_OUT_COMMON_INTERMEDIATES \
  HOST_OUT_FAKE

# Nano environment config
include $(BUILD_SYSTEM)/aux_config.mk

HOST_CROSS_OUT_INTERMEDIATES := $(HOST_CROSS_OUT)/obj
HOST_CROSS_OUT_NOTICE_FILES := $(HOST_CROSS_OUT_INTERMEDIATES)/NOTICE_FILES
.KATI_READONLY := \
  HOST_CROSS_OUT_INTERMEDIATES \
  HOST_CROSS_OUT_NOTICE_FILES

HOST_OUT_GEN := $(HOST_OUT)/gen
HOST_OUT_COMMON_GEN := $(HOST_COMMON_OUT_ROOT)/gen
.KATI_READONLY := \
  HOST_OUT_GEN \
  HOST_OUT_COMMON_GEN

HOST_CROSS_OUT_GEN := $(HOST_CROSS_OUT)/gen
.KATI_READONLY := HOST_CROSS_OUT_GEN

HOST_OUT_TEST_CONFIG := $(HOST_OUT)/test_config
.KATI_READONLY := HOST_OUT_TEST_CONFIG

# Out for HOST_2ND_ARCH
$(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_INTERMEDIATES := $(HOST_OUT)/obj32
$(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_SHARED_LIBRARIES := $(HOST_OUT)/lib
$(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_EXECUTABLES := $(HOST_OUT_EXECUTABLES)
$(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_JAVA_LIBRARIES := $(HOST_OUT_JAVA_LIBRARIES)
$(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_NATIVE_TESTS := $(HOST_OUT)/nativetest
$(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_TESTCASES := $(HOST_OUT_TESTCASES)
.KATI_READONLY := \
  $(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_INTERMEDIATES \
  $(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_SHARED_LIBRARIES \
  $(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_EXECUTABLES \
  $(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_JAVA_LIBRARIES \
  $(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_NATIVE_TESTS \
  $(HOST_2ND_ARCH_VAR_PREFIX)HOST_OUT_TESTCASES

# The default host library path.
# It always points to the path where we build libraries in the default bitness.
HOST_LIBRARY_PATH := $(HOST_OUT_SHARED_LIBRARIES)
.KATI_READONLY := HOST_LIBRARY_PATH

# Out for HOST_CROSS_2ND_ARCH
$(HOST_CROSS_2ND_ARCH_VAR_PREFIX)HOST_CROSS_OUT_INTERMEDIATES := $(HOST_CROSS_OUT)/obj64
$(HOST_CROSS_2ND_ARCH_VAR_PREFIX)HOST_CROSS_OUT_SHARED_LIBRARIES := $(HOST_CROSS_OUT)/lib64
$(HOST_CROSS_2ND_ARCH_VAR_PREFIX)HOST_CROSS_OUT_EXECUTABLES := $(HOST_CROSS_OUT_EXECUTABLES)
$(HOST_CROSS_2ND_ARCH_VAR_PREFIX)HOST_CROSS_OUT_NATIVE_TESTS := $(HOST_CROSS_OUT)/nativetest64
.KATI_READONLY := \
  $(HOST_CROSS_2ND_ARCH_VAR_PREFIX)HOST_CROSS_OUT_INTERMEDIATES \
  $(HOST_CROSS_2ND_ARCH_VAR_PREFIX)HOST_CROSS_OUT_SHARED_LIBRARIES \
  $(HOST_CROSS_2ND_ARCH_VAR_PREFIX)HOST_CROSS_OUT_EXECUTABLES \
  $(HOST_CROSS_2ND_ARCH_VAR_PREFIX)HOST_CROSS_OUT_NATIVE_TESTS

ifneq ($(filter address,$(SANITIZE_TARGET)),)
  TARGET_OUT_INTERMEDIATES := $(PRODUCT_OUT)/obj_asan
else
  TARGET_OUT_INTERMEDIATES := $(PRODUCT_OUT)/obj
endif
TARGET_OUT_HEADERS := $(TARGET_OUT_INTERMEDIATES)/include
.KATI_READONLY := TARGET_OUT_INTERMEDIATES TARGET_OUT_HEADERS

ifneq ($(filter address,$(SANITIZE_TARGET)),)
  TARGET_OUT_COMMON_INTERMEDIATES := $(TARGET_COMMON_OUT_ROOT)/obj_asan
else
  TARGET_OUT_COMMON_INTERMEDIATES := $(TARGET_COMMON_OUT_ROOT)/obj
endif
.KATI_READONLY := TARGET_OUT_COMMON_INTERMEDIATES

TARGET_OUT_GEN := $(PRODUCT_OUT)/gen
TARGET_OUT_COMMON_GEN := $(TARGET_COMMON_OUT_ROOT)/gen
.KATI_READONLY := TARGET_OUT_GEN TARGET_OUT_COMMON_GEN

TARGET_OUT := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_SYSTEM)
.KATI_READONLY := TARGET_OUT
ifneq ($(filter address,$(SANITIZE_TARGET)),)
target_out_shared_libraries_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/system
ifeq ($(SANITIZE_LITE),true)
# When using SANITIZE_LITE, APKs must not be packaged with sanitized libraries, as they will not
# work with unsanitized app_process. For simplicity, generate APKs into /data/asan/.
target_out_app_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/system
else
target_out_app_base := $(TARGET_OUT)
endif
else
target_out_shared_libraries_base := $(TARGET_OUT)
target_out_app_base := $(TARGET_OUT)
endif

TARGET_OUT_EXECUTABLES := $(TARGET_OUT)/bin
TARGET_OUT_OPTIONAL_EXECUTABLES := $(TARGET_OUT)/xbin
ifeq ($(TARGET_IS_64_BIT),true)
# /system/lib always contains 32-bit libraries,
# and /system/lib64 (if present) always contains 64-bit libraries.
TARGET_OUT_SHARED_LIBRARIES := $(target_out_shared_libraries_base)/lib64
else
TARGET_OUT_SHARED_LIBRARIES := $(target_out_shared_libraries_base)/lib
endif
TARGET_OUT_RENDERSCRIPT_BITCODE := $(TARGET_OUT_SHARED_LIBRARIES)
TARGET_OUT_JAVA_LIBRARIES := $(TARGET_OUT)/framework
TARGET_OUT_APPS := $(target_out_app_base)/app
TARGET_OUT_APPS_PRIVILEGED := $(target_out_app_base)/priv-app
TARGET_OUT_KEYLAYOUT := $(TARGET_OUT)/usr/keylayout
TARGET_OUT_KEYCHARS := $(TARGET_OUT)/usr/keychars
TARGET_OUT_ETC := $(TARGET_OUT)/etc
TARGET_OUT_NOTICE_FILES := $(TARGET_OUT_INTERMEDIATES)/NOTICE_FILES
TARGET_OUT_FAKE := $(PRODUCT_OUT)/fake_packages
TARGET_OUT_TESTCASES := $(PRODUCT_OUT)/testcases
TARGET_OUT_TEST_CONFIG := $(PRODUCT_OUT)/test_config
.KATI_READONLY := \
  TARGET_OUT_EXECUTABLES \
  TARGET_OUT_OPTIONAL_EXECUTABLES \
  TARGET_OUT_SHARED_LIBRARIES \
  TARGET_OUT_RENDERSCRIPT_BITCODE \
  TARGET_OUT_JAVA_LIBRARIES \
  TARGET_OUT_APPS \
  TARGET_OUT_APPS_PRIVILEGED \
  TARGET_OUT_KEYLAYOUT \
  TARGET_OUT_KEYCHARS \
  TARGET_OUT_ETC \
  TARGET_OUT_NOTICE_FILES \
  TARGET_OUT_FAKE \
  TARGET_OUT_TESTCASES \
  TARGET_OUT_TEST_CONFIG

ifeq ($(SANITIZE_LITE),true)
# When using SANITIZE_LITE, APKs must not be packaged with sanitized libraries, as they will not
# work with unsanitized app_process. For simplicity, generate APKs into /data/asan/.
TARGET_OUT_SYSTEM_OTHER := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/$(TARGET_COPY_OUT_SYSTEM_OTHER)
else
TARGET_OUT_SYSTEM_OTHER := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_SYSTEM_OTHER)
endif
.KATI_READONLY := TARGET_OUT_SYSTEM_OTHER

# Out for TARGET_2ND_ARCH
ifeq ($(TARGET_TRANSLATE_2ND_ARCH),true)
# With this you can reference the arm binary translation library with libfoo_arm in PRODUCT_PACKAGES.
TARGET_2ND_ARCH_MODULE_SUFFIX := _$(TARGET_2ND_ARCH)
else
TARGET_2ND_ARCH_MODULE_SUFFIX := $(HOST_2ND_ARCH_MODULE_SUFFIX)
endif
.KATI_READONLY := TARGET_2ND_ARCH_MODULE_SUFFIX

ifneq ($(filter address,$(SANITIZE_TARGET)),)
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_INTERMEDIATES := $(PRODUCT_OUT)/obj_$(TARGET_2ND_ARCH)_asan
else
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_INTERMEDIATES := $(PRODUCT_OUT)/obj_$(TARGET_2ND_ARCH)
endif
ifeq ($(TARGET_TRANSLATE_2ND_ARCH),true)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_SHARED_LIBRARIES := $(target_out_shared_libraries_base)/lib/$(TARGET_2ND_ARCH)
else
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_SHARED_LIBRARIES := $(target_out_shared_libraries_base)/lib
endif
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_RENDERSCRIPT_BITCODE := $($(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_SHARED_LIBRARIES)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_EXECUTABLES := $(TARGET_OUT_EXECUTABLES)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_APPS := $(TARGET_OUT_APPS)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_APPS_PRIVILEGED := $(TARGET_OUT_APPS_PRIVILEGED)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_TESTCASES := $(TARGET_OUT_TESTCASES)
.KATI_READONLY := \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_INTERMEDIATES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_SHARED_LIBRARIES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_RENDERSCRIPT_BITCODE \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_EXECUTABLES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_APPS \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_APPS_PRIVILEGED \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_TESTCASES

TARGET_OUT_DATA := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_DATA)
TARGET_OUT_DATA_EXECUTABLES := $(TARGET_OUT_EXECUTABLES)
TARGET_OUT_DATA_SHARED_LIBRARIES := $(TARGET_OUT_SHARED_LIBRARIES)
TARGET_OUT_DATA_JAVA_LIBRARIES := $(TARGET_OUT_DATA)/framework
TARGET_OUT_DATA_APPS := $(TARGET_OUT_DATA)/app
TARGET_OUT_DATA_KEYLAYOUT := $(TARGET_OUT_KEYLAYOUT)
TARGET_OUT_DATA_KEYCHARS := $(TARGET_OUT_KEYCHARS)
TARGET_OUT_DATA_ETC := $(TARGET_OUT_ETC)
ifeq ($(TARGET_IS_64_BIT),true)
TARGET_OUT_DATA_NATIVE_TESTS := $(TARGET_OUT_DATA)/nativetest64
TARGET_OUT_DATA_METRIC_TESTS := $(TARGET_OUT_DATA)/benchmarktest64
TARGET_OUT_VENDOR_NATIVE_TESTS := $(TARGET_OUT_DATA)/nativetest64$(TARGET_VENDOR_TEST_SUFFIX)
TARGET_OUT_VENDOR_METRIC_TESTS := $(TARGET_OUT_DATA)/benchmarktest64$(TARGET_VENDOR_TEST_SUFFIX)
else
TARGET_OUT_DATA_NATIVE_TESTS := $(TARGET_OUT_DATA)/nativetest
TARGET_OUT_DATA_METRIC_TESTS := $(TARGET_OUT_DATA)/benchmarktest
TARGET_OUT_VENDOR_NATIVE_TESTS := $(TARGET_OUT_DATA)/nativetest$(TARGET_VENDOR_TEST_SUFFIX)
TARGET_OUT_VENDOR_METRIC_TESTS := $(TARGET_OUT_DATA)/benchmarktest$(TARGET_VENDOR_TEST_SUFFIX)
endif
TARGET_OUT_DATA_FAKE := $(TARGET_OUT_DATA)/fake_packages
.KATI_READONLY := \
  TARGET_OUT_DATA \
  TARGET_OUT_DATA_EXECUTABLES \
  TARGET_OUT_DATA_SHARED_LIBRARIES \
  TARGET_OUT_DATA_JAVA_LIBRARIES \
  TARGET_OUT_DATA_APPS \
  TARGET_OUT_DATA_KEYLAYOUT \
  TARGET_OUT_DATA_KEYCHARS \
  TARGET_OUT_DATA_ETC \
  TARGET_OUT_DATA_NATIVE_TESTS \
  TARGET_OUT_DATA_METRIC_TESTS \
  TARGET_OUT_VENDOR_NATIVE_TESTS \
  TARGET_OUT_VENDOR_METRIC_TESTS \
  TARGET_OUT_DATA_FAKE

$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_EXECUTABLES := $(TARGET_OUT_DATA_EXECUTABLES)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_SHARED_LIBRARIES := $($(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_SHARED_LIBRARIES)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_APPS := $(TARGET_OUT_DATA_APPS)
ifeq ($(TARGET_TRANSLATE_2ND_ARCH),true)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_NATIVE_TESTS := $(TARGET_OUT_DATA)/nativetest/$(TARGET_2ND_ARCH)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_METRIC_TESTS := $(TARGET_OUT_DATA)/benchmarktest/$(TARGET_2ND_ARCH)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_NATIVE_TESTS := $(TARGET_OUT_DATA)/nativetest/$(TARGET_2ND_ARCH)$(TARGET_VENDOR_TEST_SUFFIX)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_METRIC_TESTS := $(TARGET_OUT_DATA)/benchmarktest/$(TARGET_2ND_ARCH)$(TARGET_VENDOR_TEST_SUFFIX)
else
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_NATIVE_TESTS := $(TARGET_OUT_DATA)/nativetest
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_METRIC_TESTS := $(TARGET_OUT_DATA)/benchmarktest
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_NATIVE_TESTS := $(TARGET_OUT_DATA)/nativetest$(TARGET_VENDOR_TEST_SUFFIX)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_METRIC_TESTS := $(TARGET_OUT_DATA)/benchmarktest$(TARGET_VENDOR_TEST_SUFFIX)
endif
.KATI_READONLY := \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_EXECUTABLES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_SHARED_LIBRARIES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_APPS \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_NATIVE_TESTS \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_DATA_METRIC_TESTS \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_NATIVE_TESTS \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_METRIC_TESTS \

TARGET_OUT_CACHE := $(PRODUCT_OUT)/cache
.KATI_READONLY := TARGET_OUT_CACHE

TARGET_OUT_VENDOR := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_VENDOR)
.KATI_READONLY := TARGET_OUT_VENDOR
ifneq ($(filter address,$(SANITIZE_TARGET)),)
target_out_vendor_shared_libraries_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/$(TARGET_COPY_OUT_VENDOR)
ifeq ($(SANITIZE_LITE),true)
# When using SANITIZE_LITE, APKs must not be packaged with sanitized libraries, as they will not
# work with unsanitized app_process. For simplicity, generate APKs into /data/asan/.
target_out_vendor_app_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/$(TARGET_COPY_OUT_VENDOR)
else
target_out_vendor_app_base := $(TARGET_OUT_VENDOR)
endif
else
target_out_vendor_shared_libraries_base := $(TARGET_OUT_VENDOR)
target_out_vendor_app_base := $(TARGET_OUT_VENDOR)
endif

TARGET_OUT_VENDOR_EXECUTABLES := $(TARGET_OUT_VENDOR)/bin
TARGET_OUT_VENDOR_OPTIONAL_EXECUTABLES := $(TARGET_OUT_VENDOR)/xbin
ifeq ($(TARGET_IS_64_BIT),true)
TARGET_OUT_VENDOR_SHARED_LIBRARIES := $(target_out_vendor_shared_libraries_base)/lib64
else
TARGET_OUT_VENDOR_SHARED_LIBRARIES := $(target_out_vendor_shared_libraries_base)/lib
endif
TARGET_OUT_VENDOR_RENDERSCRIPT_BITCODE := $(TARGET_OUT_VENDOR_SHARED_LIBRARIES)
TARGET_OUT_VENDOR_JAVA_LIBRARIES := $(TARGET_OUT_VENDOR)/framework
TARGET_OUT_VENDOR_APPS := $(target_out_vendor_app_base)/app
TARGET_OUT_VENDOR_APPS_PRIVILEGED := $(target_out_vendor_app_base)/priv-app
TARGET_OUT_VENDOR_ETC := $(TARGET_OUT_VENDOR)/etc
.KATI_READONLY := \
  TARGET_OUT_VENDOR_EXECUTABLES \
  TARGET_OUT_VENDOR_OPTIONAL_EXECUTABLES \
  TARGET_OUT_VENDOR_SHARED_LIBRARIES \
  TARGET_OUT_VENDOR_RENDERSCRIPT_BITCODE \
  TARGET_OUT_VENDOR_JAVA_LIBRARIES \
  TARGET_OUT_VENDOR_APPS \
  TARGET_OUT_VENDOR_APPS_PRIVILEGED \
  TARGET_OUT_VENDOR_ETC

$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_EXECUTABLES := $(TARGET_OUT_VENDOR_EXECUTABLES)
ifeq ($(TARGET_TRANSLATE_2ND_ARCH),true)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_SHARED_LIBRARIES := $(target_out_vendor_shared_libraries_base)/lib/$(TARGET_2ND_ARCH)
else
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_SHARED_LIBRARIES := $(target_out_vendor_shared_libraries_base)/lib
endif
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_RENDERSCRIPT_BITCODE := $($(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_SHARED_LIBRARIES)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_APPS := $(TARGET_OUT_VENDOR_APPS)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_APPS_PRIVILEGED := $(TARGET_OUT_VENDOR_APPS_PRIVILEGED)
.KATI_READONLY := \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_EXECUTABLES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_SHARED_LIBRARIES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_RENDERSCRIPT_BITCODE \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_APPS \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_VENDOR_APPS_PRIVILEGED

TARGET_OUT_OEM := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_OEM)
TARGET_OUT_OEM_EXECUTABLES := $(TARGET_OUT_OEM)/bin
ifeq ($(TARGET_IS_64_BIT),true)
TARGET_OUT_OEM_SHARED_LIBRARIES := $(TARGET_OUT_OEM)/lib64
else
TARGET_OUT_OEM_SHARED_LIBRARIES := $(TARGET_OUT_OEM)/lib
endif
# We don't expect Java libraries in the oem.img.
# TARGET_OUT_OEM_JAVA_LIBRARIES:= $(TARGET_OUT_OEM)/framework
TARGET_OUT_OEM_APPS := $(TARGET_OUT_OEM)/app
TARGET_OUT_OEM_ETC := $(TARGET_OUT_OEM)/etc
.KATI_READONLY := \
  TARGET_OUT_OEM \
  TARGET_OUT_OEM_EXECUTABLES \
  TARGET_OUT_OEM_SHARED_LIBRARIES \
  TARGET_OUT_OEM_APPS \
  TARGET_OUT_OEM_ETC

$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_OEM_EXECUTABLES := $(TARGET_OUT_OEM_EXECUTABLES)
ifeq ($(TARGET_TRANSLATE_2ND_ARCH),true)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_OEM_SHARED_LIBRARIES := $(TARGET_OUT_OEM)/lib/$(TARGET_2ND_ARCH)
else
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_OEM_SHARED_LIBRARIES := $(TARGET_OUT_OEM)/lib
endif
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_OEM_APPS := $(TARGET_OUT_OEM_APPS)
.KATI_READONLY := \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_OEM_EXECUTABLES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_OEM_SHARED_LIBRARIES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_OEM_APPS \

TARGET_OUT_ODM := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ODM)
ifneq ($(filter address,$(SANITIZE_TARGET)),)
target_out_odm_shared_libraries_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/$(TARGET_COPY_OUT_OEM)
ifeq ($(SANITIZE_LITE),true)
# When using SANITIZE_LITE, APKs must not be packaged with sanitized libraries, as they will not
# work with unsanitized app_process. For simplicity, generate APKs into /data/asan/.
target_out_odm_app_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/$(TARGET_COPY_OUT_OEM)
else
target_out_odm_app_base := $(TARGET_OUT_ODM)
endif
else
target_out_odm_shared_libraries_base := $(TARGET_OUT_ODM)
target_out_odm_app_base := $(TARGET_OUT_ODM)
endif

TARGET_OUT_ODM_EXECUTABLES := $(TARGET_OUT_ODM)/bin
TARGET_OUT_ODM_OPTIONAL_EXECUTABLES := $(TARGET_OUT_ODM)/xbin
ifeq ($(TARGET_IS_64_BIT),true)
TARGET_OUT_ODM_SHARED_LIBRARIES := $(target_out_odm_shared_libraries_base)/lib64
else
TARGET_OUT_ODM_SHARED_LIBRARIES := $(target_out_odm_shared_libraries_base)/lib
endif
TARGET_OUT_ODM_RENDERSCRIPT_BITCODE := $(TARGET_OUT_ODM_SHARED_LIBRARIES)
TARGET_OUT_ODM_JAVA_LIBRARIES := $(TARGET_OUT_ODM)/framework
TARGET_OUT_ODM_APPS := $(target_out_odm_app_base)/app
TARGET_OUT_ODM_APPS_PRIVILEGED := $(target_out_odm_app_base)/priv-app
TARGET_OUT_ODM_ETC := $(TARGET_OUT_ODM)/etc
.KATI_READONLY := \
  TARGET_OUT_ODM \
  TARGET_OUT_ODM_EXECUTABLES \
  TARGET_OUT_ODM_OPTIONAL_EXECUTABLES \
  TARGET_OUT_ODM_SHARED_LIBRARIES \
  TARGET_OUT_ODM_RENDERSCRIPT_BITCODE \
  TARGET_OUT_ODM_JAVA_LIBRARIES \
  TARGET_OUT_ODM_APPS \
  TARGET_OUT_ODM_APPS_PRIVILEGED \
  TARGET_OUT_ODM_ETC

$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_EXECUTABLES := $(TARGET_OUT_ODM_EXECUTABLES)
ifeq ($(TARGET_TRANSLATE_2ND_ARCH),true)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_SHARED_LIBRARIES := $(target_out_odm_shared_libraries_base)/lib/$(TARGET_2ND_ARCH)
else
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_SHARED_LIBRARIES := $(target_out_odm_shared_libraries_base)/lib
endif
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_RENDERSCRIPT_BITCODE := $($(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_SHARED_LIBRARIES)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_APPS := $(TARGET_OUT_ODM_APPS)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_APPS_PRIVILEGED := $(TARGET_OUT_ODM_APPS_PRIVILEGED)
.KATI_READONLY := \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_EXECUTABLES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_SHARED_LIBRARIES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_RENDERSCRIPT_BITCODE \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_APPS \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_ODM_APPS_PRIVILEGED

TARGET_OUT_PRODUCT := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_PRODUCT)
TARGET_OUT_PRODUCT_EXECUTABLES := $(TARGET_OUT_PRODUCT)/bin
.KATI_READONLY := TARGET_OUT_PRODUCT
ifneq ($(filter address,$(SANITIZE_TARGET)),)
target_out_product_shared_libraries_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/$(TARGET_COPY_OUT_PRODUCT)
ifeq ($(SANITIZE_LITE),true)
# When using SANITIZE_LITE, APKs must not be packaged with sanitized libraries, as they will not
# work with unsanitized app_process. For simplicity, generate APKs into /data/asan/.
target_out_product_app_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/$(TARGET_COPY_OUT_PRODUCT)
else
target_out_product_app_base := $(TARGET_OUT_PRODUCT)
endif
else
target_out_product_shared_libraries_base := $(TARGET_OUT_PRODUCT)
target_out_product_app_base := $(TARGET_OUT_PRODUCT)
endif

ifeq ($(TARGET_IS_64_BIT),true)
TARGET_OUT_PRODUCT_SHARED_LIBRARIES := $(target_out_product_shared_libraries_base)/lib64
else
TARGET_OUT_PRODUCT_SHARED_LIBRARIES := $(target_out_product_shared_libraries_base)/lib
endif
TARGET_OUT_PRODUCT_JAVA_LIBRARIES := $(TARGET_OUT_PRODUCT)/framework
TARGET_OUT_PRODUCT_APPS := $(target_out_product_app_base)/app
TARGET_OUT_PRODUCT_APPS_PRIVILEGED := $(target_out_product_app_base)/priv-app
TARGET_OUT_PRODUCT_ETC := $(TARGET_OUT_PRODUCT)/etc
.KATI_READONLY := \
  TARGET_OUT_PRODUCT_EXECUTABLES \
  TARGET_OUT_PRODUCT_SHARED_LIBRARIES \
  TARGET_OUT_PRODUCT_JAVA_LIBRARIES \
  TARGET_OUT_PRODUCT_APPS \
  TARGET_OUT_PRODUCT_APPS_PRIVILEGED \
  TARGET_OUT_PRODUCT_ETC

$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_EXECUTABLES := $(TARGET_OUT_PRODUCT_EXECUTABLES)
ifeq ($(TARGET_TRANSLATE_2ND_ARCH),true)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_SHARED_LIBRARIES := $(target_out_product_shared_libraries_base)/lib/$(TARGET_2ND_ARCH)
else
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_SHARED_LIBRARIES := $(target_out_product_shared_libraries_base)/lib
endif
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_APPS := $(TARGET_OUT_PRODUCT_APPS)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_APPS_PRIVILEGED := $(TARGET_OUT_PRODUCT_APPS_PRIVILEGED)
.KATI_READONLY := \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_EXECUTABLES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_SHARED_LIBRARIES \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_APPS \
  $(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_APPS_PRIVILEGED

TARGET_OUT_PRODUCT_SERVICES := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_PRODUCT_SERVICES)
ifneq ($(filter address,$(SANITIZE_TARGET)),)
target_out_product_services_shared_libraries_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/$(TARGET_COPY_OUT_PRODUCT_SERVICES)
ifeq ($(SANITIZE_LITE),true)
# When using SANITIZE_LITE, APKs must not be packaged with sanitized libraries, as they will not
# work with unsanitized app_process. For simplicity, generate APKs into /data/asan/.
target_out_product_services_app_base := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ASAN)/$(TARGET_COPY_OUT_PRODUCT_SERVICES)
else
target_out_product_services_app_base := $(TARGET_OUT_PRODUCT_SERVICES)
endif
else
target_out_product_services_shared_libraries_base := $(TARGET_OUT_PRODUCT_SERVICES)
target_out_product_services_app_base := $(TARGET_OUT_PRODUCT_SERVICES)
endif

ifeq ($(TARGET_IS_64_BIT),true)
TARGET_OUT_PRODUCT_SERVICES_SHARED_LIBRARIES := $(target_out_product_services_shared_libraries_base)/lib64
else
TARGET_OUT_PRODUCT_SERVICES_SHARED_LIBRARIES := $(target_out_product_services_shared_libraries_base)/lib
endif
TARGET_OUT_PRODUCT_SERVICES_JAVA_LIBRARIES:= $(TARGET_OUT_PRODUCT_SERVICES)/framework
TARGET_OUT_PRODUCT_SERVICES_APPS := $(target_out_product_services_app_base)/app
TARGET_OUT_PRODUCT_SERVICES_APPS_PRIVILEGED := $(target_out_product_services_app_base)/priv-app
TARGET_OUT_PRODUCT_SERVICES_ETC := $(TARGET_OUT_PRODUCT_SERVICES)/etc

ifeq ($(TARGET_TRANSLATE_2ND_ARCH),true)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_SERVICES_SHARED_LIBRARIES := $(target_out_product_services_shared_libraries_base)/lib/$(TARGET_2ND_ARCH)
else
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_SERVICES_SHARED_LIBRARIES := $(target_out_product_services_shared_libraries_base)/lib
endif
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_SERVICES_APPS := $(TARGET_OUT_PRODUCT_SERVICES_APPS)
$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_OUT_PRODUCT_SERVICES_APPS_PRIVILEGED := $(TARGET_OUT_PRODUCT_SERVICES_APPS_PRIVILEGED)

TARGET_OUT_BREAKPAD := $(PRODUCT_OUT)/breakpad
.KATI_READONLY := TARGET_OUT_BREAKPAD

TARGET_OUT_UNSTRIPPED := $(PRODUCT_OUT)/symbols
TARGET_OUT_EXECUTABLES_UNSTRIPPED := $(TARGET_OUT_UNSTRIPPED)/system/bin
TARGET_OUT_SHARED_LIBRARIES_UNSTRIPPED := $(TARGET_OUT_UNSTRIPPED)/system/lib
TARGET_OUT_VENDOR_SHARED_LIBRARIES_UNSTRIPPED := $(TARGET_OUT_UNSTRIPPED)/$(TARGET_COPY_OUT_VENDOR)/lib
TARGET_ROOT_OUT_UNSTRIPPED := $(TARGET_OUT_UNSTRIPPED)
TARGET_ROOT_OUT_SBIN_UNSTRIPPED := $(TARGET_OUT_UNSTRIPPED)/sbin
TARGET_ROOT_OUT_BIN_UNSTRIPPED := $(TARGET_OUT_UNSTRIPPED)/bin
TARGET_OUT_COVERAGE := $(PRODUCT_OUT)/coverage
.KATI_READONLY := \
  TARGET_OUT_UNSTRIPPED \
  TARGET_OUT_EXECUTABLES_UNSTRIPPED \
  TARGET_OUT_SHARED_LIBRARIES_UNSTRIPPED \
  TARGET_OUT_VENDOR_SHARED_LIBRARIES_UNSTRIPPED \
  TARGET_ROOT_OUT_UNSTRIPPED \
  TARGET_ROOT_OUT_SBIN_UNSTRIPPED \
  TARGET_ROOT_OUT_BIN_UNSTRIPPED \
  TARGET_OUT_COVERAGE

TARGET_RAMDISK_OUT := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_RAMDISK)
TARGET_RAMDISK_OUT_UNSTRIPPED := $(TARGET_OUT_UNSTRIPPED)

TARGET_ROOT_OUT := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_ROOT)
TARGET_ROOT_OUT_BIN := $(TARGET_ROOT_OUT)/bin
TARGET_ROOT_OUT_SBIN := $(TARGET_ROOT_OUT)/sbin
TARGET_ROOT_OUT_ETC := $(TARGET_ROOT_OUT)/etc
TARGET_ROOT_OUT_USR := $(TARGET_ROOT_OUT)/usr
.KATI_READONLY := \
  TARGET_ROOT_OUT \
  TARGET_ROOT_OUT_BIN \
  TARGET_ROOT_OUT_SBIN \
  TARGET_ROOT_OUT_ETC \
  TARGET_ROOT_OUT_USR

TARGET_RECOVERY_OUT := $(PRODUCT_OUT)/$(TARGET_COPY_OUT_RECOVERY)
TARGET_RECOVERY_ROOT_OUT := $(TARGET_RECOVERY_OUT)/root
.KATI_READONLY := \
  TARGET_RECOVERY_OUT \
  TARGET_RECOVERY_ROOT_OUT

TARGET_SYSLOADER_OUT := $(PRODUCT_OUT)/sysloader
TARGET_SYSLOADER_ROOT_OUT := $(TARGET_SYSLOADER_OUT)/root
TARGET_SYSLOADER_SYSTEM_OUT := $(TARGET_SYSLOADER_OUT)/root/system
.KATI_READONLY := \
  TARGET_SYSLOADER_OUT \
  TARGET_SYSLOADER_ROOT_OUT \
  TARGET_SYSLOADER_SYSTEM_OUT

TARGET_INSTALLER_OUT := $(PRODUCT_OUT)/installer
TARGET_INSTALLER_DATA_OUT := $(TARGET_INSTALLER_OUT)/data
TARGET_INSTALLER_ROOT_OUT := $(TARGET_INSTALLER_OUT)/root
TARGET_INSTALLER_SYSTEM_OUT := $(TARGET_INSTALLER_OUT)/root/system
.KATI_READONLY := \
  TARGET_INSTALLER_OUT \
  TARGET_INSTALLER_DATA_OUT \
  TARGET_INSTALLER_ROOT_OUT \
  TARGET_INSTALLER_SYSTEM_OUT

COMMON_MODULE_CLASSES := TARGET-NOTICE_FILES HOST-NOTICE_FILES HOST-JAVA_LIBRARIES
PER_ARCH_MODULE_CLASSES := SHARED_LIBRARIES STATIC_LIBRARIES EXECUTABLES GYP RENDERSCRIPT_BITCODE NATIVE_TESTS HEADER_LIBRARIES
.KATI_READONLY := COMMON_MODULE_CLASSES PER_ARCH_MODULE_CLASSES

ifeq ($(CALLED_FROM_SETUP),true)
PRINT_BUILD_CONFIG ?= true
endif
