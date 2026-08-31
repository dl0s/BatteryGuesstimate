import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;

// Reads exactly one newest SensorHistory entry, and only when the hourly
// refresh interval is due. The source is device temperature, used solely as an
// environmental proxy; the original sensor timestamp is always preserved.
(:background)
class TemperatureSampler {
    private var _cacheStore as TemperatureCacheStore;

    public function initialize() {
        _cacheStore = new TemperatureCacheStore();
    }

    public function shouldRefreshAt(cache as Array, nowUtc as Number) as Boolean {
        var lastAttempt = cache[3] as Number;
        return lastAttempt <= 0 || nowUtc < lastAttempt
            || nowUtc - lastAttempt >= $.TEMPERATURE_REFRESH_SECONDS;
    }

    public function qualityFlagsAt(
        temperatureDeciC as Number,
        temperatureTimestampUtc as Number,
        nowUtc as Number
    ) as Number {
        if (temperatureDeciC == $.TEMPERATURE_UNKNOWN
            || temperatureTimestampUtc <= 0) {
            return $.FLAG_TEMP_UNKNOWN;
        }
        var flags = $.FLAG_TEMP_DEVICE_PROXY;
        if (nowUtc < temperatureTimestampUtc
            || nowUtc - temperatureTimestampUtc > $.TEMPERATURE_STALE_SECONDS) {
            flags = flags | $.FLAG_TEMP_STALE;
        }
        return flags;
    }

    // Pure cache path used by tests and by the non-refresh callbacks.
    // [temperatureDeciC, temperatureTimestampUtc, flags, readDurationMs, refreshed]
    public function fromCacheAt(cache as Array, nowUtc as Number) as Array {
        return [
            cache[1],
            cache[2],
            qualityFlagsAt(cache[1], cache[2], nowUtc),
            0,
            false
        ];
    }

    public function sampleAt(nowUtc as Number) as Array {
        var cache = _cacheStore.load();
        if (!shouldRefreshAt(cache, nowUtc)) {
            return fromCacheAt(cache, nowUtc);
        }

        var started = System.getTimer();
        cache[3] = nowUtc;
        try {
            if ((Toybox has :SensorHistory)
                && (Toybox.SensorHistory has :getTemperatureHistory)) {
                var iterator = SensorHistory.getTemperatureHistory({
                    :period => 1,
                    :order => SensorHistory.ORDER_NEWEST_FIRST
                });
                if (iterator != null) {
                    var newest = iterator.next();
                    if (newest != null && newest.data != null
                        && newest.when != null) {
                        cache[1] = Math.round(newest.data * 10.0).toNumber();
                        cache[2] = newest.when.value();
                    }
                }
            }
        } catch (e) {
            // Preserve the last real value and timestamp. A failed refresh must
            // never fabricate a new observation time or 0 C value.
            System.println("Battery temperature refresh unavailable");
        }
        _cacheStore.save(cache);
        var duration = System.getTimer() - started;
        var result = fromCacheAt(cache, nowUtc);
        result[3] = duration;
        result[4] = true;
        return result;
    }
}
