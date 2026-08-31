import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// Final Lightweight RC entry. Garmin is only a battery telemetry node:
// sample, durable append, reliable sync, and compact summary projection.
(:background :glance :typecheck([disableBackgroundCheck, disableGlanceCheck]))
class BatteryApp extends Application.AppBase {
    public function initialize() {
        Application.AppBase.initialize();
        try {
            Background.registerForTemporalEvent(
                new Time.Duration($.SAMPLE_INTERVAL_SECONDS)
            );
            if (Background has :registerForPhoneAppMessageEvent) {
                Background.registerForPhoneAppMessageEvent();
            }
        } catch (e) {
            System.println("BatterySync background registration error");
        }
    }

    public function onStart(state as Dictionary?) as Void {
    }

    public function onStop(state as Dictionary?) as Void {
    }

    public function getGlanceView() {
        return [new $.BatteryGuesstimateGlanceView()];
    }

    public function getInitialView() {
        return [new $.BatteryMinimalView(), new $.BatteryMinimalDelegate()];
    }

    public function getServiceDelegate() {
        return [new $.BatteryServiceDelegate()];
    }
}

(:background)
class BatteryServiceDelegate extends System.ServiceDelegate {
    (:background_method)
    public function initialize() {
        System.ServiceDelegate.initialize();
    }

    (:background_method)
    public function onTemporalEvent() as Void {
        var completed = false;
        var started = System.getTimer();
        var temperatureDuration = 0;
        try {
            var nowUtc = Time.now().value();
            var stats = System.getSystemStats();
            var settings = System.getDeviceSettings();
            var context = new BatteryContextSampler().sample(settings);
            var temperature = new TemperatureSampler().sampleAt(nowUtc);
            temperatureDuration = temperature[3];
            var sample = new BatterySampler().sampleFrom(
                stats, settings, context, temperature, 0, nowUtc
            );
            var store = new BatteryStore();
            new DeviceDescriptorStore().maybeUpdate(settings, store.getInstallId());
            completed = store.appendSample(sample);
            if (completed) {
                var phoneConnected = (sample.connectionFlags
                    & $.CONNECTION_PHONE_CONNECTED) != 0;
                new BatterySyncManager().syncAt(
                    false,
                    sample.batteryPct100,
                    sample.charging,
                    phoneConnected,
                    nowUtc
                );
                var meta = store.getMeta();
                var duration = System.getTimer() - started;
                meta.put("lastBackgroundDurationMs", duration);
                var maximum = meta.get("maxBackgroundDurationMs") as Number;
                if (duration > maximum) {
                    meta.put("maxBackgroundDurationMs", duration);
                }
                meta.put("temperatureReadDurationMs", temperatureDuration);
                store.saveMeta(meta);
                new BatteryGlanceSummaryStore().updateFrom(sample, meta);
            }
        } catch (e) {
            System.println("BatterySync temporal error " + e.getErrorMessage());
            new BatteryMetaStore().recordError($.ERROR_STORAGE_WRITE);
        }
        Background.exit(completed);
    }

    (:background_method)
    public function onPhoneAppMessage(
        message as Communications.PhoneAppMessage
    ) as Void {
        var accepted = false;
        try {
            var handler = new BatteryAckHandler();
            accepted = handler.handle(message.data);
            var manager = new BatterySyncManager();
            if (accepted && !handler.wasDescriptorRequest()) {
                var stats = System.getSystemStats();
                manager.sync(
                    true,
                    Math.round(stats.battery * 100.0).toNumber(),
                    stats.charging
                );
            } else if (!accepted) {
                manager.sendStatus();
            }
        } catch (e) {
            System.println("BatterySync background phone error");
            new BatteryMetaStore().recordError($.ERROR_INVALID_ACK);
        }
        Background.exit(accepted);
    }
}
