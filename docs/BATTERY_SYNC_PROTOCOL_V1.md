# BATTERY SYNC PROTOCOL V1

## Freeze status

`protocolVersion = 1`

The message positions and semantics in this document are the V1 freeze
candidate. They become **BATTERY SYNC PROTOCOL V1 — FROZEN** only after the
checked-in fēnix 7 Pro simulator suite completes and the 72-hour device
acceptance run passes. Until then, no iPhone production implementation should
ship against a different shape.

After freeze, existing positions, units, and meanings may change only in V2.
Optional new message types require a protocol revision if an old V1 peer cannot
safely ignore them.

## Allowed transport types

V1 uses Number, String, Array, and Boolean-compatible numeric flags. ByteArray is
not used. All messages are positional arrays.

## Message types

| Name | Number | Direction |
| --- | ---: | --- |
| `SAMPLE_BATCH` | 1 | Garmin -> iPhone |
| `ACK` | 2 | iPhone -> Garmin |
| `SYNC_REQUEST` | 3 | iPhone -> Garmin |
| `STATUS` | 4 | Garmin -> iPhone |
| `DATA_LOSS` | 5 | Garmin -> iPhone |
| `DEVICE_DESCRIPTOR` | 6 | Garmin -> iPhone |
| `DESCRIPTOR_REQUEST` | 7 | iPhone -> Garmin |

## SAMPLE_BATCH

`[1, 1, installId, firstSeq, lastSeq, samples]`

Each item in `samples` is:

`[timestampUtc, batteryPct100, batteryInDays100, chargingFlag, solarIntensity, firmwareMajor, firmwareMinor, activityTimerState, activitySport, connectionFlags, temperatureDeciC, temperatureTimestampUtc, flags]`

The sequence for `samples[i]` is `firstSeq + i`. `lastSeq` must equal
`firstSeq + samples.size() - 1`. Removing per-row seq saves one Number per
sample while retaining deterministic identity and readable code. The local page
row still stores seq explicitly.

Field definitions:

| Field | Type/unit |
| --- | --- |
| `timestampUtc` | Unix epoch seconds; authoritative despite schedule jitter |
| `batteryPct100` | Percentage x100; `7421` means 74.21% |
| `batteryInDays100` | Days x100; `1285` means 12.85 days; `-1` unknown |
| `chargingFlag` | `0` false, `1` true |
| `solarIntensity` | Garmin raw Number semantics; `-32768` unknown |
| `firmwareMajor` | `DeviceSettings.firmwareVersion[0]`; `-1` unknown |
| `firmwareMinor` | `DeviceSettings.firmwareVersion[1]`; `-1` unknown |
| `activityTimerState` | Compact V1 enum: `0 OFF`, `1 STOPPED`, `2 PAUSED`, `3 ON`, `255 UNKNOWN` |
| `activitySport` | Garmin numeric `Activity.SPORT_*` value; `255` unknown/invalid |
| `connectionFlags` | Compact connection bit mask below |
| `temperatureDeciC` | Device-temperature proxy in 0.1 C; `-32768` unknown |
| `temperatureTimestampUtc` | Epoch seconds of the real SensorHistory record; never rewritten on cache reuse |
| `flags` | V1 bit field below |

Garmin sends at most 16 samples per batch. Sixteen keeps messages bounded well
below BLE oversized-request risk, aligns with a storage page, and limits retry
work while avoiding the overhead of 8-row batches.

## ACK

`[2, 1, installId, ackedSeq]`

`ackedSeq` and every sequence before it have been durably and continuously
committed to the iPhone canonical store, or are covered by a durably committed
DATA_LOSS marker. ACK is sent only after the SQLite transaction commits.

Garmin rejects a protocol mismatch, install mismatch, decreasing ACK, or ACK
above local `newestSeq`. An equal ACK is a safe duplicate. Transport completion
is never interpreted as ACK.

## SYNC_REQUEST

`[3, 1, installId, highestContiguousAccountedSeq]`

The fourth value carries the same durability claim as ACK and requests the next
batch. If it is below Garmin's persisted `ackedSeq`, Garmin does not regress and
responds with STATUS. If it is valid and equal/higher, Garmin applies it and may
send one next batch.

When the request accounts for every current local record (`pending == 0`),
Garmin persists `syncRequestedPending = true`. The next authoritative 15-minute
sample then triggers an immediate transport attempt. The latch is cleared when
that transport attempt begins, so a failed attempt falls back to the normal
retry backoff instead of retrying every 15 minutes.

## STATUS

`[4, 1, installId, ackedSeq, oldestSeq, newestSeq, pendingCount, state, errorCode]`

State values: `0 IDLE`, `1 PENDING`, `2 SENDING`, `3 WAITING_ACK`, `4 ERROR`.

STATUS is a fire-and-forget control message. Its transport completion does not
enter `WAITING_ACK` and its transport error does not mutate the durable sample
state. SAMPLE_BATCH and DATA_LOSS require durable confirmation and enter
`WAITING_ACK` only after transport completion; that state still does not advance
`ackedSeq`.

`errorCode` values are fixed for V1 STATUS messages:

