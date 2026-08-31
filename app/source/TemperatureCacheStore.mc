import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;

// Compact cache layout:
// [version, temperatureDeciC, temperatureTimestampUtc, lastRefreshAttemptUtc]
(:background)
class TemperatureCacheStore {
    public function initialize() {
    }

    public function empty() as Array {
        return [
            $.BATTERY_TEMPERATURE_CACHE_VERSION,
            $.TEMPERATURE_UNKNOWN,
            0,
            0
        ];
    }

    private function isValid(value) as Boolean {
        return value instanceof Array
            && value.size() == 4
            && value[0] == $.BATTERY_TEMPERATURE_CACHE_VERSION
            && value[1] instanceof Number
            && value[2] instanceof Number
            && value[3] instanceof Number;
    }

    public function load() as Array {
        var value = Storage.getValue($.BATTERY_TEMPERATURE_CACHE_KEY);
        return isValid(value) ? value : empty();
    }

    public function save(value as Array) as Boolean {
        if (!isValid(value)) {
            return false;
        }
        try {
            Storage.setValue($.BATTERY_TEMPERATURE_CACHE_KEY, value);
            return true;
        } catch (e) {
            System.println("Battery temperature cache write failed");
            return false;
        }
    }
}
