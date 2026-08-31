import Toybox.Time;
import Toybox.Lang;
import Toybox.System;

(:background)
class BatterySyncManager {
    private var _store;
    private var _protocol;
    private var _transport;

    public function initialize() {
        _store = new BatteryStore();
        _protocol = new BatteryProtocol();
        _transport = new BatteryTransport();
    }

    // Test seam. Production callers use the default Communications transport.
    public function setTransport(transport) as Void {
        _transport = transport;
    }

    public function stateName(state) as String {
        switch (state) {
            case $.SYNC_STATE_PENDING:
                return "PENDING";
            case $.SYNC_STATE_SENDING:
                return "SENDING";
            case $.SYNC_STATE_WAITING_ACK:
                return "WAITING_ACK";
            case $.SYNC_STATE_ERROR:
                return "ERROR";
            default:
                return "IDLE";
        }
    }

    public function getStatus() as Dictionary {
        var meta = _store.getMeta();
        return {
            "pending" => _store.getPendingCount(),
            "lastSuccessUtc" => meta.get("lastSyncSuccessUtc"),
            "state" => stateName(meta.get("syncState")),
            "lastErrorCode" => meta.get("lastErrorCode")
        };
    }

    private function phoneConnected() as Boolean {
        var settings = System.getDeviceSettings();
        if (settings has :phoneConnected) {
            return settings.phoneConnected;
        }
        // Required fēnix 7 targets expose phoneConnected. Preserve legacy
        // compatibility if this class is compiled for an older device.
        return true;
    }

    public function shouldSyncAt(
        immediate,
        batteryPct100,
        charging,
        isPhoneConnected,
        nowUtc
    ) as Boolean {
        var meta = _store.ensurePendingContinuity();
        var hasPendingLoss = meta.get("lastDataLossToSeq") != null
            && meta.get("ackedSeq") < meta.get("lastDataLossToSeq");
        var pending = _store.getPendingCount();
        if (pending <= 0 && !hasPendingLoss) {
            return false;
        }
        if (immediate) {
            return true;
        }
        if (!isPhoneConnected) {
            return false;
        }

        var lastAttempt = meta.get("lastSyncAttemptUtc") as Number;
        var retryBackoff = batteryPct100 < $.SYNC_LOW_BATTERY_PCT100
            ? $.SYNC_LOW_BATTERY_RETRY_BACKOFF_SECONDS
            : $.SYNC_RETRY_BACKOFF_SECONDS;
        if (lastAttempt > 0 && nowUtc >= lastAttempt
            && nowUtc - lastAttempt < retryBackoff) {
            return false;
        }

        // A loss marker is part of the continuity contract even when no
        // sample row remains available. It still follows background retry
        // backoff so a disconnected/failed phone is not contacted every 15m.
        if (hasPendingLoss) {
            return true;
        }

        var lastSuccess = meta.get("lastSyncSuccessUtc");
        var sinceSuccess = lastSuccess == 0 ? 0 : nowUtc - lastSuccess;

        if (charging) {
            return pending >= 1;
        }
        if (batteryPct100 < $.SYNC_LOW_BATTERY_PCT100) {
            return pending >= $.SYNC_LOW_BATTERY_MIN_PENDING
                || (lastSuccess > 0 && sinceSuccess >= $.SYNC_LOW_BATTERY_MAX_SILENCE_SECONDS);
        }
        return pending >= $.SYNC_MIN_PENDING
            || (lastSuccess > 0 && sinceSuccess >= $.SYNC_MAX_SILENCE_SECONDS);
    }

    public function shouldSync(immediate, batteryPct100, charging) as Boolean {
        return shouldSyncAt(
            immediate,
            batteryPct100,
            charging,
            phoneConnected(),
            Time.now().value()
        );
    }

