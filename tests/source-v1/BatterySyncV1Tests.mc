import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Test;

function testSample(percent100 as Number) as BatterySampleV1 {
    return new BatterySampleV1(
        0,
        1700000000 + percent100,
        percent100,
        1200,
        false,
        25,
        12,
        34,
        $.ACTIVITY_TIMER_OFF,
        0,
        $.CONNECTION_PHONE_CONNECTED | $.CONNECTION_BLUETOOTH_CONNECTED,
        234,
        1699999900 + percent100,
        $.FLAG_TEMP_DEVICE_PROXY
    );
}

function appendTestSamples(count as Number) as BatteryStore {
    var store = new BatteryStore();
    for (var i = 0; i < count; i += 1) {
        Test.assertMessage(store.appendSample(testSample(5000 + (i % 100))), "append failed at " + i);
    }
    return store;
}

function assertNumber(actual, expected, message as String) as Void {
    Test.assertEqualMessage(actual as Number, expected as Number, message);
}

(:test)
function storageFirstInstall(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var first = new BatteryStore();
    var installId = first.getInstallId();
    Test.assertMessage(installId.length() == 32, "installId must be 32 characters");
    var second = new BatteryStore();
    Test.assertEqualMessage(second.getInstallId(), installId, "installId must survive restart");
    Storage.deleteValue($.BATTERY_INSTALL_ID_KEY);
    var recovered = new BatteryStore();
    Test.assertEqualMessage(
        recovered.getInstallId(), installId, "metadata must recover the dedicated installId key"
    );
    assertNumber(second.getMeta().get("nextSeq"), 1, "first nextSeq");
    return true;
}

(:test)
function storageAppendPageRolloverAndRestart(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(17);
    assertNumber(store.getMeta().get("newestSeq"), 17, "newest after rollover");
    assertNumber(store.getMeta().get("tailPage"), 1, "tail page after rollover");
    assertNumber(store.getSample(17).seq, 17, "seq stored explicitly");
    var restarted = new BatteryStore();
    Test.assertMessage(restarted.appendSample(testSample(6000)), "restart append");
    assertNumber(restarted.getMeta().get("newestSeq"), 18, "seq continuation");
    return true;
}

(:test)
function storageAckedCapacityRecycle(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples($.MAX_WATCH_SAMPLES);
    Test.assertMessage(store.applyAck($.MAX_WATCH_SAMPLES), "ack all");
    Test.assertMessage(store.appendSample(testSample(5000)), "append beyond acknowledged capacity");
    var meta = store.getMeta();
    assertNumber(meta.get("oldestSeq"), 2, "oldest recycled");
    Test.assertMessage(meta.get("lastDataLossFromSeq") == null, "acked recycle is not loss");
    Test.assertMessage(
        (store.getSample(2).flags & $.FLAG_DATA_GAP_BEFORE) == 0,
        "acked recycle must not create a data-gap flag"
    );
    return true;
}

(:test)
function storageBacklogFullDataLoss(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples($.MAX_WATCH_SAMPLES - 1);
    var meta = store.getMeta();
    assertNumber(meta.get("oldestSeq"), 1, "1344 oldest");
    assertNumber(meta.get("newestSeq"), 1344, "1344 newest");
    Test.assertMessage(meta.get("lastDataLossFromSeq") == null, "1344 has no loss");

    Test.assertMessage(store.appendSample(testSample(5000)), "append 1345");
    meta = store.getMeta();
    assertNumber(meta.get("oldestSeq"), 1, "1345 oldest");
    assertNumber(meta.get("newestSeq"), 1345, "1345 newest");
    Test.assertMessage(meta.get("lastDataLossFromSeq") == null, "1345 has no loss");

    Test.assertMessage(store.appendSample(testSample(5001)), "append 1346");
    meta = store.getMeta();
    assertNumber(meta.get("oldestSeq"), 2, "oldest after overflow");
    assertNumber(meta.get("lastDataLossFromSeq"), 1, "loss start");
    assertNumber(meta.get("lastDataLossToSeq"), 1, "loss end");
    Test.assertMessage(
        (store.getSample(2).flags & $.FLAG_DATA_GAP_BEFORE) != 0,
        "first retained sample must carry DATA_GAP_BEFORE"
    );

    Test.assertMessage(store.appendSample(testSample(5002)), "append 1347");
    Test.assertMessage(store.appendSample(testSample(5003)), "append 1348");
    meta = store.getMeta();
    assertNumber(meta.get("lastDataLossFromSeq"), 1, "merged loss start");
    assertNumber(meta.get("lastDataLossToSeq"), 3, "continuous loss ranges merge");
    return true;
}

