using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Http;
using EnterpriseAuth.Api.Core.Application.Interfaces;

namespace EnterpriseAuth.Api.Infrastructure.Features.SchemaManagement
{
    public class HeaderX3SchemaProvider : IX3SchemaProvider
    {
        private readonly IHttpContextAccessor _httpContextAccessor;
        private const string SchemaHeaderName = "X-X3-Schema";
        private const string DefaultSchema = "INLDRYRUN";
        private static readonly Regex SchemaRegex = new Regex("^[A-Z0-9_]{1,30}$", RegexOptions.Compiled);

        public HeaderX3SchemaProvider(IHttpContextAccessor httpContextAccessor)
        {
            _httpContextAccessor = httpContextAccessor;
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

            return DefaultSchema;
        }
    }
}
