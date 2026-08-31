# Garmin Battery Telemetry Architecture

## Lightweight RC boundary

Garmin is a battery telemetry node. Its production responsibilities are only:

1. sample compact battery-relevant telemetry;
2. append it to a bounded durable backlog;
3. synchronize it with durable ACK semantics;
4. maintain one compact Glance/Minimal-View summary.

The iPhone owns complete history, trends, charge/discharge segmentation,
temperature correlation, firmware/activity analysis, battery aging/SOH, data
quality, and export.

## Production flow

```text
15-minute Background
  -> SystemStats (once)
  -> DeviceSettings (once)
  -> ActivityInfo (once)
  -> ActivityProfile (at most once)
  -> TemperatureSampler (one newest record, only when hourly refresh is due)
  -> BatterySampleV1
  -> BatteryPageStore append
  -> BatteryGlanceSummaryStore update
  -> BatterySyncManager bounded decision/transmit
  -> exit

BatteryGlanceSummaryStore -> GlanceView / BatteryMinimalView
```

Glance performs exactly one summary-key read. It cannot construct
`BatteryStore`, scan pages/history, migrate/recover, calculate history, or start
sync. App startup only registers callbacks; it does not migrate, recompute, or
force sync. Legacy migration remains schema-gated in `BatteryStore` and runs
only when V1 storage has not been initialized.

## Removed from production navigation and callback paths

- 24h/2d/7d/14d graph and history pages
- watch discharge-rate and custom prediction calculations
- history averages and startup history recomputation
- aging/SOH and charge/discharge segment analysis
- WebDAV/watch history export
- Glance PageStore/history access and forced sync
- foreground startup sync
- charge-threshold web notification

Legacy source files remain temporarily for repository history and old test
compatibility, but no production App, Glance, Minimal View, or background entry
references them.

## Compact stores

- `BatteryPageStore`: bounded 16-row pages; unACKed data is never deleted merely
  because transport completed.
- `TemperatureCacheStore`: last real deci-C value, its real SensorHistory epoch,
  and last refresh attempt.
- `BatteryGlanceSummaryStore`: latest display-only projection.
- `DeviceDescriptorStore`: installation/static device metadata, rewritten only
  when changed.

## Protocol state

Battery Protocol V1 remains a **FREEZE CANDIDATE**. Earlier six/eight-field
candidate rows were never frozen, so the final candidate uses the requested
thirteen-field row. Old candidate storage rows are adapted in memory. Once the
simulator matrix and 72-hour device acceptance gate pass, V1 may be marked
FROZEN; subsequent positional changes require V2.
