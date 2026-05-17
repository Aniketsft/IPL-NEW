using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Internal;

using Microsoft.Extensions.Options;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class DelInvoiceRepository : IDelInvoiceRepository
    {
        private readonly ISqlDataAccess _sql;
        private readonly SyncSettings _syncSettings;

        public DelInvoiceRepository(ISqlDataAccess sqlDataAccess, IOptions<SyncSettings> syncSettings)
        {
            _sql = sqlDataAccess;
            _syncSettings = syncSettings.Value;
        }

        public async Task<List<InvoiceRowDto>> GetAllInvoices()
        {
            var query =
                $@"select a.ROWID,
                 b.SALFCY_0,
                 a.SALPRITYP_0,
                 a.NUM_0,
                 a.INVTYP_0,
                 c.INVREF_0,
                 a.ACCDAT_0,
                 b.BPCINV_0,
                 a.CUR_0,
                 c.REP_0,
                 c.SIHORINUM_0,
                 c.SIHORI_0,
                 c.STOMVTFLG_0,
                 c.STOFCY_0,
                 c.INVDTAAMT_0,
                 c.INVDTAAMT_1
          from  {_syncSettings.X3DatabaseName}.INLPROD.SINVOICE as a
          inner join {_syncSettings.X3DatabaseName}.INLPROD.SINVOICED as b on a.NUM_0 = b.NUM_0
          inner join {_syncSettings.X3DatabaseName}.INLPROD.SINVOICEV as c on a.NUM_0 = c.NUM_0
          order by a.ACCDAT_0";

            var result = await _sql.LoadDataRaw<InvoiceRowDto, dynamic>(query, new { }, "Innodis");
            return result?.ToList() ?? new List<InvoiceRowDto>();
        }
    }
}
