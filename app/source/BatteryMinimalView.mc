import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class BatteryMinimalView extends WatchUi.View {
    public function initialize() {
        WatchUi.View.initialize();
    }

    private function valueOrUnknown(value, unknown) as String {
        return value == unknown ? "--" : value.toString();
    }

    private function daysText(summary as BatteryGlanceSummaryV1) as String {
        if (summary.batteryInDays100 == $.BATTERY_DAYS_UNKNOWN) {
            return "--";
        }
        return (summary.batteryInDays100 / 100.0).format("%.1f") + " d";
    }

    private function temperatureText(summary as BatteryGlanceSummaryV1) as String {
        if ((summary.flags & $.FLAG_TEMP_UNKNOWN) != 0) {
            return "--";
        }
        var suffix = (summary.flags & $.FLAG_TEMP_STALE) != 0 ? "C old" : "C proxy";
        return (summary.temperatureDeciC / 10.0).format("%.1f") + suffix;
    }

    private function syncText(state as Number) as String {
        switch (state) {
            case $.SYNC_STATE_IDLE:
                return "OK";
            case $.SYNC_STATE_PENDING:
                return "PENDING";
            case $.SYNC_STATE_SENDING:
                return "SENDING";
            case $.SYNC_STATE_WAITING_ACK:
                return "WAIT ACK";
            default:
                return "ERROR";
        }
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var summary = new BatteryGlanceSummaryStore().load();
        if (summary == null) {
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_TINY,
                "WAITING FOR SAMPLE",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }
        var rows = [
            "BATTERY  " + (summary.latestBatteryPct100 / 100.0).format("%.1f") + "%",
            "GARMIN   " + daysText(summary),
            "CHARGE   " + (summary.charging ? "YES" : "NO"),
            "SOLAR    " + valueOrUnknown(summary.solarIntensity, $.SOLAR_INTENSITY_UNKNOWN),
            "TEMP     " + temperatureText(summary),
            "SYNC     " + syncText(summary.syncState),
            "PENDING  " + summary.pendingCount,
            "SAMPLE   " + summary.lastSampleUtc,
            "SYNCED   " + summary.lastSyncSuccessUtc
        ];
        var lineHeight = dc.getHeight() / rows.size();
        for (var i = 0; i < rows.size(); i += 1) {
            dc.drawText(
                dc.getWidth() / 2,
                i * lineHeight,
                Graphics.FONT_XTINY,
                rows[i],
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }
}

class BatteryMinimalDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        WatchUi.BehaviorDelegate.initialize();
    }
}
