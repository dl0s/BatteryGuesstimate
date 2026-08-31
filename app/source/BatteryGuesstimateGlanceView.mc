import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Glance is a strict one-read projection. It never constructs BatteryStore,
// scans pages/history, migrates, recovers, computes trends, or starts sync.
(:glance)
class BatteryGuesstimateGlanceView extends WatchUi.GlanceView {
    public function initialize() {
        WatchUi.GlanceView.initialize();
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
        var suffix = (summary.flags & $.FLAG_TEMP_STALE) != 0 ? " C*" : " C";
        return (summary.temperatureDeciC / 10.0).format("%.1f") + suffix;
    }

    private function syncText(summary as BatteryGlanceSummaryV1) as String {
        if (summary.syncState == $.SYNC_STATE_ERROR) {
            return "!";
        }
        if (summary.pendingCount > 0) {
            return "... " + summary.pendingCount;
        }
        return "OK";
    }

    public function onUpdate(dc) {
        // This is the sole Glance storage read.
        var summary = new BatteryGlanceSummaryStore().load();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (summary == null) {
            dc.drawText(0, 0, Graphics.FONT_XTINY, "BATTERY --",
                Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }
        var rows = [
            "BATTERY  " + (summary.latestBatteryPct100 / 100.0).format("%.0f") + "%",
            "EST.     " + daysText(summary),
            "TEMP.    " + temperatureText(summary),
            "SYNC     " + syncText(summary)
        ];
        var lineHeight = dc.getHeight() / rows.size();
        for (var i = 0; i < rows.size(); i += 1) {
            dc.drawText(0, i * lineHeight, Graphics.FONT_XTINY,
                rows[i], Graphics.TEXT_JUSTIFY_LEFT);
        }
    }
}
