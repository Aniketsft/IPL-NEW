using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;
using System.Xml.XPath;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using System.Text.Json;

namespace EnterpriseAuth.Api.Core.Application.Services
{
    public class SageX3SoapService : ISageX3SoapService
    {
        private readonly ScanProductionDbContext _context;
        private readonly HttpClient _httpClient;
        private readonly string _soapUrl;
        private readonly string _poolAlias;
        private readonly string _username;
        private readonly string _password;

        public SageX3SoapService(ScanProductionDbContext context, IConfiguration configuration, IHttpClientFactory httpClientFactory)
        {
            _context = context;
            _httpClient = httpClientFactory.CreateClient();
            
            var settings = configuration.GetSection("X3SoapService");
            _soapUrl = settings["Url"] ?? "http://192.168.120.6:8124/soap-generic/syracuse/collaboration/syracuse/CAdxWebServiceXmlCC";
            _poolAlias = settings["PoolAlias"] ?? "IMPORT-EXPORT";
            _username = settings["Username"] ?? "ADMIN";
            _password = settings["Password"] ?? "PASSWORD_HERE";
        }

        public async Task<EndOfDayResult> ProcessEndOfDayAsync()
        {
            var result = new EndOfDayResult();

            // 1. Fetch only pending (non-processed) records from Staging
            var allRecords = await _context.StagingRecords
                .Where(r => !r.IsProcessed)
                .ToListAsync();

            if (!allRecords.Any())
            {
                return result;
            }

            // 2. Group by SO Number
            var groups = allRecords.GroupBy(r => r.ZSOHNUM_0).ToList();
            result.TotalProcessed = groups.Count;

            foreach (var group in groups)
            {
                var importResult = await ImportSalesOrderAsync(group.Key ?? "Unknown", group.ToList());
                result.Results.Add(importResult);

                if (importResult.Success)
                {
                    result.SuccessCount++;
                    
                    // Mark staging records as processed
                    foreach (var record in group)
                    {
                        record.IsProcessed = true;
                        record.ZVACITM_0 = importResult.RequestNumber; // Store X3 request number (field repurposed from ZREQNUM_0)
                    }

                    // Also mark the normalized SalesOrder as processed
                    var normalizedOrder = await _context.SalesOrders
                        .FirstOrDefaultAsync(o => o.SourceOrderId == group.Key);
                    if (normalizedOrder != null)
                    {
                        normalizedOrder.IsProcessed = true;
                        normalizedOrder.UpdatedAt = DateTime.UtcNow;
                    }
                }
                else
                {
                    result.FailureCount++;
                }
            }

            await _context.SaveChangesAsync();
            return result;
        }

