using System.Text.Json;
using Gainer.Api.Composition;
using Gainer.Api.Security;
using Gainer.Contracts.Sync;
using Gainer.Core.BodyTracking;
using Gainer.Core.Security;
using Gainer.Core.Sync;
using Gainer.Core.Training;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.Api.Controllers;

[ApiController]
[Authorize]
[Route(ApiConstants.Version1Route + "/sync/mutations")]
[ResponseCache(Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class SyncMutationsController(ISyncMutationProcessor processor, IUserContext userContext) : ControllerBase
{
    [HttpPut("{mutationId:guid}")]
    [ProducesResponseType<PushMutationResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
    public async Task<ActionResult<PushMutationResponse>> Push(
        Guid mutationId,
        PushMutationRequest request,
        CancellationToken cancellationToken)
    {
        if (SyncAccountIdentityGuard.Validate(Request.Headers, userContext) is { } identityProblem)
            return identityProblem;

        if (mutationId == Guid.Empty)
        {
            return SyncProblem(StatusCodes.Status422UnprocessableEntity, "invalid_mutation_id", "Mutation id is required.");
        }
        try
        {
            var content = new CanonicalMutationContent(
                request.ProtocolVersion,
                request.ClientId,
                request.ClientSequence,
                request.Operation,
                request.Resources.Select(item => new CanonicalResourceVersion(
                    item.ResourceType, item.ResourceId, item.BaseVersion)).ToList(),
                request.DependsOnMutationId,
                request.Payload);
            ProcessedSyncMutationResult result = await processor.ProcessAsync(
                new ProcessSyncMutationCommand(mutationId, content), cancellationToken);
            return Ok(new PushMutationResponse(
                result.MutationId,
                result.Replayed,
                result.Revision,
                result.Changes.Select(ToResponse).ToList()));
        }
        catch (SyncMutationConflictException exception)
        {
            return SyncProblem(StatusCodes.Status409Conflict, exception.Code, exception.Message);
        }
        catch (SyncMutationValidationException exception)
        {
            return SyncProblem(StatusCodes.Status422UnprocessableEntity, exception.Code, exception.Message);
        }
        catch (DailyCheckInValidationException exception)
        {
            return SyncProblem(StatusCodes.Status422UnprocessableEntity, "validation_failed", exception.Message);
        }
        catch (CustomExerciseValidationException exception)
        {
            return SyncProblem(StatusCodes.Status422UnprocessableEntity, "validation_failed", exception.Message);
        }
        catch (Exception exception) when (exception is BodyGoalValidationException
                                          or WorkoutTemplateValidationException
                                          or WorkoutRotationValidationException
                                          or WorkoutValidationException)
        {
            return SyncProblem(StatusCodes.Status422UnprocessableEntity, "validation_failed", exception.Message);
        }
        catch (Exception exception) when (exception is DailyCheckInConflictException
                                          or DailyCheckInNotFoundException
                                          or CustomExerciseConflictException
                                          or CustomExerciseNotFoundException
                                          or BodyGoalConflictException
                                          or WorkoutTemplateConflictException
                                          or WorkoutTemplateNotFoundException
                                          or WorkoutRotationConflictException
                                          or WorkoutRotationNotFoundException
                                          or WorkoutConflictException
                                          or WorkoutNotFoundException)
        {
            return SyncProblem(StatusCodes.Status409Conflict, "resource_conflict", "The resource changed or is unavailable.");
        }
    }

    private ObjectResult SyncProblem(int status, string code, string title)
    {
        var problem = new ProblemDetails
        {
            Status = status,
            Title = title,
            Type = $"https://gainer.local/problems/{code}",
        };
        problem.Extensions["code"] = code;
        return StatusCode(status, problem);
    }

    private static SyncResourceResult ToResponse(ExecutedSyncChange change)
    {
        JsonElement? snapshot = change.IsTombstone ? null : change.Snapshot switch
        {
            JsonElement element => element.Clone(),
            _ => JsonSerializer.SerializeToElement(change.Snapshot, new JsonSerializerOptions(JsonSerializerDefaults.Web)),
        };
        return new SyncResourceResult(
            change.Resource.Kind.ToString(),
            change.Resource.ResourceId,
            change.Version,
            snapshot,
            change.IsTombstone);
    }
}
