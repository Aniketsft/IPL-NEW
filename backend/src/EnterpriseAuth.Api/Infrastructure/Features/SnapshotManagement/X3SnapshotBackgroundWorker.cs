using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace EnterpriseAuth.Api.Infrastructure.Features.SnapshotManagement
{
    public class X3SnapshotBackgroundWorker : BackgroundService
    {
        private readonly IServiceScopeFactory _scopeFactory;
        private readonly ILogger<X3SnapshotBackgroundWorker> _logger;
        private readonly TimeSpan _cycleInterval = TimeSpan.FromMinutes(2);

        public X3SnapshotBackgroundWorker(
            IServiceScopeFactory scopeFactory,
            ILogger<X3SnapshotBackgroundWorker> logger)
        {
            _scopeFactory = scopeFactory;
            _logger = logger;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("X3SnapshotBackgroundWorker initialized with 2-minute cycle.");

            // 1. Initial pre-warm run on startup
            try
            {
                await SweepAndRefreshSnapshotsAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Initial snapshot pre-warm experienced a non-fatal error.");
            }

            // 2. Periodic 2-minute timer loop
            using var timer = new PeriodicTimer(_cycleInterval);
            while (!stoppingToken.IsCancellationRequested && await timer.WaitForNextTickAsync(stoppingToken))
            {
                try
                {
                    await SweepAndRefreshSnapshotsAsync(stoppingToken);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error occurred during 2-minute X3 snapshot background sweep.");
                }
            }
        }

        private async Task SweepAndRefreshSnapshotsAsync(CancellationToken stoppingToken)
        {
            using var scope = _scopeFactory.CreateScope();
            var repo = scope.ServiceProvider.GetRequiredService<ISalesInvoiceRepository>();
            var snapshotService = scope.ServiceProvider.GetRequiredService<ISnapshotService>();
            var sitesRepo = scope.ServiceProvider.GetService<ISitesRepository>();

            // Discover active sites, fallback to standard sites if repository is unavailable
            var activeSites = new[] { "POD", "VAL", "PIS", "PLM" };
            if (sitesRepo != null)
            {
                try
                {
                    var dbSites = await sitesRepo.GetSitesAsync();
                    if (dbSites != null && dbSites.Any())
                    {
                        activeSites = dbSites
                            .Where(s => !string.IsNullOrWhiteSpace(s.SiteCode))
                            .Select(s => s.SiteCode.Trim().ToUpperInvariant())
                            .Distinct()
                            .ToArray();
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Unable to query active sites from database, falling back to default site list.");
                }
            }

            foreach (var site in activeSites)
            {
                if (stoppingToken.IsCancellationRequested) break;

                // Sweep Invoices & Credit Notes
                try
                {
                    await snapshotService.GetOrUpdateSnapshotAsync(
                        site,
                        "x3_history",
                        () => repo.GetX3HistoryWatermarkAsync(site, 6),
                        () => repo.GetX3HistoryAsync(site, null, 6)
                    );
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Background sweep for x3_history at site {Site} failed", site);
                }

                // Sweep Open Invoices & Debt
                try
                {
                    await snapshotService.GetOrUpdateSnapshotAsync(
                        site,
                        "open_invoices",
                        () => repo.GetOpenInvoicesWatermarkAsync(site, 0),
                        () => repo.GetOpenInvoicesAsync(site, null, 0)
                    );
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Background sweep for open_invoices at site {Site} failed", site);
                }

                // Sweep Stock Levels
                try
                {
                    await snapshotService.GetOrUpdateSnapshotAsync(
                        site,
                        "stock_details",
                        () => repo.GetStockWatermarkAsync(site),
                        () => repo.GetItemStockDetailsAsync(site)
                    );
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Background sweep for stock_details at site {Site} failed", site);
                }

                // Small jitter delay between sites to avoid spiking DB CPU
                await Task.Delay(1000, stoppingToken);
            }
        }
    }
}
