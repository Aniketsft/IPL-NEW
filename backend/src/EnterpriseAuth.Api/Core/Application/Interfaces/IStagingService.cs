using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface IStagingService
    {
        Task<bool> PopulateStagingAsync(string soNumber);
        Task<List<StagingReportDto>> GetStagingReportByDateAsync(System.DateTime deliveryDate);
    }
}
