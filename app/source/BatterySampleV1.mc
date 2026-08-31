import Toybox.Lang;

(:background)
class BatterySampleV1 {
    public var schemaVersion;
    public var seq;
    public var timestampUtc;
    public var batteryPct100;
    public var batteryInDays100;
    public var charging;
    public var solarIntensity;
    public var firmwareMajor;
    public var firmwareMinor;
    public var activityTimerState;
    public var activitySport;
    public var connectionFlags;
    public var temperatureDeciC;
    public var temperatureTimestampUtc;
    public var flags;

    public function initialize(
        sequence,
        timestamp,
        percent100,
        days100,
        isCharging,
        solar,
        firmwareMajorVersion,
        firmwareMinorVersion,
        timerState,
        sport,
        connections,
        temperature,
        temperatureTimestamp,
        sampleFlags
    ) {
        schemaVersion = $.BATTERY_SAMPLE_SCHEMA_VERSION;
        seq = sequence;
        timestampUtc = timestamp;
        batteryPct100 = percent100;
        batteryInDays100 = days100;
        charging = isCharging;
        solarIntensity = solar;
        firmwareMajor = firmwareMajorVersion;
        firmwareMinor = firmwareMinorVersion;
        activityTimerState = timerState;
        activitySport = sport;
        connectionFlags = connections;
        temperatureDeciC = temperature;
        temperatureTimestampUtc = temperatureTimestamp;
        flags = sampleFlags;
    }

    // Local storage keeps seq explicitly. This is intentionally different
    // from the compact wire row where seq is firstSeq + array index.
    public function toStorageArray() as Array {
        return [
            schemaVersion,
            seq,
            timestampUtc,
            batteryPct100,
            batteryInDays100,
            charging ? 1 : 0,
            solarIntensity,
            firmwareMajor,
            firmwareMinor,
            activityTimerState,
            activitySport,
            connectionFlags,
            temperatureDeciC,
            temperatureTimestampUtc,
            flags
        ];
    }

    public function toPayloadArray() as Array {
        return [
            timestampUtc,
            batteryPct100,
            batteryInDays100,
            charging ? 1 : 0,
            solarIntensity,
            firmwareMajor,
            firmwareMinor,
            activityTimerState,
            activitySport,
            connectionFlags,
            temperatureDeciC,
            temperatureTimestampUtc,
            flags
        ];
    }

    public static function fromStorageArray(row) {
        if (!(row instanceof Array)
            || (row.size() != 8 && row.size() != 10 && row.size() != 15)) {
            return null;
        }
        if (row[0] != $.BATTERY_SAMPLE_SCHEMA_VERSION) {
            return null;
        }
        if (!(row[1] instanceof Number) || !(row[2] instanceof Number)
            || !(row[3] instanceof Number) || !(row[4] instanceof Number)
            || !(row[5] instanceof Number) || !(row[6] instanceof Number)
            || !(row[7] instanceof Number)
            || (row[5] != 0 && row[5] != 1)) {
            return null;
        }
        // Rows written by the pre-firmware V1 freeze candidate had eight
        // fields. Keep them readable and mark firmware explicitly unknown.
        if (row.size() == 8) {
            return new BatterySampleV1(
                row[1], row[2], row[3], row[4], row[5] == 1, row[6],
                $.FIRMWARE_VERSION_UNKNOWN,
                $.FIRMWARE_VERSION_UNKNOWN,
                $.ACTIVITY_TIMER_UNKNOWN,
                $.ACTIVITY_SPORT_UNKNOWN,
                0,
                $.TEMPERATURE_UNKNOWN,
                0,
                row[7] | $.FLAG_FIRMWARE_UNKNOWN
                    | $.FLAG_TEMP_UNKNOWN
            );
        }
        if (row.size() == 10) {
            if (!(row[8] instanceof Number) || !(row[9] instanceof Number)) {
                return null;
            }
            return new BatterySampleV1(
                row[1], row[2], row[3], row[4], row[5] == 1, row[6],
                row[7], row[8],
                $.ACTIVITY_TIMER_UNKNOWN,
                $.ACTIVITY_SPORT_UNKNOWN,
                0,
                $.TEMPERATURE_UNKNOWN,
                0,
                row[9] | $.FLAG_TEMP_UNKNOWN
            );
        }
        for (var i = 8; i < 15; i += 1) {
            if (!(row[i] instanceof Number)) {
                return null;
            }
        }
        if (row[10] < 0 || row[11] < 0) {
            return null;
        }
        return new BatterySampleV1(
            row[1], row[2], row[3], row[4], row[5] == 1, row[6],
            row[7], row[8], row[9], row[10], row[11], row[12], row[13], row[14]
        );
    }
}
