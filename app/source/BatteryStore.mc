import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;

// Stable facade for sampling, sync, and the legacy UI. UI code never sees a
// page key, slot, or metadata layout.
(:background)
class BatteryStore {
    private var _metaStore as BatteryMetaStore;
    private var _pageStore as BatteryPageStore;

    public function initialize() {
        _metaStore = new BatteryMetaStore();
        _pageStore = new BatteryPageStore();
        ensureReady();
    }

    private function ensureReady() as Void {
        if (Storage.getValue($.BATTERY_STORAGE_SCHEMA_KEY) == null
            && LegacyStorageMigration.hasLegacyData()) {
            new LegacyStorageMigration().migrate();
        } else {
            _metaStore.ensure();
        }
    }

    public function getInstallId() as String {
        return _metaStore.ensureInstallId();
    }

    public function getMeta() as Dictionary {
        return _metaStore.load();
    }

    private function number(meta as Dictionary, key as String) as Number {
        return meta.get(key) as Number;
    }

    private function updatePagePointers(meta as Dictionary) as Void {
        if (number(meta, "newestSeq") < number(meta, "oldestSeq")) {
            meta.put("headPage", -1);
            meta.put("tailPage", -1);
        } else {
            meta.put("headPage", _pageStore.pageIdForSeq(number(meta, "oldestSeq")));
            meta.put("tailPage", _pageStore.pageIdForSeq(number(meta, "newestSeq")));
        }
    }

    private function mergeDataLoss(
        meta as Dictionary,
        fromSeq as Number,
        toSeq as Number
    ) as Void {
        var oldFrom = meta.get("lastDataLossFromSeq");
        var oldTo = meta.get("lastDataLossToSeq");
        if (oldFrom == null || fromSeq < (oldFrom as Number)) {
            meta.put("lastDataLossFromSeq", fromSeq);
        }
        if (oldTo == null || toSeq > (oldTo as Number)) {
            meta.put("lastDataLossToSeq", toSeq);
        }
        meta.put("lastErrorCode", $.ERROR_STORAGE_FULL);
        meta.put("lastErrorUtc", Time.now().value());
        meta.put("syncState", $.SYNC_STATE_ERROR);
    }

    public function appendSample(sample as BatterySampleV1) as Boolean {
        var meta = _metaStore.load();
        var seq = number(meta, "nextSeq");
        var count = number(meta, "newestSeq") >= number(meta, "oldestSeq")
            ? number(meta, "newestSeq") - number(meta, "oldestSeq") + 1
            : 0;

        if (count >= $.MAX_WATCH_SAMPLES) {
            var evictedSeq = number(meta, "oldestSeq");
            var evictedUnacked = evictedSeq > number(meta, "ackedSeq");
            meta.put("oldestSeq", evictedSeq + 1);
            if (evictedUnacked) {
                // Persist the marker before any page slot can overwrite data.
                mergeDataLoss(meta, evictedSeq, evictedSeq);
            }
            updatePagePointers(meta);
            if (!_metaStore.save(meta)) {
                return false;
            }
            if (evictedUnacked
                && !_pageStore.addFlag(number(meta, "oldestSeq"), $.FLAG_DATA_GAP_BEFORE)) {
                _metaStore.recordError($.ERROR_CORRUPT_PAGE);
            }
        }

        sample.seq = seq;
        if (!_pageStore.saveSample(sample)) {
            _metaStore.recordError($.ERROR_STORAGE_WRITE);
            return false;
        }

        meta = _metaStore.load();
        if (number(meta, "newestSeq") == 0) {
            meta.put("oldestSeq", seq);
        }
        meta.put("newestSeq", seq);
        meta.put("nextSeq", seq + 1);
        if (number(meta, "ackedSeq") < seq
            && number(meta, "syncState") == $.SYNC_STATE_IDLE) {
            meta.put("syncState", $.SYNC_STATE_PENDING);
        }
        updatePagePointers(meta);
        return _metaStore.save(meta);
    }

    public function getSample(seq as Number) {
        var meta = _metaStore.load();
        if (seq < number(meta, "oldestSeq") || seq > number(meta, "newestSeq")) {
            return null;
        }
        var sample = _pageStore.getSample(seq);
        if (sample == null) {
            _metaStore.recordError($.ERROR_CORRUPT_PAGE);
        }
        return sample;
    }

    // Compatibility adapter: offset 0 is newest, offset 1344 is ~14 days ago.
    public function getBatteryAt(offset as Number) {
        var meta = _metaStore.load();
        var sample = getSample(number(meta, "newestSeq") - offset);
        if (sample == null) {
            return null;
        }
        return sample.batteryPct100 / 100.0;
    }

    public function getBatteryHistory(count as Number) as Array {
        var result = [];
        for (var offset = count - 1; offset >= 0; offset -= 1) {
            result.add(getBatteryAt(offset));
        }
        return result;
    }