| Value | Name |
| ---: | --- |
| 0 | `NONE` |
| 100 | `STORAGE_FULL` / explicit unACKed eviction |
| 101 | `STORAGE_WRITE` |
| 200 | `TRANSMIT_FAILURE` |
| 300 | `INVALID_ACK` |
| 301 | `PROTOCOL_MISMATCH` |
| 302 | `INSTALL_ID_MISMATCH` |
| 303 | `STALE_ACK` |
| 304 | `FUTURE_ACK` |
| 400 | `CORRUPT_PAGE` |
| 401 | `CORRUPT_METADATA` |
| 500 | `LEGACY_MIGRATION` |

## DATA_LOSS

`[5, 1, installId, lostFromSeq, lostToSeq, oldestAvailableSeq, newestSeq]`

Garmin sends a pending DATA_LOSS marker before any later sample batch. The iPhone
must transactionally persist the marker, establish the explicit skipped range,
then ACK `lostToSeq`. This ACK bridges continuity without inventing samples.
Duplicate DATA_LOSS messages must be idempotent. Garmin retains the marker until
an ACK reaches `lostToSeq`.

## Flags V1

| Bit | Value | Meaning |
| --- | ---: | --- |
| `LEGACY_SAMPLE` | 1 | Migrated from Float ring storage |
| `TIMESTAMP_RECONSTRUCTED` | 2 | Timestamp approximated at 15-minute slots |
| `SOLAR_UNKNOWN` | 4 | Solar API unavailable/null; sentinel is present |
| `BATTERY_DAYS_UNKNOWN` | 8 | Days unavailable/null; sentinel is present |
| `DATA_GAP_BEFORE` | 16 | An explicit retained-data gap precedes this row |
| `MANUAL_SAMPLE` | 32 | Sample was manually requested |
| `CHARGING_UNKNOWN` | 64 | Historical migration cannot recover charging |
| `FIRMWARE_UNKNOWN` | 128 | Firmware major/minor are both `-1` |

Unknown bits must be stored and forwarded unchanged by V1 receivers.

Additional final-candidate temperature flag bits are:

| Bit | Value | Meaning |
| --- | ---: | --- |
| `TEMP_UNKNOWN` | 256 | No valid device-temperature sample exists |
| `TEMP_STALE` | 512 | Real temperature record is older than 120 minutes |
| `TEMP_DEVICE_PROXY` | 1024 | Value is device temperature used as an environmental proxy, not strict ambient temperature |

`connectionFlags` uses `1 PHONE_CONNECTED`, `2 BLUETOOTH_CONNECTED`,
`4 WIFI_CONNECTED`, and `8 CONNECTION_AVAILABLE`.

## DEVICE_DESCRIPTOR and request

The iPhone sends `[7, 1]` for anonymous first discovery. Garmin must accept it
without an `installId` and respond with the authoritative
`[6, 1, installId, descriptor]`. The iPhone may also send
`[7, 1, installId]` for an identified descriptor request; Garmin validates the
identity before responding. A wrong protocol version is always rejected.

`descriptor` is the persisted compact `DeviceDescriptorV1` array containing
install identity, part number, Monkey C runtime version, app version, protocol
version, activity-tracking setting, and firmware pair. Descriptor transport is
informational and does not advance the sample ACK. The watch rewrites the
descriptor only on first creation, app or firmware/device metadata change, or
an explicit request that finds it absent.

## Identity and sequence rules

- `installId` is generated once on first V1 initialization, stored separately
  and in metadata, and remains stable across restart and app upgrade.
- Uninstall/reinstall may generate a new `installId` and restarts seq at 1.
- Record identity is `(installId, seq)`. Timestamp is never a primary key.
- Seq is a positive monotonic Connect IQ Number. It is assigned only to an
  append attempt whose page write succeeds; it never follows a circular slot.
- V1 never wraps seq. A future range expansion requires V2.

## Ordering, retry, and restart

Garmin always starts from `ackedSeq + 1`, unless an explicit DATA_LOSS marker
must be processed first. Only one bounded batch is initiated per manager call.
On transmit failure, ACK loss, phone absence, watch restart, or app restart, the
same unacknowledged first/last range is rebuilt from durable pages and resent.
Newer samples may accumulate behind it. Delivery is at least once.

Background attempts require `DeviceSettings.phoneConnected == true`. After any
durable-message attempt, normal background retry waits at least 2 hours using
persisted `lastSyncAttemptUtc`; below 15% battery it waits at least 6 hours.
Foreground immediate sync and a received ACK/SYNC_REQUEST may bypass the retry
backoff so backlog can continue draining while the phone is actively engaged.

The iPhone must tolerate duplicate batches, overlapping replays, duplicate ACK
requests, and a Garmin restart at any point. It must reject inconsistent content
for an already committed `(installId, seq)` rather than silently overwrite it.

## Protocol migration

A V1 endpoint rejects unsupported `protocolVersion` and does not ACK it. V2 must
use its own version number and explicitly define negotiation/migration. V1 field
positions and units remain immutable after freeze.

Earlier freeze-candidate drafts used six and then eight fields per wire sample.
Neither was FROZEN. The final thirteen-field schema above supersedes both.
Previously stored watch rows are upgraded in memory with explicit unknown
activity, connection, firmware, and temperature values/flags, then transmitted
using the final shape. Future field-position changes require V2 after this
candidate is frozen.