(:test)
function storageCorruptMetadataRecovery(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    appendTestSamples(20);
    Storage.setValue($.BATTERY_META_KEY, "corrupt");
    var recovered = new BatteryStore();
    var meta = recovered.getMeta();
    assertNumber(meta.get("newestSeq"), 20, "recovered newest");
    assertNumber(meta.get("nextSeq"), 21, "recovered continuation");
    assertNumber(meta.get("lastErrorCode"), $.ERROR_CORRUPT_METADATA, "corruption recorded");
    return true;
}

(:test)
function storageMissingMetadataRecovery(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    appendTestSamples(20);
    Storage.deleteValue($.BATTERY_META_KEY);
    var recovered = new BatteryStore();
    var meta = recovered.getMeta();
    assertNumber(meta.get("oldestSeq"), 1, "recovered missing-meta oldest");
    assertNumber(meta.get("newestSeq"), 20, "recovered missing-meta newest");
    assertNumber(meta.get("ackedSeq"), 0, "missing-meta recovery retransmits");
    assertNumber(meta.get("lastErrorCode"), $.ERROR_CORRUPT_METADATA, "missing metadata recorded");
    return true;
}

(:test)
function storageCorruptPageCreatesExplicitLoss(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(20);
    Storage.deleteValue($.BATTERY_PAGE_KEY_PREFIX + 0);
    var meta = store.ensurePendingContinuity();
    assertNumber(meta.get("lastDataLossFromSeq"), 1, "corrupt-page loss start");
    assertNumber(meta.get("lastDataLossToSeq"), 16, "corrupt-page loss end");
    assertNumber(meta.get("oldestSeq"), 17, "first available after corrupt page");
    Test.assertMessage(
        (store.getSample(17).flags & $.FLAG_DATA_GAP_BEFORE) != 0,
        "first row after corrupt page carries a gap flag"
    );
    return true;
}

(:test)
function syncDoesNotStarveLossWithoutRows(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    appendTestSamples(3);
    Storage.deleteValue($.BATTERY_PAGE_KEY_PREFIX + 0);
    var store = new BatteryStore();
    store.ensurePendingContinuity();
    assertNumber(store.getPendingCount(), 0, "no rows remain pending");
    Test.assertMessage(
        new BatterySyncManager().shouldSyncAt(false, 5000, false, true, 20000),
        "DATA_LOSS must be eligible even with no sample rows"
    );
    return true;
}

(:test)
function syncRetryBackoff(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(32);
    var meta = store.getMeta();
    meta.put("lastSyncAttemptUtc", 10000);
    store.saveMeta(meta);
    var manager = new BatterySyncManager();
    Test.assertMessage(
        !manager.shouldSyncAt(false, 5000, false, true, 17199),
        "normal background retry waits at least two hours"
    );
    Test.assertMessage(
        manager.shouldSyncAt(false, 5000, false, true, 17200),
        "normal background retry resumes at two hours"
    );
    Test.assertMessage(
        !manager.shouldSyncAt(false, 1400, false, true, 17200),
        "low battery uses a longer retry backoff"
    );
    Test.assertMessage(
        manager.shouldSyncAt(false, 1400, false, true, 31600),
        "low battery retry resumes at six hours"
    );
    return true;
}

