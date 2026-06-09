using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using EnterpriseAuth.Api.Infrastructure.Security;
using EnterpriseAuth.Api.Core.Application.Services;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Infrastructure.Features.SchemaManagement;

var builder = WebApplication.CreateBuilder(args);

// SCANPRODUCTION SCHEMA DEBUG
try {
    string connStr = builder.Configuration.GetConnectionString("ScanProduction")!;
    using var conn = new Microsoft.Data.SqlClient.SqlConnection(connStr);
    conn.Open();
    Console.WriteLine("--- SCHEMA DEBUG (production_scan) ---");
    var command = conn.CreateCommand();
    command.CommandText = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'production_scan'";
    using (var reader = command.ExecuteReader())
    {
        while (reader.Read())
        {
            Console.WriteLine($"DB COLUMN: {reader.GetString(0)}");
        }
    }
} catch (Exception ex) { Console.WriteLine("DEBUG SCAN SCHEMA ERROR: " + ex.Message); }
// END SCANPRODUCTION SCHEMA DEBUG

// Add services to the container.
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles;
    });
builder.Services.AddSwaggerGen();

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

// Dynamic Database Selection
var dbSource = builder.Configuration["DatabaseSource"];
builder.Services.AddDbContext<ApplicationDbContext>(options =>
{
    if (dbSource == "Postgres")
    {
        options.UseNpgsql(builder.Configuration.GetConnectionString("Postgres"));
    }
    else
    {
        options.UseSqlServer(builder.Configuration.GetConnectionString("SqlServer"));
    }
});

// Dedicated context for new ScanProduction database
builder.Services.AddDbContext<ScanProductionDbContext>(options =>
{
    options.UseSqlServer(builder.Configuration.GetConnectionString("ScanProduction"));
});

// Dependency Injection
builder.Services.AddScoped<IUserRepository, EfUserRepository>();
builder.Services.AddScoped<IRoleRepository, EfRoleRepository>();

builder.Services.AddScoped<ILogisticsRepository, EfLogisticsRepository>();
builder.Services.AddScoped<ILogisticsService, LogisticsService>();
builder.Services.AddScoped<ISyncRepository, EfSyncRepository>();
builder.Services.AddScoped<IPasswordHasher, BCryptPasswordHasher>();
builder.Services.AddScoped<ITokenService, JwtTokenService>();
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IStagingService, StagingService>();
builder.Services.AddScoped<ISageX3SoapService, SageX3SoapService>();
builder.Services.AddHttpClient();
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<IX3SchemaProvider, HeaderX3SchemaProvider>();

// Configure SyncSettings
builder.Services.Configure<SyncSettings>(builder.Configuration.GetSection("SyncSettings"));

// Configure EodSettings
builder.Services.Configure<EodSettings>(builder.Configuration.GetSection("EodSettings"));

// JWT Authentication
var jwtSettings = builder.Configuration.GetSection("Jwt");
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtSettings["Issuer"],
            ValidAudience = jwtSettings["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSettings["Key"]!))
        };

        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = async context =>
            {
                var dbContext = context.HttpContext.RequestServices.GetRequiredService<ApplicationDbContext>();
                var userIdString = context.Principal?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
                var tokenVersionString = context.Principal?.FindFirst("TokenVersion")?.Value;

                if (Guid.TryParse(userIdString, out var userId) && Guid.TryParse(tokenVersionString, out var tokenVersion))
                {
                    var userTokenVersion = await dbContext.Users
                        .Where(u => u.Id == userId)
                        .Select(u => u.TokenVersion)
                        .FirstOrDefaultAsync();

                    if (userTokenVersion != tokenVersion)
                    {
                        context.Fail("Token is invalid because permissions have changed.");
                    }
                }
                else
                {
                    context.Fail("Token is missing required claims.");
                }
            }
        };
    });

var app = builder.Build();

// Seed Primary Database and Create ScanProduction database
using (var scope = app.Services.CreateScope())
{
    // Primary auth & user management seed
    var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher>();
    await DbInitializer.SeedAsync(context, hasher);
    
    // Automatically create ScanProduction database if it doesn't exist
    var scanContext = scope.ServiceProvider.GetRequiredService<ScanProductionDbContext>();
    scanContext.Database.EnsureCreated();
    await DbInitializer.MigrateScanProductionAsync(scanContext);
    await DbInitializer.MigrateEnterpriseRedesignAsync(scanContext);
    await DbInitializer.MigrateFinalDecommissionAsync(scanContext);
    await DbInitializer.MigrateStagingTableAsync(scanContext);
}

// Configure the HTTP request pipeline.
// Swagger enabled for all environments (IIS InProcess doesn't reliably detect Development mode)
app.UseSwagger();
app.UseSwaggerUI();

// app.UseHttpsRedirection(); // Causes issues with Android Emulator on HTTP port 5004

app.UseCors();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
