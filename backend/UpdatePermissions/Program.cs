using System;
using Microsoft.Data.SqlClient;

class Program
{
    static void Main()
    {
        string connectionString = "Server=192.168.120.3\\EMDATA;Database=Hipo;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;";
        using (SqlConnection connection = new SqlConnection(connectionString))
        {
            connection.Open();
            
            string query = @"
                -- 1. Create UserPermissions table
                IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='UserPermissions' and xtype='U')
                BEGIN
                    CREATE TABLE [UserPermissions] (
                        [PermissionsId] uniqueidentifier NOT NULL,
                        [UsersId] uniqueidentifier NOT NULL,
                        CONSTRAINT [PK_UserPermissions] PRIMARY KEY ([PermissionsId], [UsersId]),
                        CONSTRAINT [FK_UserPermissions_Permissions_PermissionsId] FOREIGN KEY ([PermissionsId]) REFERENCES [Permissions] ([Id]) ON DELETE CASCADE,
                        CONSTRAINT [FK_UserPermissions_Users_UsersId] FOREIGN KEY ([UsersId]) REFERENCES [Users] ([Id]) ON DELETE CASCADE
                    );
                END

                -- 2. Migrate existing custom permissions
                INSERT INTO [UserPermissions] ([PermissionsId], [UsersId])
                SELECT rp.[PermissionId], ur.[UserId]
                FROM [RolePermissions] rp
                JOIN [UserRoles] ur ON rp.[RoleId] = ur.[RoleId]
                JOIN [Roles] r ON r.[Id] = ur.[RoleId]
                WHERE r.[Name] LIKE 'Custom:%'
                AND NOT EXISTS (
                    SELECT 1 FROM [UserPermissions] up WHERE up.[PermissionsId] = rp.[PermissionId] AND up.[UsersId] = ur.[UserId]
                );

                -- 3. Delete Custom Roles (this cascades to UserRoles and RolePermissions)
                DELETE FROM [Roles] WHERE [Name] LIKE 'Custom:%';

                -- 4. Drop UserGroups
                IF EXISTS (SELECT * FROM sys.foreign_keys WHERE name='FK_Users_UserGroups_UserGroupId')
                    ALTER TABLE [Users] DROP CONSTRAINT [FK_Users_UserGroups_UserGroupId];

                IF EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('Users') AND name = 'UserGroupId')
                    ALTER TABLE [Users] DROP COLUMN [UserGroupId];

                IF EXISTS (SELECT * FROM sysobjects WHERE name='UserGroups' and xtype='U')
                    DROP TABLE [UserGroups];
            ";

            using (SqlCommand command = new SqlCommand(query, connection))
            {
                int rowsAffected = command.ExecuteNonQuery();
                Console.WriteLine($"Successfully executed database schema migration! (Affected {rowsAffected} rows)");
            }
        }
    }
}