(:test)
function syncPhoneDisconnectedSkipsBackgroundTransmit(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    appendTestSamples(8);
    Test.assertMessage(
        !new BatterySyncManager().syncAt(false, 5000, false, false, 20000),
        "disconnected background sync exits before transport"
    );
    assertNumber(
        new BatteryStore().getMeta().get("lastSyncAttemptUtc"),
        0,
        "disconnected gate must not record a transmit attempt"
    );
    return true;
}

(:test)
function syncForegroundImmediate(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(1);
    var meta = store.getMeta();
    meta.put("lastSyncAttemptUtc", 20000);
    store.saveMeta(meta);
    Test.assertMessage(
        new BatterySyncManager().shouldSyncAt(true, 5000, false, false, 20001),
        "foreground/SYNC_REQUEST path bypasses retry and background connection gates"
    );
    return true;
}

(:test)
function statusTransportDoesNotWaitForAck(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(8);
    var manager = new BatterySyncManager();
    new BatteryTransportListener(manager, false).onComplete();
    assertNumber(
        store.getMeta().get("syncState"),
        $.SYNC_STATE_PENDING,
        "STATUS completion preserves sync state"
    );
    new BatteryTransportListener(manager, true).onComplete();
    assertNumber(
        store.getMeta().get("syncState"),
        $.SYNC_STATE_WAITING_ACK,
        "durable message completion waits for ACK"
    );
    return true;
}

(:test)
function protocolSampleBatchEncoding(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(3);
    var payload = new BatteryProtocol().buildSampleBatch(
        store.getInstallId(), store.getPendingBatch(16)
    );
    assertNumber(payload[0], $.TYPE_SAMPLE_BATCH, "batch type");
    assertNumber(payload[1], $.BATTERY_PROTOCOL_VERSION, "protocol version");
    assertNumber(payload[3], 1, "first seq");
    assertNumber(payload[4], 3, "last seq");
    Test.assertEqualMessage(payload[5].size(), 3, "three compact rows");
    Test.assertEqualMessage(payload[5][0].size(), 13, "sample wire row has thirteen fields");
    assertNumber(payload[5][0][5], 12, "firmware major encoded");
    assertNumber(payload[5][0][6], 34, "firmware minor encoded");
    assertNumber(payload[5][0][7], $.ACTIVITY_TIMER_OFF, "timer state encoded");
    assertNumber(payload[5][0][8], 0, "Garmin sport enum encoded");
    assertNumber(
        payload[5][0][9],
        $.CONNECTION_PHONE_CONNECTED | $.CONNECTION_BLUETOOTH_CONNECTED,
        "connection flags encoded"
    );
    assertNumber(payload[5][0][10], 234, "temperature encoded in deci-C");
    assertNumber(payload[5][0][11], 1699999900 + 5000, "real temperature timestamp encoded");
    assertNumber(payload[5][0][12], $.FLAG_TEMP_DEVICE_PROXY, "flags encoded last");
    return true;
}

(:test)
function firmwareStorageEncodeDecode(logger as Test.Logger) as Boolean {
    var sample = testSample(7421);
    var decoded = BatterySampleV1.fromStorageArray(sample.toStorageArray());
    assertNumber(decoded.firmwareMajor, 12, "firmware major round trip");
    assertNumber(decoded.firmwareMinor, 34, "firmware minor round trip");
    assertNumber(decoded.toPayloadArray()[5], 12, "wire firmware major position");
    assertNumber(decoded.toPayloadArray()[6], 34, "wire firmware minor position");
    assertNumber(decoded.temperatureDeciC, 234, "temperature round trip");
    assertNumber(
        decoded.temperatureTimestampUtc,
        sample.temperatureTimestampUtc,
        "temperature timestamp round trip"
    );

    var oldCandidateRow = [1, 9, 1700000000, 5000, 1200, 0, 25, 0];
    var upgraded = BatterySampleV1.fromStorageArray(oldCandidateRow);
    assertNumber(upgraded.firmwareMajor, $.FIRMWARE_VERSION_UNKNOWN, "old row major sentinel");
    assertNumber(upgraded.firmwareMinor, $.FIRMWARE_VERSION_UNKNOWN, "old row minor sentinel");
    Test.assertMessage(
        (upgraded.flags & $.FLAG_FIRMWARE_UNKNOWN) != 0,
        "old candidate row carries firmware unknown"
    );
    Test.assertMessage(
        (upgraded.flags & $.FLAG_TEMP_UNKNOWN) != 0,
        "old candidate row carries temperature unknown"
    );
    return true;
}

