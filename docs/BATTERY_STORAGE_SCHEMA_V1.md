# Battery Storage Schema V1

## Purpose

Storage V1 is a bounded durable short-term watch backlog, not the canonical
long-term database. Capacity is 1345 samples (approximately 14 days at 15
minutes) solely to protect sync reliability; no watch UI scans it for history.

## Keys

| Key | Value |
| --- | --- |
| `battery.storage.schema` | Number `1` |
| `battery.install.id` | Stable 32-character String |
| `battery.meta.v1` | Metadata Dictionary below |
| `battery.page.v1.<slot>` | Page Array; slots `0..84` |
| `battery.glance.summary.v1` | One compact `BatteryGlanceSummaryV1` array |
| `battery.temperature.cache.v1` | Last real temperature and refresh-attempt time |
| `battery.device.descriptor.v1` | Static `DeviceDescriptorV1` array |

No Symbol is persisted as a key or value.

## Metadata dictionary

Required fields are:

| Field | Meaning |
| --- | --- |
| `storageSchemaVersion` | `1` |
| `installId` | Installation identity duplicated from its dedicated key |
| `nextSeq` | Sequence assigned to the next successful append |
| `ackedSeq` | Highest continuous iPhone durable commit acknowledged |
| `oldestSeq` / `newestSeq` | Current bounded retained range |
| `headPage` / `tailPage` | Logical page ids for the retained range |
| `lastSyncAttemptUtc` | Last transmit attempt epoch seconds |
| `lastSyncSuccessUtc` | Last accepted ACK epoch seconds |
| `lastDataLossFromSeq` / `lastDataLossToSeq` | Pending explicit gap, or null |

Additional recovery fields are `inFlightFromSeq`, `inFlightToSeq`, `syncState`,
`lastErrorCode`, `lastErrorUtc`, and `legacyDroppedSamples`.

## Page layout

`[storageSchemaVersion, logicalPageId, sampleRows]`

- Page size: 16.
- Physical slot: `logicalPageId % 85`.
- Sequence-to-page: `(seq - 1) / 16`.
- A stored sample row explicitly contains seq:
  `[sampleSchemaVersion, seq, timestampUtc, batteryPct100, batteryInDays100,
  chargingFlag, solarIntensity, firmwareMajor, firmwareMinor,
  activityTimerState, activitySport, connectionFlags, temperatureDeciC,
  temperatureTimestampUtc, flags]`.

The reader also accepts earlier eight- and ten-field freeze-candidate storage
rows. It supplies explicit unknown firmware/activity/temperature context and
flags before the sample is returned or transmitted.

The page is written before final metadata advancement. If metadata is damaged,
the page scan conservatively reconstructs bounds, sets `ackedSeq` to zero, and
causes safe retransmission.

A missing/corrupt page does not abort startup. When it reaches the next pending
sequence, the store records the absent contiguous range as DATA_LOSS, advances
`oldestSeq` to the first available row, and marks that row with
`DATA_GAP_BEFORE`. If no row remains, `oldestSeq` is `newestSeq + 1`; the loss
marker is still eligible for immediate transport even though pending row count
is zero.

## Capacity and recycling

ACKed rows may remain until capacity pressure requires reuse, but are not used
for watch history UI or analysis. If the oldest row is ACKed, reuse is normal.
If it is not ACKed, the loss range is persisted before page reuse and the first
retained row gets `FLAG_DATA_GAP_BEFORE`.

## Legacy migration

When either legacy head key is detected, numeric Float rows are streamed oldest
to newest into V1 pages. Timestamp values are reconstructed from their ring
offset and the 15-minute sampling policy; migrated rows set `LEGACY_SAMPLE`,
`TIMESTAMP_RECONSTRUCTED`, `SOLAR_UNKNOWN`, `BATTERY_DAYS_UNKNOWN`, and
`CHARGING_UNKNOWN`. Firmware is `-1/-1` and `FIRMWARE_UNKNOWN` is set. Invalid
or unwritable rows are explicitly counted in
`legacyDroppedSamples` and removed. Migration errors are persisted as code 500
and do not prevent application startup.
