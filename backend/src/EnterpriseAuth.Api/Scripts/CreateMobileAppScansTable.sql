-- Create the MobileAppScans table to store synchronized barcode scans from the mobile application.

USE InnodisTestDB;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[INLPROD].[MobileAppScans]') AND type in (N'U'))
BEGIN
CREATE TABLE [INLPROD].[MobileAppScans](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[SoNumber] [varchar](50) NOT NULL,
	[ProductCode] [varchar](50) NOT NULL,
	[Quantity] [decimal](18, 4) NOT NULL,
	[ScanTimestamp] [datetime2](7) NOT NULL,
	[SyncTimestamp] [datetime2](7) NOT NULL DEFAULT GETUTCDATE(),
 CONSTRAINT [PK_MobileAppScans] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
END
GO
