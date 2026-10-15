using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Application.Common;

namespace EnterpriseAuth.Api.Infrastructure.Features.SchemaManagement
{
    public class HeaderX3SchemaProvider : IX3SchemaProvider
    {
        private readonly IHttpContextAccessor _httpContextAccessor;
        private readonly SyncSettings _syncSettings;
        private const string SchemaHeaderName = "X-X3-Schema";
        private static readonly Regex SchemaRegex = new Regex("^[A-Z0-9_]{1,30}$", RegexOptions.Compiled);

        public HeaderX3SchemaProvider(IHttpContextAccessor httpContextAccessor, IOptions<SyncSettings> syncSettings)
        {
            _httpContextAccessor = httpContextAccessor;
            _syncSettings = syncSettings.Value;
        }

        public string GetSchemaName()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context != null && context.Request.Headers.TryGetValue(SchemaHeaderName, out var schemaValue))
            {
                var val = schemaValue.ToString().Trim().ToUpper();
                if (SchemaRegex.IsMatch(val))
                {
                    return val;
                }
            }

            return !string.IsNullOrWhiteSpace(_syncSettings.X3SchemaName) 
                ? _syncSettings.X3SchemaName.Trim() 
                : "INLDRYRUN";
        }
    }
}
