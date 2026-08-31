import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

(:background)
class BatteryMetaStore {
    public function initialize() {
    }

    private function isInstallId(value) as Boolean {
        return value instanceof String && value.length() == 32;
    }

    public function getInstallId() {
        var value = Storage.getValue($.BATTERY_INSTALL_ID_KEY);
        if (isInstallId(value)) {
            return value;
        }
        return null;
    }

    public function ensureInstallId() as String {
        var existing = getInstallId();
        if (existing != null) {
            return existing;
        }
        var storedMeta = Storage.getValue($.BATTERY_META_KEY);
        if (storedMeta instanceof Dictionary
            && isInstallId(storedMeta.get("installId"))) {
            var recovered = storedMeta.get("installId") as String;
            try {
                Storage.setValue($.BATTERY_INSTALL_ID_KEY, recovered);
            } catch (e) {
                System.println("BatterySync error " + $.ERROR_STORAGE_WRITE
                    + " install identity recovery " + e.getErrorMessage());
            }
            return recovered;
        }
        // Install identity is not a security credential. Epoch plus three PRNG
        // words gives a compact, installation-scoped 32-character identifier.
        var generated = Time.now().value().format("%08x")
            + (Math.rand() & 0x7fffffff).format("%08x")
            + (Math.rand() & 0x7fffffff).format("%08x")
            + (Math.rand() & 0x7fffffff).format("%08x");
        try {
            Storage.setValue($.BATTERY_INSTALL_ID_KEY, generated);
        } catch (e) {
            System.println("BatterySync error " + $.ERROR_STORAGE_WRITE
                + " install identity write " + e.getErrorMessage());
        }
        return generated;
    }

    private function defaultMeta(installId as String) as Dictionary {
        return {
            "storageSchemaVersion" => $.BATTERY_STORAGE_SCHEMA_VERSION,
            "installId" => installId,
            "nextSeq" => 1,
            "ackedSeq" => 0,
            "oldestSeq" => 1,
            "newestSeq" => 0,
            "headPage" => -1,
            "tailPage" => -1,
            "lastSyncAttemptUtc" => 0,
            "lastSyncSuccessUtc" => 0,
            "lastDataLossFromSeq" => null,
            "lastDataLossToSeq" => null,
            "inFlightFromSeq" => null,
            "inFlightToSeq" => null,
            "syncState" => $.SYNC_STATE_IDLE,
            "lastErrorCode" => $.ERROR_NONE,
            "lastErrorUtc" => 0,
            "legacyDroppedSamples" => 0,
            "lastBackgroundDurationMs" => 0,
            "maxBackgroundDurationMs" => 0,
            "temperatureReadDurationMs" => 0,
            "syncAttemptCount" => 0,
            "syncFailureCount" => 0,
            "syncRequestedPending" => false
        };
    }

    private function ensureMetrics(meta as Dictionary) as Boolean {
        var changed = false;
        var keys = [
            "lastBackgroundDurationMs",
            "maxBackgroundDurationMs",
            "temperatureReadDurationMs",
            "syncAttemptCount",
            "syncFailureCount"
        ];
        for (var i = 0; i < keys.size(); i += 1) {
            var key = keys[i] as String;
            if (!(meta.get(key) instanceof Number)) {
                meta.put(key, 0);
                changed = true;
            }
        }
        if (meta.get("syncRequestedPending") == null) {
            meta.put("syncRequestedPending", false);
            changed = true;
        }
        return changed;
    }

    private function isValid(meta) as Boolean {
        if (!(meta instanceof Dictionary)) {
            return false;
        }
        var dict = meta as Dictionary;
        if (dict.get("storageSchemaVersion") != $.BATTERY_STORAGE_SCHEMA_VERSION) {
            return false;
        }
        var required = ["installId", "nextSeq", "ackedSeq", "oldestSeq", "newestSeq"];
        for (var i = 0; i < required.size(); i += 1) {
            if (dict.get(required[i] as String) == null) {
                return false;
            }
        }
        if (!isInstallId(dict.get("installId"))) {
            return false;
        }
        if (!(dict.get("nextSeq") instanceof Number)
            || !(dict.get("ackedSeq") instanceof Number)
            || !(dict.get("oldestSeq") instanceof Number)
            || !(dict.get("newestSeq") instanceof Number)) {
            return false;
        }
        var nextSeq = dict.get("nextSeq") as Number;
        var ackedSeq = dict.get("ackedSeq") as Number;
        var oldestSeq = dict.get("oldestSeq") as Number;
        var newestSeq = dict.get("newestSeq") as Number;
        if (nextSeq < 1 || ackedSeq < 0 || oldestSeq < 1 || newestSeq < 0) {
            return false;
        }
        if (newestSeq == 0) {
            return nextSeq == 1 && ackedSeq == 0;
        }
        if (oldestSeq > newestSeq + 1 || nextSeq != newestSeq + 1
            || ackedSeq > newestSeq) {
            return false;
        }
        return true;
    }

    public function ensure() as Dictionary {
        var installId = ensureInstallId();
        var stored = Storage.getValue($.BATTERY_META_KEY);
        if (isValid(stored)) {
            var validMeta = stored as Dictionary;
            // The dedicated identity key is authoritative if metadata was copied
            // or partially damaged.
            if (!(validMeta.get("installId") as String).equals(installId)) {
                validMeta.put("installId", installId);
                save(validMeta);
            }
            if (ensureMetrics(validMeta)) {
                save(validMeta);
            }
            return validMeta;
        }

        var meta = defaultMeta(installId);
        var pageStore = new BatteryPageStore();
        var bounds = pageStore.scanBounds();
        if (stored != null || bounds[1] != null) {
            System.println("BatterySync error " + $.ERROR_CORRUPT_METADATA + ": rebuilding bounds");
            if (bounds[1] != null) {
                meta.put("oldestSeq", bounds[0]);
                meta.put("newestSeq", bounds[1]);
                meta.put("nextSeq", bounds[1] + 1);
                meta.put("headPage", pageStore.pageIdForSeq(bounds[0]));
                meta.put("tailPage", pageStore.pageIdForSeq(bounds[1]));
                meta.put("syncState", $.SYNC_STATE_PENDING);
            }
            meta.put("lastErrorCode", $.ERROR_CORRUPT_METADATA);
            meta.put("lastErrorUtc", Time.now().value());
        }
        save(meta);
        return meta;
    }

    public function load() as Dictionary {
        return ensure();
    }

    public function save(meta as Dictionary) as Boolean {
        try {
            Storage.setValue($.BATTERY_INSTALL_ID_KEY, meta.get("installId"));
            Storage.setValue($.BATTERY_META_KEY, meta);
            Storage.setValue($.BATTERY_STORAGE_SCHEMA_KEY, $.BATTERY_STORAGE_SCHEMA_VERSION);
            return true;
        } catch (e) {
            System.println("BatterySync error " + $.ERROR_STORAGE_WRITE + " metadata write " + e.getErrorMessage());
            return false;
        }
    }

    public function recordError(code as Number) as Void {
        var meta = ensure();
        meta.put("lastErrorCode", code);
        meta.put("lastErrorUtc", Time.now().value());
        meta.put("syncState", $.SYNC_STATE_ERROR);
        save(meta);
        System.println("BatterySync error " + code);
    }

    public function isSyncRequestedPending() as Boolean {
        var meta = ensure();
        var value = meta.get("syncRequestedPending");
        return value instanceof Boolean && value;
    }

    public function setSyncRequestedPending(value as Boolean) as Boolean {
        var meta = ensure();
        meta.put("syncRequestedPending", value);
        return save(meta);
    }
}
