import Toybox.WatchUi;
import Toybox.Lang;

class BatteryGuesstimateCarusellDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        WatchUi.BehaviorDelegate.initialize();
    }

    public function onSelect() as Boolean {
        var view = new BatteryGuesstimateView();
        WatchUi.pushView(
            view,
            new BatteryGuesstimateDelegate(view),
            WatchUi.SLIDE_RIGHT
        );
        return true;
    }
}
