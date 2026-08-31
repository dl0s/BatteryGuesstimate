import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;

// Captures only compact battery-relevant activity and connection context.
// It never persists Activity.Info, ProfileInfo, DeviceSettings, or strings.
(:background)
class BatteryContextSampler {
    public function initialize() {
    }

    public function encodeTimerState(timerState) as Number {
        if (timerState == Activity.TIMER_STATE_OFF) {
            return $.ACTIVITY_TIMER_OFF;
        }
        if (timerState == Activity.TIMER_STATE_STOPPED) {
            return $.ACTIVITY_TIMER_STOPPED;
        }
        if (timerState == Activity.TIMER_STATE_PAUSED) {
            return $.ACTIVITY_TIMER_PAUSED;
        }
        if (timerState == Activity.TIMER_STATE_ON) {
            return $.ACTIVITY_TIMER_ON;
        }
        return $.ACTIVITY_TIMER_UNKNOWN;
    }

    public function encodeSport(sport) as Number {
        return sport instanceof Number ? sport : $.ACTIVITY_SPORT_UNKNOWN;
    }

    public function encodeConnectionBooleans(
        phone as Boolean,
        bluetooth as Boolean,
        wifi as Boolean,
        available as Boolean
    ) as Number {
        var flags = 0;
        if (phone) {
            flags = flags | $.CONNECTION_PHONE_CONNECTED;
        }
        if (bluetooth) {
            flags = flags | $.CONNECTION_BLUETOOTH_CONNECTED;
        }
        if (wifi) {
            flags = flags | $.CONNECTION_WIFI_CONNECTED;
        }
        if (available) {
            flags = flags | $.CONNECTION_AVAILABLE;
        }
        return flags;
    }

    public function encodeConnectionFlags(settings) as Number {
        var phone = false;
        var bluetoothConnected = false;
        var wifiConnected = false;
        var available = false;
        if (settings has :phoneConnected) {
            if (settings.phoneConnected) {
                phone = true;
            }
        }
        if (settings has :connectionAvailable) {
            if (settings.connectionAvailable) {
                available = true;
            }
        }
        if (settings has :connectionInfo) {
            var info = settings.connectionInfo;
            if (info instanceof Dictionary) {
                var bluetooth = info.get(:bluetooth);
                if (bluetooth != null
                    && (bluetooth as System.ConnectionInfo).state
                        == System.CONNECTION_STATE_CONNECTED) {
                    bluetoothConnected = true;
                }
                var wifi = info.get(:wifi);
                if (wifi != null
                    && (wifi as System.ConnectionInfo).state
                        == System.CONNECTION_STATE_CONNECTED) {
                    wifiConnected = true;
                }
            }
        }
        return encodeConnectionBooleans(
            phone, bluetoothConnected, wifiConnected, available
        );
    }

    // [activityTimerState, activitySport, connectionFlags]
    public function sample(settings) as Array {
        var timerState = $.ACTIVITY_TIMER_OFF;
        var sport = $.ACTIVITY_SPORT_UNKNOWN;
        try {
            var info = Activity.getActivityInfo();
            if (info != null) {
                timerState = encodeTimerState(info.timerState);
                var profile = Activity.getProfileInfo();
                if (profile != null && profile.sport != null) {
                    sport = encodeSport(profile.sport);
                }
            }
        } catch (e) {
            timerState = $.ACTIVITY_TIMER_UNKNOWN;
            sport = $.ACTIVITY_SPORT_UNKNOWN;
            System.println("Battery telemetry activity context unavailable");
        }
        return [timerState, sport, encodeConnectionFlags(settings)];
    }
}
