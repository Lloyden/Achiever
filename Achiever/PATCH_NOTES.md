# Achiever 0.6.0

- Splits metadata into Alliance and Horde LoadOnDemand addons.
- Loads only the current character's faction definitions.
- Keeps generated metadata in `ACHIEVER_EMBEDDED_DB`, separate from runtime
  data and SavedVariables.
- Stops persisting the large metadata database on logout.
- Keeps network metadata synchronization disabled.
