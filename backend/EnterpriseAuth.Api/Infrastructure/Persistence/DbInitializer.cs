using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public static class DbInitializer
    {
        public static async Task SeedAsync(ApplicationDbContext context, IPasswordHasher hasher)
        {
            await context.Database.EnsureCreatedAsync();

            // Ensure CutBulkEntries table exists (EnsureCreated doesn't add tables to existing DBs)
            var createTableSql = @"
                IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[CutBulkEntries]') AND type in (N'U'))
                BEGIN
                    CREATE TABLE [dbo].[CutBulkEntries] (
                        [Id] INT IDENTITY(1,1) NOT NULL,
                        [EntryNumber] NVARCHAR(50) NOT NULL,
                        [Type] NVARCHAR(20) NOT NULL,
                        [CustomerCode] NVARCHAR(50) NOT NULL,
                        [CustomerName] NVARCHAR(100) NOT NULL,
                        [Date] DATETIME NOT NULL,
                        [PoNumber] NVARCHAR(50) NULL,
                        [Salesman1Code] NVARCHAR(50) NULL,
                        [Salesman2Code] NVARCHAR(50) NULL,
                        [AmountKg] DECIMAL(18, 2) NOT NULL,
                        CONSTRAINT [PK_CutBulkEntries] PRIMARY KEY CLUSTERED ([Id] ASC)
                    );
                    CREATE UNIQUE INDEX [IX_CutBulkEntries_EntryNumber] ON [dbo].[CutBulkEntries] ([EntryNumber] ASC);
                END";
            
            await context.Database.ExecuteSqlRawAsync(createTableSql);

            // Reconciliation: Add missing columns if table already existed (EnsureCreated limitation)
            var addColumnsSql = @"
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[CutBulkEntries]') AND name = 'Salesman1Code')
                BEGIN
                    ALTER TABLE [dbo].[CutBulkEntries] ADD [Salesman1Code] NVARCHAR(50) NULL;
                END
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[CutBulkEntries]') AND name = 'Salesman2Code')
                BEGIN
                    ALTER TABLE [dbo].[CutBulkEntries] ADD [Salesman2Code] NVARCHAR(50) NULL;
                END";
            
            await context.Database.ExecuteSqlRawAsync(addColumnsSql);

            // Seed Permissions (Hierarchical Tree Structure)
            // Format: Module -> SubModule(s) -> Child(ren)
            // The order here reflects the Home Screen priority requested.
            var hierarchy = new List<(string Module, string[] SubModules)>
            {
                ( "logistics", new[] { "receipt", "transfer", "delivery" } ),
                ( "manufacturing", new[] { "dashboard", "view_sales_order", "view_sales_order.sales_order", "work_order", "tracking", "components", "products" } ),
                ( "inventory", new[] { "stock_control", "picking", "by_identifier" } ),
                ( "administration", new[] { "user_management" } ),
                ( "settings", new[] { "general", "printer" } )
            };
            
            var actions = new[] { "Create", "Read", "Update", "Delete" };
            var existingPermissions = await context.Permissions.ToDictionaryAsync(p => p.Name.ToLowerInvariant());
            var permissionsToAdd = new List<Permission>();

            foreach (var item in hierarchy)
            {
                foreach (var subModule in item.SubModules)
                {
                    foreach (var action in actions)
                    {
                        var permName = $"{item.Module}.{subModule}.{action}".ToLowerInvariant();
                        if (!existingPermissions.ContainsKey(permName))
                        {
                            permissionsToAdd.Add(new Permission 
                            { 
                                Id = Guid.NewGuid(), 
                                Name = permName, 
                                Description = $"{action} access to {subModule} in {item.Module}" 
                            });
                        }
                    }
                }
            }

            if (permissionsToAdd.Any())
            {
                await context.Permissions.AddRangeAsync(permissionsToAdd);
                await context.SaveChangesAsync();
                Console.WriteLine($"[DbInitializer] Added {permissionsToAdd.Count} new permissions.");
            }

            // Seed Roles
            var allPermissions = await context.Permissions.ToListAsync();
            Console.WriteLine($"[DbInitializer] Total permissions in DB: {allPermissions.Count}");

            var adminRole = await context.Roles.Include(r => r.Permissions).FirstOrDefaultAsync(r => r.Name == "Admin");
            if (adminRole == null)
            {
                adminRole = new Role
                {
                    Id = Guid.NewGuid(),
                    Name = "Admin",
                    Description = "Full system access",
                    Permissions = new List<Permission>(allPermissions)
                };
                await context.Roles.AddAsync(adminRole);
                Console.WriteLine("[DbInitializer] Created Admin role with all permissions.");
            }
            else
            {
                // Brute force update: Clear and re-add to ensure sync
                adminRole.Permissions.Clear();
                foreach(var p in allPermissions) adminRole.Permissions.Add(p);
                Console.WriteLine($"[DbInitializer] Synchronized Admin role with {allPermissions.Count} permissions.");
            }

            // Ensure other roles exist
            if (!await context.Roles.AnyAsync(r => r.Name == "Operator"))
            {
                await context.Roles.AddAsync(new Role { 
                    Id = Guid.NewGuid(), 
                    Name = "Operator", 
                    Permissions = allPermissions.Where(p => p.Name.Contains(".read")).ToList() 
                });
            }

            await context.SaveChangesAsync();

            // Seed User Groups
            var itGroup = await context.UserGroups.FirstOrDefaultAsync(g => g.Name == "IT Administration");
            if (itGroup == null)
            {
                itGroup = new UserGroup
                {
                    Id = Guid.NewGuid(),
                    Name = "IT Administration",
                    RoleId = adminRole.Id
                };
                await context.UserGroups.AddAsync(itGroup);
            }

            await context.SaveChangesAsync();

            // Seed Admin User
            var adminUser = await context.Users
                .Include(u => u.Roles)
                .FirstOrDefaultAsync(u => u.Username == "admin");

            if (adminUser == null)
            {
                var passwordHash = hasher.HashPassword("password", out string salt);
                adminUser = new User
                {
                    Id = Guid.NewGuid(),
                    Username = "admin",
                    Email = "admin@enterprise.com",
                    PasswordHash = passwordHash,
                    Salt = salt,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow,
                    Roles = new List<Role> { adminRole },
                    UserGroupId = itGroup.Id
                };
                await context.Users.AddAsync(adminUser);
                Console.WriteLine("[DbInitializer] Created 'admin' user and assigned Admin role.");
            }
            else
            {
                // Ensure Admin Role Link
                if (!adminUser.Roles.Any(r => r.Name == "Admin"))
                {
                    adminUser.Roles.Add(adminRole);
                    Console.WriteLine("[DbInitializer] Assigned missing Admin role to existing 'admin' user.");
                }
                adminUser.UserGroupId = itGroup.Id;
            }

            await context.SaveChangesAsync();
            Console.WriteLine("[DbInitializer] Seeding completed successfully.");
        }
    }
}