(:test)
function activityContextEncoding(logger as Test.Logger) as Boolean {
    var sampler = new BatteryContextSampler();
    assertNumber(
        sampler.encodeTimerState(Toybox.Activity.TIMER_STATE_OFF),
        $.ACTIVITY_TIMER_OFF,
        "timer OFF"
    );
    assertNumber(
        sampler.encodeTimerState(Toybox.Activity.TIMER_STATE_STOPPED),
        $.ACTIVITY_TIMER_STOPPED,
        "timer STOPPED"
    );
    assertNumber(
        sampler.encodeTimerState(Toybox.Activity.TIMER_STATE_PAUSED),
        $.ACTIVITY_TIMER_PAUSED,
        "timer PAUSED"
    );
    assertNumber(
        sampler.encodeTimerState(Toybox.Activity.TIMER_STATE_ON),
        $.ACTIVITY_TIMER_ON,
        "timer ON"
    );
    assertNumber(sampler.encodeTimerState(null), $.ACTIVITY_TIMER_UNKNOWN, "timer unknown");
    assertNumber(
        sampler.encodeSport(Toybox.Activity.SPORT_RUNNING),
        Toybox.Activity.SPORT_RUNNING,
        "sport enum passes through without a string"
    );
    assertNumber(sampler.encodeSport(null), $.ACTIVITY_SPORT_UNKNOWN, "sport unknown");
    return true;
}

(:test)
function connectionContextBitmaskEncoding(logger as Test.Logger) as Boolean {
    var sampler = new BatteryContextSampler();
    var all = sampler.encodeConnectionBooleans(true, true, true, true);
    assertNumber(
        all,
        $.CONNECTION_PHONE_CONNECTED
            | $.CONNECTION_BLUETOOTH_CONNECTED
            | $.CONNECTION_WIFI_CONNECTED
            | $.CONNECTION_AVAILABLE,
        "all connection bits"
    );
    assertNumber(
        sampler.encodeConnectionBooleans(false, true, false, true),
        $.CONNECTION_BLUETOOTH_CONNECTED | $.CONNECTION_AVAILABLE,
        "sparse connection bits"
    );
    return true;
}

(:test)
function temperatureValidNegativeUnknownAndStale(logger as Test.Logger) as Boolean {
    var sampler = new TemperatureSampler();
    var valid = sampler.fromCacheAt([1, 234, 10000, 10000], 11000);
    assertNumber(valid[0], 234, "valid temperature");
    assertNumber(valid[1], 10000, "valid timestamp remains original");
    Test.assertMessage((valid[2] & $.FLAG_TEMP_DEVICE_PROXY) != 0, "proxy flag");
    Test.assertMessage((valid[2] & $.FLAG_TEMP_STALE) == 0, "fresh temperature");

    var negative = sampler.fromCacheAt([1, -52, 10000, 10000], 11000);
    assertNumber(negative[0], -52, "negative deci-C temperature");

    var unknown = sampler.fromCacheAt([1, $.TEMPERATURE_UNKNOWN, 0, 10000], 11000);
    assertNumber(unknown[0], $.TEMPERATURE_UNKNOWN, "unknown sentinel");
    Test.assertMessage((unknown[2] & $.FLAG_TEMP_UNKNOWN) != 0, "unknown flag");

    var stale = sampler.fromCacheAt(
        [1, 234, 10000, 10000],
        10000 + $.TEMPERATURE_STALE_SECONDS + 1
    );
    Test.assertMessage((stale[2] & $.FLAG_TEMP_STALE) != 0, "stale flag");
    assertNumber(stale[1], 10000, "stale timestamp is not rewritten");
    return true;
}

