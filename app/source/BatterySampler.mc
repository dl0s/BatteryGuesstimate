import Toybox.Math;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
class BatterySampler {
    public function initialize() {
    }

    // The caller owns API acquisition so the 15-minute callback can enforce
    // exactly one SystemStats and one DeviceSettings read.
    public function sampleFrom(
        stats,
        settings,
        context as Array,
        temperature as Array,
        flags,
        nowUtc
    ) as BatterySampleV1 {
        var sampleFlags = flags;
        var days100 = $.BATTERY_DAYS_UNKNOWN;
        var solar = $.SOLAR_INTENSITY_UNKNOWN;
        var firmwareMajor = $.FIRMWARE_VERSION_UNKNOWN;
        var firmwareMinor = $.FIRMWARE_VERSION_UNKNOWN;

        if (stats has :batteryInDays) {
            if (stats.batteryInDays != null) {
                days100 = Math.round(stats.batteryInDays * 100.0).toNumber();
            } else {
                sampleFlags = sampleFlags | $.FLAG_BATTERY_DAYS_UNKNOWN;
            }
        } else {
            sampleFlags = sampleFlags | $.FLAG_BATTERY_DAYS_UNKNOWN;
        }

        if (stats has :solarIntensity) {
            if (stats.solarIntensity != null) {
                // Preserve Garmin's raw Number semantics, including negatives.
                solar = stats.solarIntensity;
            } else {
                sampleFlags = sampleFlags | $.FLAG_SOLAR_UNKNOWN;
            }
        } else {
            sampleFlags = sampleFlags | $.FLAG_SOLAR_UNKNOWN;
        }

        if (settings has :firmwareVersion) {
            var firmware = settings.firmwareVersion;
            if (firmware instanceof Array && firmware.size() >= 2
                && firmware[0] instanceof Number
                && firmware[1] instanceof Number) {
                firmwareMajor = firmware[0];
                firmwareMinor = firmware[1];
            } else {
                sampleFlags = sampleFlags | $.FLAG_FIRMWARE_UNKNOWN;
            }
        } else {
            sampleFlags = sampleFlags | $.FLAG_FIRMWARE_UNKNOWN;
        }

        return new BatterySampleV1(
            0,
            nowUtc,
            Math.round(stats.battery * 100.0).toNumber(),
            days100,
            stats.charging,
            solar,
            firmwareMajor,
            firmwareMinor,
            context[0],
            context[1],
            context[2],
            temperature[0],
            temperature[1],
            sampleFlags | temperature[2]
        );
    }

    // Foreground/manual compatibility entry. The production temporal callback
    // uses sampleFrom() and does not duplicate these API calls.
    public function sample(flags) as BatterySampleV1 {
        var nowUtc = Time.now().value();
        var stats = System.getSystemStats();
        var settings = System.getDeviceSettings();
        var context = new BatteryContextSampler().sample(settings);
        var temperature = new TemperatureSampler().sampleAt(nowUtc);
        return sampleFrom(
            stats, settings, context, temperature, flags, nowUtc
        );
    }
}
