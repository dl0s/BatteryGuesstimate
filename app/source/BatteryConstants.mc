// Sampling and retention. Keep every policy knob in this file.
(:background :glance)
const BATTERY_STORAGE_SCHEMA_VERSION = 1;
(:background :glance)
const BATTERY_SAMPLE_SCHEMA_VERSION = 1;
(:background :glance)
const SAMPLE_INTERVAL_MINUTES = 15;
(:background :glance)
const SAMPLE_INTERVAL_SECONDS = SAMPLE_INTERVAL_MINUTES * 60;
(:background :glance)
const MAX_WATCH_SAMPLES = 1345;
(:background :glance)
const BATTERY_PAGE_SIZE = 16;
(:background :glance)
const BATTERY_PAGE_SLOT_COUNT = 85;

// Sync policy.
(:background :glance)
const SYNC_BATCH_SIZE = 16;
(:background :glance)
const SYNC_MIN_PENDING = 8;
(:background :glance)
const SYNC_MAX_SILENCE_SECONDS = 2 * 60 * 60;
(:background :glance)
const SYNC_RETRY_BACKOFF_SECONDS = 2 * 60 * 60;
(:background :glance)
const SYNC_LOW_BATTERY_PCT100 = 1500;
(:background :glance)
const SYNC_LOW_BATTERY_MIN_PENDING = 32;
(:background :glance)
const SYNC_LOW_BATTERY_MAX_SILENCE_SECONDS = 6 * 60 * 60;
(:background :glance)
const SYNC_LOW_BATTERY_RETRY_BACKOFF_SECONDS = 6 * 60 * 60;

// Explicit unknown sentinels. Negative solar values other than this sentinel
// retain Garmin's original "not currently charging" meaning.
(:background :glance)
const BATTERY_DAYS_UNKNOWN = -1;
(:background :glance)
const SOLAR_INTENSITY_UNKNOWN = -32768;
(:background :glance)
const FIRMWARE_VERSION_UNKNOWN = -1;
(:background :glance)
const TEMPERATURE_UNKNOWN = -32768;
(:background :glance)
const TEMPERATURE_REFRESH_SECONDS = 60 * 60;
(:background :glance)
const TEMPERATURE_STALE_SECONDS = 120 * 60;

// Compact activity context. These values are protocol values, not display
// strings. activitySport carries Garmin's raw Activity.SPORT_* number.
(:background :glance)
const ACTIVITY_TIMER_OFF = 0;
(:background :glance)
const ACTIVITY_TIMER_STOPPED = 1;
(:background :glance)
const ACTIVITY_TIMER_PAUSED = 2;
(:background :glance)
const ACTIVITY_TIMER_ON = 3;
(:background :glance)
const ACTIVITY_TIMER_UNKNOWN = 255;
(:background :glance)
const ACTIVITY_SPORT_UNKNOWN = 255;

// Compact connection bit mask. No DeviceSettings dictionary is persisted.
(:background :glance)
const CONNECTION_PHONE_CONNECTED = 1;
(:background :glance)
const CONNECTION_BLUETOOTH_CONNECTED = 2;
(:background :glance)
const CONNECTION_WIFI_CONNECTED = 4;
(:background :glance)
const CONNECTION_AVAILABLE = 8;

// BatterySampleV1 flags.
(:background :glance)
const FLAG_LEGACY_SAMPLE = 1;
(:background :glance)
const FLAG_TIMESTAMP_RECONSTRUCTED = 2;
(:background :glance)
const FLAG_SOLAR_UNKNOWN = 4;
(:background :glance)
const FLAG_BATTERY_DAYS_UNKNOWN = 8;
(:background :glance)
const FLAG_DATA_GAP_BEFORE = 16;
(:background :glance)
const FLAG_MANUAL_SAMPLE = 32;
(:background :glance)
const FLAG_CHARGING_UNKNOWN = 64;
(:background :glance)
const FLAG_FIRMWARE_UNKNOWN = 128;
(:background :glance)
const FLAG_TEMP_UNKNOWN = 256;
(:background :glance)
const FLAG_TEMP_STALE = 512;
(:background :glance)
const FLAG_TEMP_DEVICE_PROXY = 1024;

// Persisted sync state.
(:background :glance)
const SYNC_STATE_IDLE = 0;
(:background :glance)
const SYNC_STATE_PENDING = 1;
(:background :glance)
const SYNC_STATE_SENDING = 2;
(:background :glance)
const SYNC_STATE_WAITING_ACK = 3;
(:background :glance)
const SYNC_STATE_ERROR = 4;

// Persisted error codes. Data is never discarded merely because one occurs.
(:background :glance)
const ERROR_NONE = 0;
(:background :glance)
const ERROR_STORAGE_FULL = 100;
(:background :glance)
const ERROR_STORAGE_WRITE = 101;
(:background :glance)
const ERROR_TRANSMIT_FAILURE = 200;
(:background :glance)
const ERROR_INVALID_ACK = 300;
(:background :glance)
const ERROR_PROTOCOL_MISMATCH = 301;
(:background :glance)
const ERROR_INSTALL_ID_MISMATCH = 302;
(:background :glance)
const ERROR_STALE_ACK = 303;
(:background :glance)
const ERROR_FUTURE_ACK = 304;
(:background :glance)
const ERROR_CORRUPT_PAGE = 400;
(:background :glance)
const ERROR_CORRUPT_METADATA = 401;
(:background :glance)
const ERROR_LEGACY_MIGRATION = 500;

// Storage keys are strings so builds cannot invalidate them like Symbols can.
(:background :glance)
const BATTERY_META_KEY = "battery.meta.v1";
(:background :glance)
const BATTERY_STORAGE_SCHEMA_KEY = "battery.storage.schema";
(:background :glance)
const BATTERY_INSTALL_ID_KEY = "battery.install.id";
(:background :glance)
const BATTERY_PAGE_KEY_PREFIX = "battery.page.v1.";
(:background :glance)
const BATTERY_GLANCE_SUMMARY_KEY = "battery.glance.summary.v1";
(:background :glance)
const BATTERY_GLANCE_SUMMARY_VERSION = 1;
(:background)
const BATTERY_TEMPERATURE_CACHE_KEY = "battery.temperature.cache.v1";
(:background)
const BATTERY_TEMPERATURE_CACHE_VERSION = 1;
(:background)
const BATTERY_DEVICE_DESCRIPTOR_KEY = "battery.device.descriptor.v1";
(:background)
const BATTERY_DEVICE_DESCRIPTOR_VERSION = 1;
(:background)
const BATTERY_APP_VERSION = 1;
