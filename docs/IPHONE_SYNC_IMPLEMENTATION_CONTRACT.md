# iPhone Sync Implementation Contract

The only Garmin wire specification for the future iPhone implementation is
[`BATTERY_SYNC_PROTOCOL_V1.md`](BATTERY_SYNC_PROTOCOL_V1.md).

## Required platform and persistence behavior

The iPhone application must:

1. Use the Garmin Connect IQ Mobile SDK to receive and send app messages.
2. Validate message type, exact positional length, `protocolVersion`, field
   types, `installId`, and first/last sequence consistency before persistence.
3. Store samples in SQLite with `UNIQUE(install_id, seq)`.
4. Perform batch insertion and continuity update in one SQLite transaction.
5. Send ACK only after that transaction successfully commits to durable
   canonical storage.
6. ACK the highest continuously committed seq, never merely the batch's last
   value and never data still held only in memory.
7. Make duplicate and overlapping SAMPLE_BATCH delivery safe.
8. Preserve `timestampUtc`, units, raw solar values, firmware major/minor,
   activity context, connection bitmask, temperature value and original
   timestamp, sentinels, and unknown flag bits exactly as received.
9. Reject unsupported protocol versions without ACK.
10. Persist DATA_LOSS markers transactionally before ACKing `lostToSeq`.

## Recommended future Swift models (not implemented here)

```text
GarminInstall
  installId: String (primary key)
  highestContinuousSeq: Int64
  protocolVersion: Int

BatterySample
  installId: String
  seq: Int64
  timestampUtc: Int64
  batteryPct100: Int
  batteryInDays100: Int
  chargingFlag: Int
  solarIntensity: Int
  firmwareMajor: Int
  firmwareMinor: Int
  activityTimerState: Int
  activitySport: Int
  connectionFlags: Int
  temperatureDeciC: Int
  temperatureTimestampUtc: Int64
  flags: Int
  UNIQUE(installId, seq)

BatteryDataLoss
  installId: String
  lostFromSeq: Int64
  lostToSeq: Int64
  oldestAvailableSeq: Int64
  observedAtUtc: Int64
  UNIQUE(installId, lostFromSeq, lostToSeq)
```

Insertion conflict handling must compare all immutable fields. An exact duplicate
is success; different content for the same identity is a protocol/data-integrity
error and must not be ACKed past the conflict.

`firmwareMajor` and `firmwareMinor` come directly from Garmin
`DeviceSettings.firmwareVersion`. The iPhone must store the numeric pair without
reconstructing a display string. `-1/-1` with `FIRMWARE_UNKNOWN` means the
sample predates telemetry or the value was unavailable.

`temperatureDeciC` is device temperature used only as an environmental proxy.
It must not be relabeled as strict ambient temperature: skin contact, wearing
state, sunlight, and device self-heating can all affect it. Correlation and
quality analysis belong on iPhone. The watch's 60-minute cache reuse preserves
the real `temperatureTimestampUtc`; `TEMP_STALE` begins after 120 minutes.

The iPhone owns all complete history, daily metrics, charge/discharge segments,
temperature correlation, firmware/activity analysis, aging/SOH, data quality,
and export. None of these computations should be reintroduced on Garmin.

## Continuity algorithm

After a successful transaction, advance `highestContinuousSeq` only while the
next sequence is either stored as a sample or covered by a committed DATA_LOSS
range. ACK that value. Do not infer continuity from timestamps or batch arrival
order.

No Swift, SQLite, UI, CSV, JSON export, analytics, or cloud implementation is
part of the Garmin V1 phase.
