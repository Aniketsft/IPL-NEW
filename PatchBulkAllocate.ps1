$connectionString = "Server=192.168.120.3\EMDATA;Database=Hipo;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;Connect Timeout=10;"

$sql = @"
IF NOT EXISTS (SELECT 1 FROM [Permissions] WHERE [Name] = 'manufacturing.bulk_allocate.read')
BEGIN
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'manufacturing.bulk_allocate.read', 'Read access to bulk_allocate in manufacturing');
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'manufacturing.bulk_allocate.create', 'Create access to bulk_allocate in manufacturing');
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'manufacturing.bulk_allocate.update', 'Update access to bulk_allocate in manufacturing');
    INSERT INTO [Permissions] ([Id], [Name], [Description]) VALUES (NEWID(), 'manufacturing.bulk_allocate.delete', 'Delete access to bulk_allocate in manufacturing');
    PRINT 'Inserted bulk_allocate permissions.';
END
ELSE
BEGIN
    PRINT 'Permissions already exist.';
END
"@

Write-Host "Connecting to 192.168.120.3\EMDATA..."
try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $command = New-Object System.Data.SqlClient.SqlCommand($sql, $connection)
    
    $connection.Open()
    Write-Host "Connected successfully."
    
    $rowsAffected = $command.ExecuteNonQuery()
    Write-Host "Execution complete."
    
    $connection.Close()
} catch {
    Write-Host "Error: $($_.Exception.Message)"
}
