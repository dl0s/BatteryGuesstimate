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

    private function validateAndApply(decoded) as Boolean {
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
        var applied = _store.applyAck(decoded.get("ackedSeq"));
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
            return validateAndApply(_protocol.decodeAck(payload));
        }
        if (payload[0] == $.TYPE_SYNC_REQUEST) {
            return validateAndApply(_protocol.decodeSyncRequest(payload));
        }
        if (payload[0] == $.TYPE_DESCRIPTOR_REQUEST) {
            var decoded = _protocol.decodeDescriptorRequest(payload);
            if (!decoded.get("ok")) {
                _store.recordError(decoded.get("error"));
                return false;
            }
            if (!(decoded.get("installId") as String).equals(_store.getInstallId())) {
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
