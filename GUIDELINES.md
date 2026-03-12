# Enterprise Auth System - Technical Guidelines

## Backend Guidelines (C# / .NET)

### 1. DTO Consistency for Mobile Sync
- **Naming Convention**: All DTOs intended for mobile synchronization MUST use `camelCase` for property naming in JSON serialization. This ensures compatibility with Dart's `json_serializable`.
- **Serialization**: Use `System.Text.Json` with `JsonNamingPolicy.CamelCase`. If specific property names are required, use `[JsonPropertyName("name")]`.

### 2. Synchronization Integrity
- **Master Data**: When implementing new synchronization flows, always include relevant master data (e.g., `ProductLookupDto`) within the `SyncPackageDto`. This allows the mobile client to perform offline validation.
- **Data Integrity**: Ensure that SQL extensions for synchronization populate all required fields, including units of measure and descriptions, to avoid "Missing Description" errors on the client.

---

## Frontend Guidelines (Dart / Flutter)

### 1. Offline-First Validation
- **Local Master Storage**: Use the local `tbl_products` (Product Master) for all real-time validations during scanning. DO NOT rely on active server connections for base-level validation.
- **Database Helper**: Any schema changes must be accompanied by an increment in `databaseVersion` within `LocalDatabaseHelper` and a corresponding migration in `_onUpgrade`.

### 2. Barcode Handling
- **Multi-Format Decoding**: Use the `BarcodeDecoder` logic for all scanning entries. It must support:
  - **Fixed Weight (Prefix '10')**: Barcode contains Code only.
  - **Variable Weight (Prefix '20')**: Barcode contains Code + Weight (last 6 digits / 1000).
  - **Global Lookup**: Fallback direct string match in the Product Master.
- **Scanning Guards**: Always verify `isValidProduct()` before allowing a scan to persist.

### 3. Sync Package Decoders
- **DTO Correspondence**: When the backend updates a DTO, the corresponding `fromJson` and `toJson` methods in Dart must be updated immediately. Ensure all fields are nullable if the backend might omit them in incremental updates.