    public function getPendingCount() {
        var meta = _metaStore.load();
        var start = number(meta, "ackedSeq") + 1;
        if (start < number(meta, "oldestSeq")) {
            start = number(meta, "oldestSeq");
        }
        if (start > number(meta, "newestSeq")) {
            return 0;
        }
        return number(meta, "newestSeq") - start + 1;
    }

    public function ensurePendingContinuity() as Dictionary {
        var meta = _metaStore.load();
        var lossTo = meta.get("lastDataLossToSeq");
        if (lossTo != null && number(meta, "ackedSeq") < (lossTo as Number)) {
            return meta;
        }
        if (lossTo != null && number(meta, "ackedSeq") >= (lossTo as Number)) {
            meta.put("lastDataLossFromSeq", null);
            meta.put("lastDataLossToSeq", null);
        }

        var start = number(meta, "ackedSeq") + 1;
        if (start < number(meta, "oldestSeq")) {
            mergeDataLoss(meta, start, number(meta, "oldestSeq") - 1);
            _metaStore.save(meta);
            return meta;
        }
        if (start <= number(meta, "newestSeq") && _pageStore.getSample(start) == null) {
            var nextAvailable = start + 1;
            while (nextAvailable <= number(meta, "newestSeq")
                && _pageStore.getSample(nextAvailable) == null) {
                nextAvailable += 1;
            }
            mergeDataLoss(meta, start, nextAvailable - 1);
            meta.put("oldestSeq", nextAvailable);
            updatePagePointers(meta);
            _metaStore.save(meta);
            if (nextAvailable <= number(meta, "newestSeq")) {
                _pageStore.addFlag(nextAvailable, $.FLAG_DATA_GAP_BEFORE);
            }
        }
        return meta;
    }

    public function getPendingBatch(limit as Number) as Array {
        var meta = ensurePendingContinuity();
        if (meta.get("lastDataLossToSeq") != null
            && number(meta, "ackedSeq")
                < (meta.get("lastDataLossToSeq") as Number)) {
            return [];
        }
        var start = number(meta, "ackedSeq") + 1;
        if (start < number(meta, "oldestSeq")) {
            start = number(meta, "oldestSeq");
        }
        var samples = [];
        for (var seq = start; seq <= number(meta, "newestSeq")
            && samples.size() < limit; seq += 1) {
            var sample = _pageStore.getSample(seq);
            if (sample == null) {
                break;
            }
            samples.add(sample);
        }
        return samples;
    }

    public function applyAck(ackedSeq as Number) as Boolean {
        var meta = _metaStore.load();
        if (ackedSeq < number(meta, "ackedSeq")) {
            _metaStore.recordError($.ERROR_STALE_ACK);
            return false;
        }
        if (ackedSeq > number(meta, "newestSeq")) {
            _metaStore.recordError($.ERROR_FUTURE_ACK);
            return false;
        }
        if (ackedSeq == number(meta, "ackedSeq")) {
            return true;
        }
        meta.put("ackedSeq", ackedSeq);
        meta.put("lastSyncSuccessUtc", Time.now().value());
        if (meta.get("inFlightFromSeq") != null
            && ackedSeq >= (meta.get("inFlightFromSeq") as Number)) {
            meta.put("inFlightFromSeq", null);
            meta.put("inFlightToSeq", null);
        }
        if (meta.get("lastDataLossToSeq") != null
            && ackedSeq >= (meta.get("lastDataLossToSeq") as Number)) {
            meta.put("lastDataLossFromSeq", null);
            meta.put("lastDataLossToSeq", null);
        }
        meta.put("lastErrorCode", $.ERROR_NONE);
        meta.put("syncState", ackedSeq < number(meta, "newestSeq")
            ? $.SYNC_STATE_PENDING : $.SYNC_STATE_IDLE);
        return _metaStore.save(meta);
    }

    // A SYNC_REQUEST carries the phone's durable accounted cursor. When it
    // accounts for every current record, arm the next-sample latch so a fresh
    // battery sample is pushed immediately instead of waiting for the normal
    // 8-sample threshold.
    public function applySyncRequest(accountedSeq as Number) as Boolean {
        var applied = applyAck(accountedSeq);
        if (applied && getPendingCount() == 0) {
            return _metaStore.setSyncRequestedPending(true);
        }
        return applied;
    }

    public function isSyncRequestedPending() as Boolean {
        return _metaStore.isSyncRequestedPending();
    }

    public function consumeSyncRequestedPending() as Boolean {
        return _metaStore.setSyncRequestedPending(false);
    }

    public function saveMeta(meta as Dictionary) as Boolean {
        return _metaStore.save(meta);
    }

    public function recordError(code as Number) as Void {
        _metaStore.recordError(code);
    }
}
