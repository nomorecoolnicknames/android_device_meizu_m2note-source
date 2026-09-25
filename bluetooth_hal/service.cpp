/*
 * Verbatim copy of hardware/interfaces/bluetooth/1.0/default/service.cpp
 * (Apache-2.0, AOSP), built 32-bit under a device-local name — see Android.bp.
 */

#define LOG_TAG "android.hardware.bluetooth@1.0-service.m5c"

#include <android/hardware/bluetooth/1.0/IBluetoothHci.h>
#include <hidl/LegacySupport.h>

// Generated HIDL files
static const size_t kMaxThreads = 5;

using android::hardware::bluetooth::V1_0::IBluetoothHci;
using android::hardware::defaultPassthroughServiceImplementation;

int main() {
    return defaultPassthroughServiceImplementation<IBluetoothHci>(kMaxThreads);
}