(:test)
function temperatureCacheReuseAndRefreshInterval(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var cache = [1, 234, 10000, 12000];
    Test.assertMessage(new TemperatureCacheStore().save(cache), "cache save");
    var restarted = new TemperatureCacheStore().load();
    assertNumber(restarted[1], 234, "cache survives restart");
    assertNumber(restarted[2], 10000, "cache preserves sensor time");
    var sampler = new TemperatureSampler();
    Test.assertMessage(
        !sampler.shouldRefreshAt(restarted, 12000 + $.TEMPERATURE_REFRESH_SECONDS - 1),
        "reuse for four 15-minute callbacks"
    );
    Test.assertMessage(
        sampler.shouldRefreshAt(restarted, 12000 + $.TEMPERATURE_REFRESH_SECONDS),
        "refresh at 60 minutes"
    );
    return true;
}

(:test)
function glanceSummaryColdWarmAndIsolation(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var summaryStore = new BatteryGlanceSummaryStore();
    Test.assertMessage(summaryStore.load() == null, "cold Glance has no summary");
    Storage.setValue("cBlP", 4);
    var summary = new BatteryGlanceSummaryV1(
        7421, 1285, false, 25, 234, 7, 1700000000, 0,
        $.SYNC_STATE_PENDING, $.FLAG_TEMP_DEVICE_PROXY
    );
    Test.assertMessage(summaryStore.save(summary), "summary save");
    var warm = summaryStore.load();
    assertNumber(warm.latestBatteryPct100, 7421, "warm Glance battery");
    assertNumber(warm.pendingCount, 7, "warm Glance pending");
    Test.assertMessage(
        Storage.getValue($.BATTERY_STORAGE_SCHEMA_KEY) == null,
        "summary read does not initialize/migrate PageStore"
    );
    Test.assertMessage(Storage.getValue("cBlP") != null, "summary read does not migrate legacy");
    Test.assertMessage(
        Storage.getValue($.BATTERY_META_KEY) == null,
        "summary read does not trigger sync or recovery"
    );
    return true;
}

(:test)
function backgroundStyleAppendPreservesAck(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(2);
    Test.assertMessage(store.applyAck(1), "initial durable ack");
    Test.assertMessage(store.appendSample(testSample(6000)), "next temporal append");
    assertNumber(store.getMeta().get("ackedSeq"), 1, "sampling cannot advance ACK");
    new BatteryGlanceSummaryStore().updateFrom(
        store.getSample(3), store.getMeta()
    );
    assertNumber(store.getMeta().get("ackedSeq"), 1, "summary update cannot advance ACK");
    return true;
}

(:test)
function protocolControlMessages(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(3);
    var protocol = new BatteryProtocol();
    var id = store.getInstallId();
    Test.assertMessage(id.length() == 32, "ACK test installId must remain canonical");
    var lossMeta = store.getMeta();
    lossMeta.put("lastDataLossFromSeq", 4);
    lossMeta.put("lastDataLossToSeq", 7);
    lossMeta.put("oldestSeq", 8);
    lossMeta.put("newestSeq", 12);
    var loss = protocol.buildDataLoss(id, lossMeta);
    assertNumber(loss[0], $.TYPE_DATA_LOSS, "loss type");
    assertNumber(loss[3], 4, "loss start");
    assertNumber(loss[4], 7, "loss end");
    var request = protocol.decodeSyncRequest([$.TYPE_SYNC_REQUEST, 1, id, 2]);
    Test.assertMessage(request.get("ok") == true, "valid sync request");
    Test.assertEqualMessage(request.get("installId"), id, "sync request install id");
    assertNumber(request.get("ackedSeq"), 2, "sync request committed seq");
    var wrong = protocol.decodeSyncRequest([$.TYPE_SYNC_REQUEST, 1, "wrong", 2]);
    Test.assertMessage(
        wrong.get("ok") == true && wrong.get("installId") != id,
        "caller can reject wrong-install sync request"
    );
    var descriptorRequest = protocol.decodeDescriptorRequest([
        $.TYPE_DESCRIPTOR_REQUEST, 1, id
    ]);
    Test.assertMessage(descriptorRequest.get("ok") == true, "descriptor request decode");
    var descriptorPayload = protocol.buildDeviceDescriptor(id, [1, id, "part"]);
    assertNumber(descriptorPayload[0], $.TYPE_DEVICE_DESCRIPTOR, "descriptor response type");
    Test.assertEqualMessage(descriptorPayload[3][2], "part", "descriptor payload");
    return true;
}

