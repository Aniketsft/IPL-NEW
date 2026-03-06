# Enterprise Auth System

A dual-stack project featuring a .NET backend and a Flutter Mobile frontend.

## Getting Started

### Backend (.NET API)
1. **Database Setup**:
   - Ensure you have MS SQL Server or PostgreSQL installed.
   - Update `backend/EnterpriseAuth.Api/appsettings.json` with your connection strings.
   - Set `"DatabaseSource"` to `"SqlServer"` or `"Postgres"`.
2. **Run API**:
   ```bash
   cd backend/EnterpriseAuth.Api
   dotnet run
   ```

### Mobile (Flutter)
1. **Dependencies**:
   ```bash
   cd mobile
   flutter pub get
   ```
2. **Run App**:
   - Ensure a mobile emulator or device is connected.
   ```bash
   flutter run
   ```

## Infrastructure Logic
The backend uses a **Hexagonal** pattern. To swap databases, the DI container checks the configuration and injects the corresponding EF Core provider.

## Access Control
This system uses **Permission-Based Access Control (PBAC)** via **Roles**. Users belong to Roles, and Roles have Permissions. Permissions are discoverable and dynamic.
