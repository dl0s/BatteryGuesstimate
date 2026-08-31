import Toybox.Lang;
import Toybox.System;

(:background)
class BatteryAckHandler {
    private var _store;
    private var _protocol;
    private var _descriptorRequest as Boolean = false;

    public function initialize() {
        _store = new BatteryStore();
        _protocol = new BatteryProtocol();
    }

    private function validateInstallId(decoded) as Boolean {
        if (!decoded.get("ok")) {
            _store.recordError(decoded.get("error"));
            return false;
        }
        if (!(decoded.get("installId") as String).equals(_store.getInstallId())) {
            System.println("BatterySync install mismatch expected="
                + _store.getInstallId() + " received=" + decoded.get("installId"));
            _store.recordError($.ERROR_INSTALL_ID_MISMATCH);
            return false;
        }
        return true;
    }

    private function validateAndApply(decoded, syncRequest as Boolean) as Boolean {
        if (!validateInstallId(decoded)) {
            return false;
        }
        var applied = syncRequest
            ? _store.applySyncRequest(decoded.get("ackedSeq"))
            : _store.applyAck(decoded.get("ackedSeq"));
        if (applied) {
            new BatteryGlanceSummaryStore().updateSyncFromMeta(_store.getMeta());
        }
        return applied;
    }

    public function handle(payload) as Boolean {
        _descriptorRequest = false;
        if (!(payload instanceof Array) || payload.size() == 0) {
            _store.recordError($.ERROR_INVALID_ACK);
            return false;
        }
        if (payload[0] == $.TYPE_ACK) {
            return validateAndApply(_protocol.decodeAck(payload), false);
        }
        if (payload[0] == $.TYPE_SYNC_REQUEST) {
            return validateAndApply(_protocol.decodeSyncRequest(payload), true);
        }
        if (payload[0] == $.TYPE_DESCRIPTOR_REQUEST) {
            var decoded = _protocol.decodeDescriptorRequest(payload);
            if (!decoded.get("ok")) {
                _store.recordError(decoded.get("error"));
                return false;
            }
            var requestInstallId = decoded.get("installId");
            if (requestInstallId != null
                && !(requestInstallId as String).equals(_store.getInstallId())) {
                System.println("BatterySync install mismatch expected="
                    + _store.getInstallId() + " received=" + requestInstallId);
                _store.recordError($.ERROR_INSTALL_ID_MISMATCH);
                return false;
            }
            _descriptorRequest = true;
            return new BatterySyncManager().sendDeviceDescriptor();
        }
        _store.recordError($.ERROR_INVALID_ACK);
        return false;
    }

    public function wasDescriptorRequest() as Boolean {
        return _descriptorRequest;
    }
}