(:test)
function lightweightPathPerformanceBudgets(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var summaryStore = new BatteryGlanceSummaryStore();
    var started = Toybox.System.getTimer();
    var cold = summaryStore.load();
    var coldMs = Toybox.System.getTimer() - started;
    Test.assertMessage(cold == null, "cold summary read");

    var summary = new BatteryGlanceSummaryV1(
        7421, 1285, false, 25, 234, 0, 1700000000, 0,
        $.SYNC_STATE_IDLE, $.FLAG_TEMP_DEVICE_PROXY
    );
    summaryStore.save(summary);
    started = Toybox.System.getTimer();
    var warm = summaryStore.load();
    var warmMs = Toybox.System.getTimer() - started;
    Test.assertMessage(warm != null, "warm summary read");

    var store = new BatteryStore();
    started = Toybox.System.getTimer();
    var sample = testSample(7421);
    Test.assertMessage(store.appendSample(sample), "normal callback append");
    summaryStore.updateFrom(sample, store.getMeta());
    new BatterySyncManager().shouldSyncAt(false, 7421, false, false, 1700001000);
    var normalMs = Toybox.System.getTimer() - started;

    Storage.deleteValue($.BATTERY_TEMPERATURE_CACHE_KEY);
    var temperature = new TemperatureSampler();
    var refresh = temperature.sampleAt(1700001000);
    var refreshMs = refresh[3] as Number;
    var reuse = temperature.sampleAt(1700001000 + $.SAMPLE_INTERVAL_SECONDS);
    Test.assertMessage(refresh[4] == true, "temperature refresh callback ran");
    Test.assertMessage(reuse[4] == false, "normal callback reused temperature cache");
    assertNumber(reuse[3], 0, "cache reuse performs no SensorHistory read");

    logger.debug("glanceColdMs=" + coldMs
        + " glanceWarmMs=" + warmMs
        + " normalCallbackCoreMs=" + normalMs
        + " temperatureReadMs=" + refreshMs);
    Test.assertMessage(coldMs < 250, "cold Glance summary read budget");
    Test.assertMessage(warmMs < 250, "warm Glance summary read budget");
    Test.assertMessage(normalMs < 1000, "normal callback core budget");
    Test.assertMessage(refreshMs < 1000, "single-entry temperature read budget");
    return true;
}

(:test)
function protocolAckValidation(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(3);
    var id = store.getInstallId();
    Test.assertEqualMessage(
        new BatteryStore().getInstallId(), id, "installId stable before ACK handler"
    );
    var handler = new BatteryAckHandler();
    Test.assertMessage(handler.handle([$.TYPE_ACK, 1, id, 2]), "valid ack");
    assertNumber(store.getMeta().get("ackedSeq"), 2, "ack applied");
    Test.assertMessage(handler.handle([$.TYPE_ACK, 1, id, 2]), "duplicate ack is safe");
    Test.assertMessage(!handler.handle([$.TYPE_ACK, 1, id, 1]), "stale ack rejected");
    Test.assertMessage(!handler.handle([$.TYPE_ACK, 1, id, 4]), "future ack rejected");
    Test.assertMessage(!handler.handle([$.TYPE_ACK, 2, id, 3]), "wrong protocol rejected");
    Test.assertMessage(!handler.handle([$.TYPE_ACK, 1, "wrong", 3]), "wrong install rejected");
    assertNumber(store.getMeta().get("ackedSeq"), 2, "invalid ack cannot advance");
    return true;
}

