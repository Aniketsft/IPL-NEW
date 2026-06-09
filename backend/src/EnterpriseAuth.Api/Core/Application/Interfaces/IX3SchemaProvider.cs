namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface IX3SchemaProvider
    {
        /// <summary>
        /// Returns the name of the X3 schema to use (e.g., INLPROD or INLDRYRUN).
        /// </summary>
        string GetSchemaName();
    }
}
