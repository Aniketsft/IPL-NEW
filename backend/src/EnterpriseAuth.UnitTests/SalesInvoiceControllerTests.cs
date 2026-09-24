using System;
using System.Collections.Generic;
using System.Security.Claims;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Controllers;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Moq;
using Xunit;

namespace EnterpriseAuth.UnitTests
{
    public class SalesInvoiceControllerTests
    {
        private readonly Mock<ISalesInvoiceRepository> _repoMock;
        private readonly Mock<ISageX3SoapService> _soapMock;
        private readonly ScanProductionDbContext _dbContext;

        public SalesInvoiceControllerTests()
        {
            _repoMock = new Mock<ISalesInvoiceRepository>();
            _soapMock = new Mock<ISageX3SoapService>();

            var options = new DbContextOptionsBuilder<ScanProductionDbContext>()
                .UseInMemoryDatabase(databaseName: "TestSalesInvoiceDb_" + Guid.NewGuid())
                .Options;
            _dbContext = new ScanProductionDbContext(options);
        }

        private SalesInvoiceController CreateControllerWithUser(string? siteClaim = null)
        {
            var controller = new SalesInvoiceController(_repoMock.Object, _dbContext, _soapMock.Object);

            var claims = new List<Claim>();
            if (siteClaim != null)
            {
                claims.Add(new Claim("SiteCode", siteClaim));
            }

            var identity = new ClaimsIdentity(claims, "TestAuth");
            var user = new ClaimsPrincipal(identity);

            controller.ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext { User = user }
            };

            return controller;
        }

        [Fact]
        public async Task GetItemStockDetails_WithNoQueryParam_UsesUserSiteClaim()
        {
            // Arrange
            var controller = CreateControllerWithUser("IPL");
            _repoMock.Setup(r => r.GetItemStockDetailsAsync("IPL"))
                .ReturnsAsync(new List<SalesInvoiceItemStockDto>());

            // Act
            var result = await controller.GetItemStockDetails(null);

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            _repoMock.Verify(r => r.GetItemStockDetailsAsync("IPL"), Times.Once);
        }

        [Fact]
        public async Task GetItemStockDetails_WithQueryParam_UsesQueryParamWhenUserHasAll()
        {
            // Arrange
            var controller = CreateControllerWithUser("ALL");
            _repoMock.Setup(r => r.GetItemStockDetailsAsync("SCG"))
                .ReturnsAsync(new List<SalesInvoiceItemStockDto>());

            // Act
            var result = await controller.GetItemStockDetails("SCG");

            // Assert
            var okResult = Assert.IsType<OkObjectResult>(result);
            _repoMock.Verify(r => r.GetItemStockDetailsAsync("SCG"), Times.Once);
        }

        [Fact]
        public async Task GetItemStockDetails_WithNoParamAndNoClaim_ReturnsBadRequest()
        {
            // Arrange
            var controller = CreateControllerWithUser(null);

            // Act
            var result = await controller.GetItemStockDetails(null);

            // Assert
            Assert.IsType<BadRequestObjectResult>(result);
        }
    }
}