        public async Task<X3ImportResult> ImportSalesOrderAsync(string soNumber, List<Staging> records)
        {
            var result = new X3ImportResult { Identifier = soNumber };

            try
            {
                // 1. Find the Header record (H) and Lines (L)
                var header = records.FirstOrDefault(r => r.ZREC_0 == "H");
                var lines = records.Where(r => r.ZREC_0 == "L").ToList();

                if (header == null)
                {
                    header = records.FirstOrDefault();
                }

                // 2. Build the I_FILE content
                var fileBuilder = new StringBuilder();
                
                string shiDate = header?.ZSHIDAT_0?.ToString("yyyyMMdd") ?? "";
                string delDate = header?.ZDLVDAT_0?.ToString("yyyyMMdd") ?? "";

                // Header Record: H;Template;Site1;Site2;;Customer;Currency;ShiDate;DelDate;Flag;Lorry;Location
                fileBuilder.Append($"H;{header?.ZSDHTYP_0};{header?.ZSALFCY_0};{header?.ZSTOFCY_0};;{header?.ZBPCORD_0};{header?.ZSUR_0};{shiDate};{delDate};{header?.ZCFMFLG_0};{header?.ZLOCFCY_0};{header?.ZLOC_0}|");

                // Line Records: L;SONo;LineNo;ItemCode;Description;Unit;Qty;VatCode
                foreach (var line in lines)
                {
                    string qty = line.ZQTY_0.ToString("F3"); // 3 decimal places
                    fileBuilder.Append($"L;{line.ZSOHNUM_0};{line.ZSOPLIN_0};{line.ZITMREF_0};{line.ZITMDES_0};{line.ZSAU_0};{qty};{line.ZVACITM_0}|");
                }

                fileBuilder.Append("END");

                // 3. Construct the JSON for the CDATA block
                var jsonPayload = new
                {
                    GRP1 = new
                    {
                        I_MODIMP = "ZSDH2",
                        I_AOWSTA = "YES",
                        I_EXEC = "REALTIME",
                        I_RECORDSEP = "|",
                        I_FILE = fileBuilder.ToString()
                    }
                };

                string inputXmlJson = JsonSerializer.Serialize(jsonPayload);

                // 4. Construct the SOAP Envelope
                string soapEnvelope = $@"<soapenv:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns:xsd=""http://www.w3.org/2001/XMLSchema"" xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:wss=""http://www.adonix.com/WSS"">
   <soapenv:Header/>
   <soapenv:Body>
      <wss:run soapenv:encodingStyle=""http://schemas.xmlsoap.org/soap/encoding/"">
         <callContext xsi:type=""wss:CAdxCallContext"">
            <codeLang xsi:type=""xsd:string"">ENG</codeLang>
            <poolAlias xsi:type=""xsd:string"">{_poolAlias}</poolAlias>
            <poolId xsi:type=""xsd:string""></poolId>
            <requestConfig xsi:type=""xsd:string""></requestConfig>
         </callContext>
         <publicName xsi:type=""xsd:string"">AOWSIMPORT</publicName>
           <inputXml xsi:type=""xsd:string"">
                 <![CDATA[{inputXmlJson}]]>
         </inputXml>
      </wss:run>
   </soapenv:Body>
</soapenv:Envelope>";

                // 5. Send Request
                Console.WriteLine("====== SAGE X3 SOAP REQUEST ======");
                Console.WriteLine(soapEnvelope);
                Console.WriteLine("==================================");

                var request = new HttpRequestMessage(HttpMethod.Post, _soapUrl);
                request.Content = new StringContent(soapEnvelope, Encoding.UTF8, "text/xml");
                
                // Set Basic Authentication
                var authToken = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_username}:{_password}"));
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authToken);

                // Syracuse can be picky about SOAPAction casing
                request.Headers.Add("SOAPAction", "");
                request.Headers.Add("soapAction", ""); 

                var response = await _httpClient.SendAsync(request);
                string responseXml = await response.Content.ReadAsStringAsync();

                if (!response.IsSuccessStatusCode)
                {
                    result.Success = false;
                    result.TechnicalError = $"HTTP {response.StatusCode}: {responseXml}";
                    return result;
                }

                // 6. Parse Response
                return ParseSoapResponse(responseXml, result);
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.TechnicalError = ex.Message;
                return result;
            }
        }

        private X3ImportResult ParseSoapResponse(string xml, X3ImportResult result)
        {
            try
            {
                var doc = XDocument.Parse(xml);
                
                // 1. Result JSON extraction (optional detail)
                var resultNode = doc.Descendants("resultXml").FirstOrDefault();
                if (resultNode != null && !string.IsNullOrEmpty(resultNode.Value))
                {
                    try 
                    {
                        using var jsonDoc = JsonDocument.Parse(resultNode.Value);
                        if (jsonDoc.RootElement.TryGetProperty("GRP1", out var grp1))
                        {
                            if (grp1.TryGetProperty("O_REQNUM", out var reqNum))
                                result.RequestNumber = reqNum.GetString();
                        }
                    }
                    catch { /* Ignore JSON parse errors in resultXml */ }
                }

                // 2. Global Status in the XML: 1 = Success, 0 = Error
                var statusNode = doc.Descendants("status").FirstOrDefault();
                result.Success = statusNode?.Value == "1";

                // 3. Extract all messages from multiRef blocks
                var messages = doc.Descendants().Where(d => d.Name.LocalName == "message").Select(m => m.Value).ToList();
                result.Messages.AddRange(messages);

                return result;
            }
            catch (Exception ex)
            {
                result.TechnicalError = "Response Parsing Error: " + ex.Message;
                return result;
            }
        }
    }
}
