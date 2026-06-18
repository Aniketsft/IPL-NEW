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

        /// <summary>
        /// Processes all pending Production EOD records in the StagingEod table.
        /// </summary>
        Task<EndOfDayResult> ProcessProductionEodAsync();

        /// <summary>
        /// Imports a single Sales Invoice (Header + Lines) into Sage X3 via AOWSIMPORT using the ZSIHWEBA template.
        /// </summary>
        Task<X3ImportResult> ImportSalesInvoiceAsync(StagingSalesInvoiceHeader invoice);
    }
}
