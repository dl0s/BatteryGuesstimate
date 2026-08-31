import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
const LEGACY_LAST_POSITION_V1 = "circular buffer last position";
(:background)
const LEGACY_PREFIX_V1 = "circular buffer ";
(:background)
const LEGACY_LAST_POSITION_V2 = "cBlP";

(:background)
class LegacyStorageMigration {
    public function initialize() {
    }

    public static function hasLegacyData() as Boolean {
        return Storage.getValue(LEGACY_LAST_POSITION_V2) != null
            || Storage.getValue(LEGACY_LAST_POSITION_V1) != null;
    }

    private function legacyValueAt(position) {
        var value = Storage.getValue(position);
        if (value == null) {
            value = Storage.getValue(LEGACY_PREFIX_V1 + position);
        }
        return value;
    }

    private function deleteLegacyAt(position as Number) as Void {
        try {
            Storage.deleteValue(position);
            Storage.deleteValue(LEGACY_PREFIX_V1 + position);
        } catch (e) {
            System.println("BatterySync error " + $.ERROR_LEGACY_MIGRATION
                + " cleanup position " + position + " " + e.getErrorMessage());
        }
    }

    public function migrate() as Boolean {
        var lastPosition = Storage.getValue(LEGACY_LAST_POSITION_V2);
        if (lastPosition == null) {
            lastPosition = Storage.getValue(LEGACY_LAST_POSITION_V1);
        }
        if (!(lastPosition instanceof Number)) {
            new BatteryMetaStore().ensure();
            if (lastPosition != null) {
                new BatteryMetaStore().recordError($.ERROR_LEGACY_MIGRATION);
            }
            return lastPosition == null;
        }

        var dropped = 0;
        // Establish V1 metadata before BatteryStore is constructed so its
        // migration guard cannot recurse.
        var metaStore = new BatteryMetaStore();
        metaStore.ensure();
        var store = new BatteryStore();
        var now = Time.now().value();
        var migrated = 0;
        var flags = $.FLAG_LEGACY_SAMPLE
            | $.FLAG_TIMESTAMP_RECONSTRUCTED
            | $.FLAG_SOLAR_UNKNOWN
            | $.FLAG_BATTERY_DAYS_UNKNOWN
            | $.FLAG_CHARGING_UNKNOWN
            | $.FLAG_FIRMWARE_UNKNOWN;

        // Start immediately after the old write head and walk once around the
        // ring. Offset itself reconstructs age, so no 1345-element RAM array is
        // needed during migration.
        for (var offset = 1; offset <= $.MAX_WATCH_SAMPLES; offset += 1) {
            var position = (lastPosition + offset) % $.MAX_WATCH_SAMPLES;
            var value = legacyValueAt(position);
            if (value == null) {
                continue;
            }
            if (!(value instanceof Number) && !(value instanceof Float)) {
                dropped += 1;
                deleteLegacyAt(position);
                continue;
            }
            var timestamp = now
                - (($.MAX_WATCH_SAMPLES - offset) * $.SAMPLE_INTERVAL_SECONDS);
            var sample = new BatterySampleV1(
                0,
                timestamp,
                ((value as Numeric) * 100.0).toNumber(),
                $.BATTERY_DAYS_UNKNOWN,
                false,
                $.SOLAR_INTENSITY_UNKNOWN,
                $.FIRMWARE_VERSION_UNKNOWN,
                $.FIRMWARE_VERSION_UNKNOWN,
                $.ACTIVITY_TIMER_UNKNOWN,
                $.ACTIVITY_SPORT_UNKNOWN,
                0,
                $.TEMPERATURE_UNKNOWN,
                0,
                flags | $.FLAG_TEMP_UNKNOWN
            );
            if (!store.appendSample(sample)) {
                dropped += 1;
                deleteLegacyAt(position);
                // Continue the read-only portion of the ring walk so every
                // legacy value that cannot be retained is explicitly counted
                // and removed instead of becoming invisible orphaned data.
                for (var remaining = offset + 1;
                        remaining <= $.MAX_WATCH_SAMPLES;
                        remaining += 1) {
                    var remainingPosition = (lastPosition + remaining)
                        % $.MAX_WATCH_SAMPLES;
                    if (legacyValueAt(remainingPosition) != null) {
                        dropped += 1;
                        deleteLegacyAt(remainingPosition);
                    }
                }
                break;
            }
            migrated += 1;
            deleteLegacyAt(position);
        }

        // One historical build could leave a value at the off-by-one index.
        // It cannot be ordered reliably relative to the circular head, so it
        // is surfaced as an explicit discard rather than silently ignored.
        if (legacyValueAt($.MAX_WATCH_SAMPLES) != null) {
            dropped += 1;
            deleteLegacyAt($.MAX_WATCH_SAMPLES);
        }

        var meta = store.getMeta();
        meta.put("legacyDroppedSamples", dropped);
        if (dropped > 0) {
            meta.put("lastErrorCode", $.ERROR_LEGACY_MIGRATION);
            meta.put("lastErrorUtc", Time.now().value());
        }
        store.saveMeta(meta);
        try {
            Storage.deleteValue(LEGACY_LAST_POSITION_V1);
            Storage.deleteValue(LEGACY_LAST_POSITION_V2);
        } catch (e) {
            System.println("BatterySync error " + $.ERROR_LEGACY_MIGRATION
                + " cleanup head " + e.getErrorMessage());
        }
        System.println("BatterySync legacy migration: " + migrated
            + " migrated, " + dropped + " discarded");
        return dropped == 0;
    }
}

// Compatibility entry point retained for older tests/build integrations.
(:background)
public function databaseMigration() as Boolean {
    if (!LegacyStorageMigration.hasLegacyData()) {
        new BatteryMetaStore().ensure();
        return true;
    }
    return new LegacyStorageMigration().migrate();
}
