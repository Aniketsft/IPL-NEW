# System Overview & Architecture

## Core Technology Stack
1. **Frontend (Mobile App)**:
   - **Framework**: Flutter (Dart)
   - **State Management**: flutter_bloc (BLoC + Cubit architecture)
   - **Local Storage**: SQLite (`sqflite`) database: `InnodisApp.db`
   - **Hardware Printing**: Sunmi / Bluetooth ESC/POS printers via `printing` package & native channels
   - **Target Devices**: Android POS handhelds (e.g., Infinix X6528, Sunmi V2s)

2. **Backend**:
   - **Framework**: ASP.NET Core (.NET 8/10)
   - **Database**: SQL Server / EF Core (`StagingSalesInvoiceHeaders`, `StagingSalesInvoiceLines`, `X3SoapAudits`)
   - **ERP Integration**: Sage X3 ERP via SOAP Web Services (`CAdxWebServiceXmlCCClient`)
   - **Authentication**: JWT Bearer + Refresh Token + Device ID Binding
