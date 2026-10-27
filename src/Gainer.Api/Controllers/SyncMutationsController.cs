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
    private static readonly JsonSerializerOptions WebJsonOptions = new(JsonSerializerDefaults.Web);

    [HttpPut("{mutationId:guid}")]
    [ProducesResponseType<PushMutationResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
    public async Task<ActionResult<PushMutationResponse>> Push(
        Guid mutationId,
        PushMutationRequest request,
        CancellationToken cancellationToken)
    {
        if (SyncAccountIdentityGuard.Validate(HttpContext, userContext, request.ProtocolVersion) is { } identityProblem)
            return identityProblem;

        if (mutationId == Guid.Empty)
        {
            return SyncProblem(StatusCodes.Status422UnprocessableEntity, "invalid_mutation_id", "Mutation id is required.");
        }
        try
        {
            ProcessedSyncMutationResult result = await processor.ProcessAsync(
                new ProcessSyncMutationCommand(mutationId, ToContent(request)), cancellationToken);
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
            return SyncValidationProblem(exception.Message, exception.Errors);
        }
        catch (ExerciseCategoryValidationException exception)
        {
            return SyncValidationProblem(exception.Message, exception.Errors);
        }
        catch (WorkoutValidationException exception)
        {
            return SyncValidationProblem(exception.Message, exception.Errors);
        }
        catch (CardioSessionValidationException exception)
        {
            return SyncValidationProblem(exception.Message, exception.Errors);
        }
        catch (TrainingPlanValidationException exception)
        {
            return SyncValidationProblem(exception.Message, exception.Errors);
        }
        catch (TrainingScheduleValidationException exception)
        {
            return SyncValidationProblem(exception.Message, exception.Errors);
        }
        catch (Exception exception) when (exception is BodyGoalValidationException)
        {
            return SyncProblem(StatusCodes.Status422UnprocessableEntity, "validation_failed", exception.Message);
        }
        catch (ActiveWorkoutExistsException)
        {
            return SyncProblem(StatusCodes.Status409Conflict, "active_workout_exists", "The user already has an active workout.");
        }
        catch (Exception exception) when (exception is DailyCheckInConflictException
                                          or DailyCheckInNotFoundException
                                          or CustomExerciseConflictException
                                          or CustomExerciseNotFoundException
                                          or ExerciseCategoryConflictException
                                          or ExerciseCategoryNotFoundException
                                          or BodyGoalConflictException
                                          or TrainingPlanConflictException
                                          or TrainingPlanNotFoundException
                                          or TrainingScheduleConflictException
                                          or TrainingScheduleNotFoundException
                                          or WorkoutConflictException
                                          or WorkoutNotFoundException
                                          or CardioSessionConflictException
                                          or CardioSessionNotFoundException)
        {
            return SyncProblem(StatusCodes.Status409Conflict, "resource_conflict", "The resource changed or is unavailable.");
        }
    }

    // A missing list or null entries pass through unchanged; the processor rejects them as invalid_resources.
    private static CanonicalMutationContent ToContent(PushMutationRequest request) => new(
        request.ProtocolVersion,
        request.ClientId,
        request.ClientSequence,
        request.Operation,
        request.Resources?.Select(ToResourceVersion).ToList()!,
        request.DependsOnMutationId,
        request.Payload);

    private static CanonicalResourceVersion ToResourceVersion(ResourceVersionRequest? item) =>
        item is null ? null! : new CanonicalResourceVersion(item.ResourceType, item.ResourceId, item.BaseVersion);

    private ObjectResult SyncProblem(int status, string code, string title) =>
        SyncProblemResults.Create(HttpContext, status, code, title);

    private ObjectResult SyncValidationProblem(string title, IReadOnlyDictionary<string, string> errors)
    {
        ObjectResult result = SyncProblem(StatusCodes.Status422UnprocessableEntity, "validation_failed", title);
        ((ProblemDetails)result.Value!).Extensions["errors"] = errors;
        return result;
    }

    private static SyncResourceResult ToResponse(ExecutedSyncChange change)
    {
        JsonElement? snapshot = change.IsTombstone ? null : change.Snapshot switch
        {
            JsonElement element => element.Clone(),
            _ => JsonSerializer.SerializeToElement(change.Snapshot, WebJsonOptions),
        };
        return new SyncResourceResult(
            change.Resource.Kind.ToString(),
            change.Resource.ResourceId,
            change.Version,
            snapshot,
            change.IsTombstone);
    }
}
