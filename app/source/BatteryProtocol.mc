import Toybox.Lang;

// BATTERY SYNC PROTOCOL V1 -- FREEZE CANDIDATE.
// Promote to FROZEN only after the simulator matrix and 72-hour acceptance
// gate in docs/GARMIN_SYNC_ACCEPTANCE.md have passed.
(:background)
const BATTERY_PROTOCOL_VERSION = 1;
(:background)
const TYPE_SAMPLE_BATCH = 1;
(:background)
const TYPE_ACK = 2;
(:background)
const TYPE_SYNC_REQUEST = 3;
(:background)
const TYPE_STATUS = 4;
(:background)
const TYPE_DATA_LOSS = 5;
(:background)
const TYPE_DEVICE_DESCRIPTOR = 6;
(:background)
const TYPE_DESCRIPTOR_REQUEST = 7;

(:background)
class BatteryProtocol {
    public function initialize() {
    }

    // [1, version, installId, firstSeq, lastSeq, compactSampleRows]
    public function buildSampleBatch(installId, samples) {
        if (!(samples instanceof Array) || samples.size() == 0) {
            return null;
        }
        var rows = [];
        var firstSeq = samples[0].seq;
        var expectedSeq = firstSeq;
        for (var i = 0; i < samples.size(); i += 1) {
            if (samples[i].seq != expectedSeq) {
                return null;
            }
            rows.add(samples[i].toPayloadArray());
            expectedSeq += 1;
        }
        return [
            $.TYPE_SAMPLE_BATCH,
            $.BATTERY_PROTOCOL_VERSION,
            installId,
            firstSeq,
            samples[samples.size() - 1].seq,
            rows
        ];
    }

    // [2, version, installId, highestContinuouslyCommittedSeq]
    public function decodeAck(payload) as Dictionary {
        return decodeControl(payload, $.TYPE_ACK);
    }

    // [3, version, installId, highestContinuouslyCommittedSeq]
    public function decodeSyncRequest(payload) as Dictionary {
        return decodeControl(payload, $.TYPE_SYNC_REQUEST);
    }

    // [7, version] anonymous first discovery.
    // [7, version, installId] identified descriptor request.
    public function decodeDescriptorRequest(payload) as Dictionary {
        if (!(payload instanceof Array)
            || (payload.size() != 2 && payload.size() != 3)
            || payload[0] != $.TYPE_DESCRIPTOR_REQUEST) {
            return {"ok" => false, "error" => $.ERROR_INVALID_ACK};
        }
        if (payload[1] != $.BATTERY_PROTOCOL_VERSION) {
            return {"ok" => false, "error" => $.ERROR_PROTOCOL_MISMATCH};
        }
        if (payload.size() == 3) {
            if (!(payload[2] instanceof String)) {
                return {"ok" => false, "error" => $.ERROR_INSTALL_ID_MISMATCH};
            }
            return {"ok" => true, "installId" => payload[2]};
        }
        return {"ok" => true, "installId" => null};
    }

    // [6, version, installId, descriptorArray]
    public function buildDeviceDescriptor(installId, descriptor) as Array {
        return [
            $.TYPE_DEVICE_DESCRIPTOR,
            $.BATTERY_PROTOCOL_VERSION,
            installId,
            descriptor
        ];
    }

    private function decodeControl(payload, expectedType) as Dictionary {
        if (!(payload instanceof Array) || payload.size() != 4
            || payload[0] != expectedType || !(payload[3] instanceof Number)) {
            return {"ok" => false, "error" => $.ERROR_INVALID_ACK};
        }
        if (payload[1] != $.BATTERY_PROTOCOL_VERSION) {
            return {"ok" => false, "error" => $.ERROR_PROTOCOL_MISMATCH};
        }
        if (!(payload[2] instanceof String)) {
            return {"ok" => false, "error" => $.ERROR_INSTALL_ID_MISMATCH};
        }
        return {
            "ok" => true,
            "installId" => payload[2],
            "ackedSeq" => payload[3]
        };
    }

    // [5, version, installId, lostFrom, lostTo, oldestAvailable, newest]
    public function buildDataLoss(installId, meta) as Array {
        return [
            $.TYPE_DATA_LOSS,
            $.BATTERY_PROTOCOL_VERSION,
            installId,
            meta.get("lastDataLossFromSeq"),
            meta.get("lastDataLossToSeq"),
            meta.get("oldestSeq"),
            meta.get("newestSeq")
        ];
    }

    // [4, version, installId, acked, oldest, newest, pending, state, error]
    public function buildStatus(installId, meta, pending) as Array {
        return [
            $.TYPE_STATUS,
            $.BATTERY_PROTOCOL_VERSION,
            installId,
            meta.get("ackedSeq"),
            meta.get("oldestSeq"),
            meta.get("newestSeq"),
            pending,
            meta.get("syncState"),
            meta.get("lastErrorCode")
        ];
    }
}