    // Deterministic policy entry used by tests and by sync(). A false result
    // exits before BatteryTransport is touched.
    public function syncAt(
        immediate,
        batteryPct100,
        charging,
        isPhoneConnected,
        nowUtc
    ) as Boolean {
        if (!shouldSyncAt(
                immediate,
                batteryPct100,
                charging,
                isPhoneConnected,
                nowUtc
            )) {
            return false;
        }
        var meta = _store.ensurePendingContinuity();
        var payload = null;
        var fromSeq = null;
        var toSeq = null;

        if (meta.get("lastDataLossToSeq") != null
            && meta.get("ackedSeq") < meta.get("lastDataLossToSeq")) {
            payload = _protocol.buildDataLoss(_store.getInstallId(), meta);
            fromSeq = meta.get("lastDataLossFromSeq");
            toSeq = meta.get("lastDataLossToSeq");
        } else {
            var samples = _store.getPendingBatch($.SYNC_BATCH_SIZE);
            if (samples.size() == 0) {
                return false;
            }
            payload = _protocol.buildSampleBatch(_store.getInstallId(), samples);
            if (payload == null) {
                _store.recordError($.ERROR_CORRUPT_PAGE);
                return false;
            }
            fromSeq = samples[0].seq;
            toSeq = samples[samples.size() - 1].seq;
        }

        meta.put("lastSyncAttemptUtc", nowUtc);
        meta.put("inFlightFromSeq", fromSeq);
        meta.put("inFlightToSeq", toSeq);
        meta.put("syncState", $.SYNC_STATE_SENDING);
        meta.put("syncAttemptCount", (meta.get("syncAttemptCount") as Number) + 1);
        if (meta.get("syncRequestedPending") == true) {
            meta.put("syncRequestedPending", false);
        }
        if (!_store.saveMeta(meta)) {
            return false;
        }

        if (!_transport.send(payload, self, true)) {
            onTransportError(true);
            return false;
        }
        return true;
    }

    // Starts at most one bounded transport operation per invocation.
    public function sync(immediate, batteryPct100, charging) as Boolean {
        return syncAt(
            immediate,
            batteryPct100,
            charging,
            phoneConnected(),
            Time.now().value()
        );
    }

    public function sendStatus() as Boolean {
        var meta = _store.getMeta();
        var payload = _protocol.buildStatus(
            _store.getInstallId(), meta, _store.getPendingCount()
        );
        return _transport.send(payload, self, false);
    }

    public function sendDeviceDescriptor() as Boolean {
        var descriptorStore = new DeviceDescriptorStore();
        var descriptor = descriptorStore.load();
        if (descriptor == null) {
            descriptorStore.maybeUpdate(
                System.getDeviceSettings(), _store.getInstallId()
            );
            descriptor = descriptorStore.load();
        }
        if (!(descriptor instanceof Array)) {
            return false;
        }
        return _transport.send(
            _protocol.buildDeviceDescriptor(_store.getInstallId(), descriptor),
            self,
            false
        );
    }

    public function onTransportComplete(requiresDurableAck) as Void {
        if (!requiresDurableAck) {
            return;
        }
        var meta = _store.getMeta();
        meta.put("syncState", $.SYNC_STATE_WAITING_ACK);
        _store.saveMeta(meta);
        new BatteryGlanceSummaryStore().updateSyncFromMeta(meta);
    }

    public function onTransportError(requiresDurableAck) as Void {
        if (requiresDurableAck) {
            var meta = _store.getMeta();
            meta.put("syncFailureCount", (meta.get("syncFailureCount") as Number) + 1);
            meta.put("lastErrorCode", $.ERROR_TRANSMIT_FAILURE);
            meta.put("lastErrorUtc", Time.now().value());
            meta.put("syncState", $.SYNC_STATE_ERROR);
            _store.saveMeta(meta);
            new BatteryGlanceSummaryStore().updateSyncFromMeta(meta);
            System.println("BatterySync error " + $.ERROR_TRANSMIT_FAILURE);
        }
    }
}
