using System.Text.Json;
using Gainer.Core.Coach;
using Gainer.Core.Nutrition;

namespace Gainer.Infrastructure.Nutrition;

/// <summary>Maps OpenAI and payload failures of nutrition AI calls to stable API error codes.</summary>
internal static class NutritionAiErrors
{
    public static async Task<T> MapAsync<T>(
        Func<Task<T>> call,
        string unavailableMessage,
        string invalidResponseMessage)
    {
        try
        {
            return await call();
        }
        catch (OpenAiProviderException exception)
        {
            int status = exception.Code switch
            {
                "provider_rate_limited" => 429,
                "provider_timeout" => 504,
                _ => 503,
            };
            throw new MealEstimationException(exception.Code, unavailableMessage, status, exception);
        }
        catch (Exception exception) when (exception is NutritionValidationException or JsonException)
        {
            throw new MealEstimationException("invalid_provider_response", invalidResponseMessage, 502, exception);
        }
    }
}
