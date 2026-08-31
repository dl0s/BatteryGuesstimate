import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;

// Compact summary layout:
// [version, latestBatteryPct100, batteryInDays100, chargingFlag,
//  solarIntensity, temperatureDeciC, pendingCount, lastSampleUtc,
//  lastSyncSuccessUtc, syncState, flags]
(:background :glance)
class BatteryGlanceSummaryV1 {
    public var latestBatteryPct100;
    public var batteryInDays100;
    public var charging;
    public var solarIntensity;
    public var temperatureDeciC;
    public var pendingCount;
    public var lastSampleUtc;
    public var lastSyncSuccessUtc;
    public var syncState;
    public var flags;

    public function initialize(
        battery, days, isCharging, solar, temperature, pending,
        sampleUtc, syncUtc, state, sampleFlags
    ) {
        latestBatteryPct100 = battery;
        batteryInDays100 = days;
        charging = isCharging;
        solarIntensity = solar;
        temperatureDeciC = temperature;
        pendingCount = pending;
        lastSampleUtc = sampleUtc;
        lastSyncSuccessUtc = syncUtc;
        syncState = state;
        flags = sampleFlags;
    }

    public function toArray() as Array {
        return [
            $.BATTERY_GLANCE_SUMMARY_VERSION,
            latestBatteryPct100,
            batteryInDays100,
            charging ? 1 : 0,
            solarIntensity,
            temperatureDeciC,
            pendingCount,
            lastSampleUtc,
            lastSyncSuccessUtc,
            syncState,
            flags
        ];
    }

    public static function fromArray(value) {
        if (!(value instanceof Array) || value.size() != 11
            || value[0] != $.BATTERY_GLANCE_SUMMARY_VERSION) {
            return null;
        }
        for (var i = 1; i < value.size(); i += 1) {
            if (!(value[i] instanceof Number)) {
                return null;
            }
        }
        if (value[3] != 0 && value[3] != 1) {
            return null;
        }
        return new BatteryGlanceSummaryV1(
            value[1], value[2], value[3] == 1, value[4], value[5],
            value[6], value[7], value[8], value[9], value[10]
        );
    }
}

(:background :glance)
class BatteryGlanceSummaryStore {
    public function initialize() {
    }

    // Exactly one Storage read. Glance calls only this method.
    public function load() {
        return BatteryGlanceSummaryV1.fromArray(
            Storage.getValue($.BATTERY_GLANCE_SUMMARY_KEY)
        );
    }

    (:background)
    private function pendingFromMeta(meta as Dictionary) as Number {
        var start = (meta.get("ackedSeq") as Number) + 1;
        var oldest = meta.get("oldestSeq") as Number;
        var newest = meta.get("newestSeq") as Number;
        if (start < oldest) {
            start = oldest;
        }
        return start <= newest ? newest - start + 1 : 0;
    }

    (:background)
    public function save(summary as BatteryGlanceSummaryV1) as Boolean {
        try {
            Storage.setValue($.BATTERY_GLANCE_SUMMARY_KEY, summary.toArray());
            return true;
        } catch (e) {
            System.println("Battery glance summary write failed");
            return false;
        }
    }

    (:background)
    public function updateFrom(sample as BatterySampleV1, meta as Dictionary) as Boolean {
        var pending = pendingFromMeta(meta);
        return save(new BatteryGlanceSummaryV1(
            sample.batteryPct100,
            sample.batteryInDays100,
            sample.charging,
            sample.solarIntensity,
            sample.temperatureDeciC,
            pending,
            sample.timestampUtc,
            meta.get("lastSyncSuccessUtc"),
            meta.get("syncState"),
            sample.flags
        ));
    }

    (:background)
    public function updateSyncFromMeta(meta as Dictionary) as Boolean {
        var summary = load();
        if (summary == null) {
            return false;
        }
        summary.pendingCount = pendingFromMeta(meta);
        summary.lastSyncSuccessUtc = meta.get("lastSyncSuccessUtc");
        summary.syncState = meta.get("syncState");
        return save(summary);
    }
}
