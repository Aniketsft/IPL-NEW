using Microsoft.AspNetCore.Http;
using EnterpriseAuth.Api.Core.Application.Interfaces;

namespace EnterpriseAuth.Api.Infrastructure.Features.SchemaManagement
{
    public class HeaderX3SchemaProvider : IX3SchemaProvider
    {
        private readonly IHttpContextAccessor _httpContextAccessor;
        private const string SchemaHeaderName = "X-X3-Schema";
        private const string DefaultSchema = "INLDRYRUN";

        public HeaderX3SchemaProvider(IHttpContextAccessor httpContextAccessor)
        {
            _httpContextAccessor = httpContextAccessor;
        }

        public string GetSchemaName()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context != null && context.Request.Headers.TryGetValue(SchemaHeaderName, out var schemaValue))
            {
                return schemaValue.ToString().ToUpper();
            }

            return DefaultSchema;
        }
    }
}
