import Toybox.Communications;
import Toybox.System;
import Toybox.Lang;

(:background)
class BatteryTransportListener extends Communications.ConnectionListener {
    private var _manager;
    private var _requiresDurableAck;

    public function initialize(manager, requiresDurableAck) {
        Communications.ConnectionListener.initialize();
        _manager = manager;
        _requiresDurableAck = requiresDurableAck;
    }

    public function onComplete() as Void {
        // Queue delivery is not a durable ACK. The batch remains in Storage.
        _manager.onTransportComplete(_requiresDurableAck);
    }

    public function onError() as Void {
        _manager.onTransportError(_requiresDurableAck);
    }
}

(:background)
class BatteryTransport {
    public function initialize() {
    }

    public function send(payload, manager, requiresDurableAck) as Boolean {
        try {
            Communications.transmit(
                payload,
                null,
                new BatteryTransportListener(manager, requiresDurableAck)
            );
            return true;
        } catch (e) {
            System.println("BatterySync error " + $.ERROR_TRANSMIT_FAILURE
                + " transmit " + e.getErrorMessage());
            return false;
        }
    }
}
