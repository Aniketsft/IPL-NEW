using System.Threading.Tasks;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface IStagingService
    {
        Task<bool> PopulateStagingAsync(string soNumber);
    }
}
