using Gainer.Core.Nutrition;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats;
using SixLabors.ImageSharp.Formats.Jpeg;
using Microsoft.Extensions.Options;

namespace Gainer.Infrastructure.Nutrition;

public sealed class MealImageOptions
{
    public const string SectionName = "MealImages";
    public int MaximumBytes { get; set; } = MealImageSanitizer.MaximumBytes;
    public int MaximumDimension { get; set; } = MealImageSanitizer.MaximumDimension;
    public long MaximumPixels { get; set; } = MealImageSanitizer.MaximumPixels;
    public int JpegQuality { get; set; } = 82;
}

public sealed class MealImageSanitizer(IOptions<MealImageOptions>? options = null) : IMealImageSanitizer
{
    public const int MaximumBytes = 8 * 1024 * 1024;
    public const int MaximumDimension = 4_096;
    public const long MaximumPixels = 16_000_000;
    private readonly MealImageOptions settings = Validate(options?.Value ?? new MealImageOptions());

    public async Task<SanitizedMealImage> SanitizeAsync(
        MealImageInput input,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(input);
        byte[] source = input.Bytes ?? throw new MealEstimationException("invalid_image", "The image is missing.");
        if (source.Length == 0 || source.Length > settings.MaximumBytes)
            throw new MealEstimationException("invalid_image_size", $"The image must be no larger than {settings.MaximumBytes} bytes.");

        try
        {
            IImageFormat format;
            ImageInfo info;
            try
            {
                format = Image.DetectFormat(source);
                info = Image.Identify(source);
            }
            catch (UnknownImageFormatException exception)
            {
                throw new MealEstimationException("invalid_image", "The file is not a supported image.", innerException: exception);
            }
            catch (InvalidImageContentException exception)
            {
                throw new MealEstimationException("invalid_image", "The image content is invalid.", innerException: exception);
            }

            string expectedContentType = format.Name switch
            {
                "JPEG" => "image/jpeg",
                "PNG" => "image/png",
                "WEBP" => "image/webp",
                _ => throw new MealEstimationException("unsupported_image_format", "Only JPEG, PNG and WebP images are supported."),
            };
            if (!string.Equals(NormalizeContentType(input.ContentType), expectedContentType, StringComparison.Ordinal))
                throw new MealEstimationException("image_type_mismatch", "The declared image type does not match its content.");
            if (info.Width < 1 || info.Width > settings.MaximumDimension || info.Height < 1 || info.Height > settings.MaximumDimension ||
                (long)info.Width * info.Height > settings.MaximumPixels)
                throw new MealEstimationException("invalid_image_dimensions", "The image dimensions exceed the allowed limit.");

            await using var inputStream = new MemoryStream(source, writable: false);
            using Image image = await Image.LoadAsync(inputStream, cancellationToken);
            image.Metadata.ExifProfile = null;
            image.Metadata.IccProfile = null;
            image.Metadata.XmpProfile = null;
            await using var output = new MemoryStream();
            await image.SaveAsJpegAsync(output, new JpegEncoder { Quality = settings.JpegQuality }, cancellationToken);
            return new SanitizedMealImage(output.ToArray(), "image/jpeg", image.Width, image.Height);
        }
        finally
        {
            Array.Clear(source);
        }
    }

    private static string NormalizeContentType(string contentType) =>
        contentType.Trim().ToLowerInvariant() switch
        {
            "image/jpg" => "image/jpeg",
            string value => value,
        };

    private static MealImageOptions Validate(MealImageOptions value)
    {
        if (value.MaximumBytes is < 100_000 or > 20 * 1024 * 1024) throw new InvalidOperationException("Meal image byte limit is invalid.");
        if (value.MaximumDimension is < 256 or > 8_192) throw new InvalidOperationException("Meal image dimension limit is invalid.");
        if (value.MaximumPixels is < 65_536 or > 40_000_000) throw new InvalidOperationException("Meal image pixel limit is invalid.");
        if (value.JpegQuality is < 50 or > 95) throw new InvalidOperationException("Meal image JPEG quality is invalid.");
        return value;
    }
}
