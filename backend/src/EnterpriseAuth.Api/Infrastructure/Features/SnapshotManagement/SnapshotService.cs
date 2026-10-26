using System;
using System.Collections.Concurrent;
using System.IO;
using System.IO.Compression;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace EnterpriseAuth.Api.Infrastructure.Features.SnapshotManagement
{
    public class SnapshotService : ISnapshotService
    {
        private readonly string _baseStorageDir;
        private readonly ILogger<SnapshotService> _logger;
        private static readonly ConcurrentDictionary<string, SemaphoreSlim> _locks = new();
        private static readonly ConcurrentDictionary<string, string> _watermarkCache = new();

        public SnapshotService(IHostEnvironment env, ILogger<SnapshotService> logger)
        {
            _logger = logger;
            _baseStorageDir = Path.Combine(env.ContentRootPath, "App_Data", "snapshots");
            if (!Directory.Exists(_baseStorageDir))
            {
                Directory.CreateDirectory(_baseStorageDir);
            }
        }

        public async Task<SnapshotFileResult> GetOrUpdateSnapshotAsync<T>(
            string siteCode,
            string snapshotName,
            Func<Task<string>> probeWatermarkFunc,
            Func<Task<T>> queryDataFunc)
        {
            var normalizedSite = string.IsNullOrWhiteSpace(siteCode) ? "GLOBAL" : siteCode.Trim().ToUpperInvariant();
            var lockKey = $"{normalizedSite}_{snapshotName}";
            var siteDir = Path.Combine(_baseStorageDir, normalizedSite);
            if (!Directory.Exists(siteDir))
            {
                Directory.CreateDirectory(siteDir);
            }

            var finalPath = Path.Combine(siteDir, $"{snapshotName}.json.gz");
            var watermarkMetaPath = Path.Combine(siteDir, $"{snapshotName}.watermark.txt");

            // 1. Check watermark probe
            string currentWatermark;
            try
            {
                currentWatermark = await probeWatermarkFunc();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Probe failed for {LockKey}, using 2-minute throttled fallback watermark", lockKey);
                // Minute-bucketed watermark prevents hammering the heavy query on every sub-second request when probe has issues
                currentWatermark = $"ERR_FALLBACK_{DateTime.UtcNow:yyyyMMdd_HHmm}";
            }

            // Quick check if file exists and watermark matches in-memory or on-disk
            if (File.Exists(finalPath))
            {
                if (_watermarkCache.TryGetValue(lockKey, out var cachedWatermark) && cachedWatermark == currentWatermark)
                {
                    var fileInfo = new FileInfo(finalPath);
                    var etag = $"\"{fileInfo.LastWriteTimeUtc.Ticks}_{currentWatermark.GetHashCode():X8}\"";
                    return new SnapshotFileResult(finalPath, etag, true, fileInfo.LastWriteTimeUtc);
                }

                if (File.Exists(watermarkMetaPath))
                {
                    var diskWatermark = await File.ReadAllTextAsync(watermarkMetaPath);
                    if (diskWatermark.Trim() == currentWatermark.Trim())
                    {
                        _watermarkCache[lockKey] = currentWatermark;
                        var fileInfo = new FileInfo(finalPath);
                        var etag = $"\"{fileInfo.LastWriteTimeUtc.Ticks}_{currentWatermark.GetHashCode():X8}\"";
                        return new SnapshotFileResult(finalPath, etag, true, fileInfo.LastWriteTimeUtc);
                    }
                }
            }

            // 2. Cache Miss or Dirty: Acquire Site Lock (Protects against 40 simultaneous requests stampede)
            var siteLock = _locks.GetOrAdd(lockKey, _ => new SemaphoreSlim(1, 1));
            await siteLock.WaitAsync();

            try
            {
                // Double-check after acquiring lock in case previous thread already rebuilt it
                if (File.Exists(finalPath) && _watermarkCache.TryGetValue(lockKey, out var recheckedWatermark) && recheckedWatermark == currentWatermark)
                {
                    var fileInfo = new FileInfo(finalPath);
                    var etag = $"\"{fileInfo.LastWriteTimeUtc.Ticks}_{currentWatermark.GetHashCode():X8}\"";
                    return new SnapshotFileResult(finalPath, etag, true, fileInfo.LastWriteTimeUtc);
                }

                _logger.LogInformation("Rebuilding snapshot {SnapshotName} for site {SiteCode} (Watermark: {Watermark})", snapshotName, normalizedSite, currentWatermark);

                var data = await queryDataFunc();

                var tempPath = Path.Combine(siteDir, $"{snapshotName}_{Guid.NewGuid():N}.tmp");
                var tempWatermarkPath = Path.Combine(siteDir, $"{snapshotName}_{Guid.NewGuid():N}.wm.tmp");

                // Write compressed JSON stream
                await using (var fs = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None, 65536, useAsync: true))
                await using (var gzip = new GZipStream(fs, CompressionLevel.Fastest))
                {
                    await JsonSerializer.SerializeAsync(gzip, data, new JsonSerializerOptions
                    {
                        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
                    });
                }

                await File.WriteAllTextAsync(tempWatermarkPath, currentWatermark);

                // Atomic Swap: Windows NTFS guaranteed safe swap without file corruption
                File.Move(tempPath, finalPath, overwrite: true);
                File.Move(tempWatermarkPath, watermarkMetaPath, overwrite: true);

                _watermarkCache[lockKey] = currentWatermark;

                var finalInfo = new FileInfo(finalPath);
                var finalEtag = $"\"{finalInfo.LastWriteTimeUtc.Ticks}_{currentWatermark.GetHashCode():X8}\"";
                return new SnapshotFileResult(finalPath, finalEtag, true, finalInfo.LastWriteTimeUtc);
            }
            finally
            {
                siteLock.Release();
            }
        }

        public Task PrewarmSiteSnapshotsAsync(string siteCode)
        {
            // Optional prewarming hook for background job
            return Task.CompletedTask;
        }
    }
}
