namespace Gainer.Core.Nutrition;

public sealed record MealImageInput(byte[] Bytes, string ContentType);

public sealed record SanitizedMealImage(byte[] Bytes, string ContentType, int Width, int Height);

public sealed record MealEstimationInput(string? Text, MealImageInput? Image, bool ImageConsent)
{
    public static MealEstimationInput Create(string? text, MealImageInput? image, bool imageConsent)
    {
        string? normalized = string.IsNullOrWhiteSpace(text) ? null : text.Trim();
        if (normalized?.Length > 2_000)
            throw new MealEstimationException("invalid_input", "Meal description must not exceed 2000 characters.");
        if (normalized is null && image is null)
            throw new MealEstimationException("invalid_input", "Text or an image is required.");
        if (image is not null && !imageConsent)
            throw new MealEstimationException("image_consent_required", "Image analysis requires explicit consent.");
        return new MealEstimationInput(normalized, image, imageConsent);
    }
}

public interface IMealImageSanitizer
{
    Task<SanitizedMealImage> SanitizeAsync(MealImageInput image, CancellationToken cancellationToken = default);
}

public interface IMealEstimator
{
    Task<MealEstimateDraft> EstimateAsync(MealEstimationInput input, CancellationToken cancellationToken = default);
}

public sealed class MealEstimationException(
    string code,
    string message,
    int statusCode = 400,
    Exception? innerException = null) : Exception(message, innerException)
{
    public string Code { get; } = code;
    public int StatusCode { get; } = statusCode;
}
