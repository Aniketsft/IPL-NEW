using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Domain.Entities;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface ISageX3SoapService
    {
        /// <summary>
        /// Imports a single Sales Order (with multiple lines) into Sage X3 via AOWSIMPORT.
        /// </summary>
        Task<X3ImportResult> ImportSalesOrderAsync(string soNumber, List<Staging> records);

        /// <summary>
        /// Processes all pending records in the Staging table, grouped by SO Number.
        /// </summary>
        Task<EndOfDayResult> ProcessEndOfDayAsync();
    }
}
