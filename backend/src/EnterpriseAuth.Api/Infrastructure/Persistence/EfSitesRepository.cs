using System.Collections.Generic;
using System.Data;
using System.Threading.Tasks;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfSitesRepository : ISitesRepository
    {
        private readonly string _connectionString;
        private readonly SyncSettings _syncSettings;
        private readonly IX3SchemaProvider _schemaProvider;

        public EfSitesRepository(
            IConfiguration configuration,
            IOptions<SyncSettings> syncSettings,
            IX3SchemaProvider schemaProvider)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new System.ArgumentNullException("Innodis connection string is missing");
            _syncSettings = syncSettings.Value;
            _schemaProvider = schemaProvider;
        }

        public async Task<IEnumerable<SiteDto>> GetSitesAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            
            var databaseName = _syncSettings.X3DatabaseName;
            var schemaName = _schemaProvider.GetSchemaName();
            
            var query = $@"
                SELECT 
                    LTRIM(RTRIM(T1.FCY_0)) AS SiteCode, 
                    LTRIM(RTRIM(T1.FCYNAM_0)) AS SiteName,
                    SALFLG_0 AS IsSalesSite
                FROM [{databaseName}].[{schemaName}].[FACILITY] T1 WITH (NOLOCK)
                WHERE T1.SALFLG_0 = 2 
                ORDER BY T1.FCY_0;
            ";

            return await db.QueryAsync<SiteDto>(query);
        }
    }
}
