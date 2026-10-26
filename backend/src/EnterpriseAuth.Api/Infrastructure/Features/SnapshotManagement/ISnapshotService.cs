using System;
using System.IO;
using System.Threading.Tasks;

namespace EnterpriseAuth.Api.Infrastructure.Features.SnapshotManagement
{
    public record SnapshotFileResult(string FilePath, string ETag, bool IsGzip, DateTime LastModifiedUtc);

    public interface ISnapshotService
    {
        Task<SnapshotFileResult> GetOrUpdateSnapshotAsync<T>(
            string siteCode,
            string snapshotName,
            Func<Task<string>> probeWatermarkFunc,
            Func<Task<T>> queryDataFunc);

        Task PrewarmSiteSnapshotsAsync(string siteCode);
    }
}
