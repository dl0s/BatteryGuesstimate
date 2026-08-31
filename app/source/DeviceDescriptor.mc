import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;

// Static installation/device data. It is separate from the 15-minute sample
// row and is rewritten only when app/firmware/device metadata changes.
(:background)
class DeviceDescriptorV1 {
    public var installId;
    public var partNumber;
    public var monkeyMajor;
    public var monkeyMinor;
    public var monkeyMicro;
    public var appVersion;
    public var protocolVersion;
    public var activityTrackingOn;
    public var firmwareMajor;
    public var firmwareMinor;

    public function initialize(
        id, part, monkey, app, protocol, tracking, firmware
    ) {
        installId = id;
        partNumber = part;
        monkeyMajor = monkey[0];
        monkeyMinor = monkey[1];
        monkeyMicro = monkey[2];
        appVersion = app;
        protocolVersion = protocol;
        activityTrackingOn = tracking;
        firmwareMajor = firmware[0];
        firmwareMinor = firmware[1];
    }

    public function toArray() as Array {
        return [
            $.BATTERY_DEVICE_DESCRIPTOR_VERSION,
            installId,
            partNumber,
            monkeyMajor,
            monkeyMinor,
            monkeyMicro,
            appVersion,
            protocolVersion,
            activityTrackingOn ? 1 : 0,
            firmwareMajor,
            firmwareMinor
        ];
    }
}

(:background)
class DeviceDescriptorStore {
    public function initialize() {
    }

    private function same(left, right) as Boolean {
        if (!(left instanceof Array) || !(right instanceof Array)
            || left.size() != right.size()) {
            return false;
        }
        for (var i = 0; i < left.size(); i += 1) {
            if (left[i] instanceof String && right[i] instanceof String) {
                if (!(left[i] as String).equals(right[i] as String)) {
                    return false;
                }
            } else if (left[i] != right[i]) {
                return false;
            }
        }
        return true;
    }

    public function load() {
        return Storage.getValue($.BATTERY_DEVICE_DESCRIPTOR_KEY);
    }

    public function maybeUpdate(settings, installId as String) as Boolean {
        var monkey = [0, 0, 0];
        var firmware = [$.FIRMWARE_VERSION_UNKNOWN, $.FIRMWARE_VERSION_UNKNOWN];
        var part = "unknown";
        var tracking = false;
        if (settings has :monkeyVersion) {
            var monkeyValue = settings.monkeyVersion;
            if (monkeyValue instanceof Array && monkeyValue.size() >= 3) {
                monkey = monkeyValue;
            }
        }
        if (settings has :firmwareVersion) {
            var firmwareValue = settings.firmwareVersion;
            if (firmwareValue instanceof Array && firmwareValue.size() >= 2) {
                firmware = firmwareValue;
            }
        }
        if (settings has :partNumber) {
            part = settings.partNumber;
        }
        if (settings has :activityTrackingOn) {
            tracking = settings.activityTrackingOn;
        }
        var next = new DeviceDescriptorV1(
            installId,
            part,
            monkey,
            $.BATTERY_APP_VERSION,
            $.BATTERY_PROTOCOL_VERSION,
            tracking,
            firmware
        ).toArray();
        var current = load();
        if (same(current, next)) {
            return false;
        }
        try {
            Storage.setValue($.BATTERY_DEVICE_DESCRIPTOR_KEY, next);
            return true;
        } catch (e) {
            System.println("Battery descriptor write failed");
            return false;
        }
    }
}
