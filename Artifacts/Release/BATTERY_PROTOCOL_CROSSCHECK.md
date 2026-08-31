# BATTERY PROTOCOL CROSSCHECK

Date: 2026-08-31

Protocol version: `1`

| Message | Wire shape | Garmin | iOS | Result |
| --- | --- | --- | --- | --- |
| `SAMPLE_BATCH` | `[1,1,installId,firstSeq,lastSeq,samples]`; 13-field rows | MATCH | MATCH | MATCH |
| `ACK` | `[2,1,installId,ackedSeq]` | MATCH | MATCH | MATCH |
| `SYNC_REQUEST` | `[3,1,installId,highestContiguousAccountedSeq]` | MATCH | MATCH | MATCH |
| `STATUS` | `[4,1,installId,acked,oldest,newest,pending,state,errorCode]` | MATCH | MATCH | MATCH |
| `DATA_LOSS` | `[5,1,installId,lostFrom,lostTo,oldestAvailable,newest]` | MATCH | MATCH | MATCH |
| `DEVICE_DESCRIPTOR` | `[6,1,installId,descriptor]` | MATCH | MATCH | MATCH |
| `DESCRIPTOR_REQUEST` | `[7,1]` and `[7,1,installId]` | MATCH | MATCH | MATCH |

Additional checks:

- Battery IQApp UUID: `05d38102-5aa5-4628-be94-94665e629840` on both sides.
- Sample field count and order: 13 fields, identical positions.
- `highestContiguousAccountedSeq` is the sync cursor; it is never `MAX(seq)`.
- DATA_LOSS advances the accounted cursor only after durable commit.
- `syncRequestedPending` latch is persisted in Garmin MetaStore and cleared
  after a transport attempt.
- First bootstrap: iPhone sends `[7,1]`, persists `[6,1,installId,descriptor]`,
  then sends `[3,1,installId,accounted]`.
- Protocol status remains `FREEZE CANDIDATE`; it is not marked `FROZEN`.
