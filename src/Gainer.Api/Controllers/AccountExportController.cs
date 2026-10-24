using System.Globalization;
using Gainer.Api.Composition;
using Gainer.Contracts.Sync;
using Gainer.Core.Sync;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[EnableRateLimiting(ApiConstants.AccountExportRateLimitPolicy)]
[Route(ApiConstants.Version1Route + "/account/export")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class AccountExportController(IAccountDataExport export, TimeProvider timeProvider) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType<AccountExportResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status429TooManyRequests)]
    public async Task<ActionResult<AccountExportResponse>> Get(CancellationToken cancellationToken)
    {
        DateTimeOffset now = timeProvider.GetUtcNow();
        AccountDataExport data = await export.ExportAsync(cancellationToken);
        string fileName = $"gainer-export-{now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)}.json";
        Response.Headers.ContentDisposition = $"attachment; filename=\"{fileName}\"";
        return Ok(new AccountExportResponse(
            AccountExportFormat.Name,
            AccountExportFormat.SchemaVersion,
            SyncProtocol.CurrentVersion,
            now,
            data.AsOfRevision,
            data.Resources.Select(item => new AccountExportResourceResponse(
                item.ResourceType,
                item.ResourceId,
                item.Version,
                item.Snapshot)).ToList()));
    }
}