(:test)
function syncTransportSuccessWithoutAckAndRetry(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(20);
    var protocol = new BatteryProtocol();
    var first = protocol.buildSampleBatch(store.getInstallId(), store.getPendingBatch(16));
    new BatterySyncManager().onTransportComplete(true);
    assertNumber(store.getMeta().get("ackedSeq"), 0, "transport success is not ack");
    var retried = protocol.buildSampleBatch(store.getInstallId(), new BatteryStore().getPendingBatch(16));
    assertNumber(retried[3], first[3], "retry first seq");
    assertNumber(retried[4], first[4], "retry last seq");
    return true;
}

(:test)
function syncAckResumeAcrossRestart(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(20);
    var id = store.getInstallId();
    Test.assertEqualMessage(
        new BatteryStore().getInstallId(), id, "restart installId stable before resume ACK"
    );
    Test.assertMessage(new BatteryAckHandler().handle([$.TYPE_ACK, 1, id, 16]), "ack first batch");
    var restarted = new BatteryStore();
    var next = new BatteryProtocol().buildSampleBatch(id, restarted.getPendingBatch(16));
    assertNumber(next[3], 17, "resume first seq");
    assertNumber(next[4], 20, "resume last seq");
    return true;
}

(:test)
function syncFailureAndOfflineBacklog(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    var store = appendTestSamples(288);
    new BatterySyncManager().onTransportError(true);
    assertNumber(store.getMeta().get("ackedSeq"), 0, "offline does not delete");
    assertNumber(store.getPendingCount(), 288, "three-day style backlog remains pending");
    assertNumber(store.getMeta().get("syncState"), $.SYNC_STATE_ERROR, "failure state");
    return true;
}

(:test)
function legacyFloatMigration(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    Storage.setValue("cBlP", 2);
    Storage.setValue(0, 70.0);
    Storage.setValue(1, 69.5);
    Storage.setValue(2, 69.0);
    Test.assertMessage($.databaseMigration(), "legacy migration");
    var store = new BatteryStore();
    assertNumber(store.getMeta().get("newestSeq"), 3, "three legacy rows");
    var sample = store.getSample(1);
    Test.assertMessage((sample.flags & $.FLAG_LEGACY_SAMPLE) != 0, "legacy flag");
    Test.assertMessage(
        (sample.flags & $.FLAG_TIMESTAMP_RECONSTRUCTED) != 0,
        "reconstructed timestamp flag"
    );
    assertNumber(sample.firmwareMajor, $.FIRMWARE_VERSION_UNKNOWN, "legacy firmware major");
    assertNumber(sample.firmwareMinor, $.FIRMWARE_VERSION_UNKNOWN, "legacy firmware minor");
    Test.assertMessage(
        (sample.flags & $.FLAG_FIRMWARE_UNKNOWN) != 0,
        "legacy firmware is explicitly unknown"
    );
    return true;
}

(:test)
function legacyPartialCorruption(logger as Test.Logger) as Boolean {
    Storage.clearValues();
    Storage.setValue("cBlP", 2);
    Storage.setValue(0, 70.0);
    Storage.setValue(1, "bad");
    Storage.setValue(2, 69.0);
    Test.assertMessage(!$.databaseMigration(), "partial corruption is reported");
    var meta = new BatteryStore().getMeta();
    assertNumber(meta.get("newestSeq"), 2, "valid legacy rows survive");
    assertNumber(meta.get("legacyDroppedSamples"), 1, "bad row counted");
    return true;
}
