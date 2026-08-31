import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;

// Pages are aligned to global sequence ranges and mapped onto bounded slots.
// Each page value stays far below the conservative 8 KB Storage value limit.
(:background)
class BatteryPageStore {
    private var _cachedPageId = null;
    private var _cachedPage = null;

    public function initialize() {
    }

    public function pageIdForSeq(seq) {
        return ((seq - 1) / $.BATTERY_PAGE_SIZE).toNumber();
    }

    public function slotForPageId(pageId) {
        return pageId % $.BATTERY_PAGE_SLOT_COUNT;
    }

    private function keyForSlot(slot) as String {
        return $.BATTERY_PAGE_KEY_PREFIX + slot;
    }

    private function validatePage(page) as Boolean {
        if (!(page instanceof Array) || page.size() != 3) {
            return false;
        }
        if (page[0] != $.BATTERY_STORAGE_SCHEMA_VERSION
            || !(page[1] instanceof Number)
            || !(page[2] instanceof Array)
            || page[2].size() > $.BATTERY_PAGE_SIZE) {
            return false;
        }
        return true;
    }

    private function readSlot(slot) {
        var page = Storage.getValue(keyForSlot(slot));
        if (!validatePage(page)) {
            if (page != null) {
                System.println("BatterySync error " + $.ERROR_CORRUPT_PAGE + " slot " + slot);
            }
            return null;
        }
        return page;
    }

    public function loadPage(pageId) {
        if (_cachedPageId == pageId && _cachedPage != null) {
            return _cachedPage;
        }
        var page = readSlot(slotForPageId(pageId));
        if (page == null || page[1] != pageId) {
            return null;
        }
        _cachedPageId = pageId;
        _cachedPage = page;
        return page;
    }

    public function saveSample(sample as BatterySampleV1) as Boolean {
        var pageId = pageIdForSeq(sample.seq);
        var offset = (sample.seq - 1) % $.BATTERY_PAGE_SIZE;
        var page = loadPage(pageId);
        if (page == null) {
            page = [$.BATTERY_STORAGE_SCHEMA_VERSION, pageId, []];
        }
        var rows = page[2];
        if (offset > rows.size()) {
            System.println("BatterySync error " + $.ERROR_CORRUPT_PAGE + " non-contiguous page");
            return false;
        }
        if (offset == rows.size()) {
            rows.add(sample.toStorageArray());
        } else {
            rows[offset] = sample.toStorageArray();
        }

        try {
            Storage.setValue(keyForSlot(slotForPageId(pageId)), page);
        } catch (e) {
            System.println("BatterySync error " + $.ERROR_STORAGE_WRITE + " page write " + e.getErrorMessage());
            return false;
        }
        _cachedPageId = pageId;
        _cachedPage = page;
        return true;
    }

    public function getSample(seq) {
        if (seq < 1) {
            return null;
        }
        var pageId = pageIdForSeq(seq);
        var page = loadPage(pageId);
        if (page == null) {
            return null;
        }
        var offset = (seq - 1) % $.BATTERY_PAGE_SIZE;
        var rows = page[2];
        if (offset >= rows.size()) {
            return null;
        }
        var sample = BatterySampleV1.fromStorageArray(rows[offset]);
        if (sample == null || sample.seq != seq) {
            System.println("BatterySync error " + $.ERROR_CORRUPT_PAGE + " seq " + seq);
            return null;
        }
        return sample;
    }

    public function addFlag(seq, flag) as Boolean {
        var sample = getSample(seq);
        if (sample == null) {
            return false;
        }
        sample.flags = sample.flags | flag;
        return saveSample(sample);
    }

    // Used only for conservative metadata recovery. Stale page generations are
    // harmless; the largest contiguous bounded generation wins in BatteryStore.
    public function scanBounds() as Array {
        var minimum = null;
        var maximum = null;
        for (var slot = 0; slot < $.BATTERY_PAGE_SLOT_COUNT; slot += 1) {
            var page = readSlot(slot);
            if (page == null) {
                continue;
            }
            var rows = page[2];
            for (var i = 0; i < rows.size(); i += 1) {
                var sample = BatterySampleV1.fromStorageArray(rows[i]);
                if (sample == null) {
                    continue;
                }
                if (minimum == null || sample.seq < minimum) {
                    minimum = sample.seq;
                }
                if (maximum == null || sample.seq > maximum) {
                    maximum = sample.seq;
                }
            }
        }
        if (maximum != null && minimum != null && (maximum - minimum + 1) > $.MAX_WATCH_SAMPLES) {
            minimum = maximum - $.MAX_WATCH_SAMPLES + 1;
        }
        return [minimum, maximum];
    }
}
