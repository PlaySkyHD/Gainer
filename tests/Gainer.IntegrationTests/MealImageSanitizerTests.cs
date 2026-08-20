using Gainer.Core.Nutrition;
using Gainer.Infrastructure.Nutrition;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Png;
using SixLabors.ImageSharp.Metadata.Profiles.Exif;
using SixLabors.ImageSharp.PixelFormats;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class MealImageSanitizerTests
{
    private static readonly byte[] TinyPng = Convert.FromBase64String(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");

    [TestMethod]
    public async Task ValidImageIsReencodedAndOriginalBufferIsCleared()
    {
        byte[] source = TinyPng.ToArray();
        SanitizedMealImage result = await new MealImageSanitizer().SanitizeAsync(
            new MealImageInput(source, "image/png"));

        Assert.AreEqual("image/jpeg", result.ContentType);
        CollectionAssert.AreEqual(new byte[] { 0xFF, 0xD8 }, result.Bytes[..2]);
        Assert.IsTrue(source.All(value => value == 0));
        Assert.AreEqual(1, result.Width);
        Assert.AreEqual(1, result.Height);
    }

    [TestMethod]
    public async Task MimeMismatchMagicBytesAndSizeAreRejectedAndCleared()
    {
        byte[] mismatch = TinyPng.ToArray();
        MealEstimationException mismatchError = await Assert.ThrowsAsync<MealEstimationException>(() =>
            new MealImageSanitizer().SanitizeAsync(new MealImageInput(mismatch, "image/jpeg")));
        Assert.AreEqual("image_type_mismatch", mismatchError.Code);
        Assert.IsTrue(mismatch.All(value => value == 0));

        byte[] invalid = [1, 2, 3, 4];
        MealEstimationException invalidError = await Assert.ThrowsAsync<MealEstimationException>(() =>
            new MealImageSanitizer().SanitizeAsync(new MealImageInput(invalid, "image/jpeg")));
        Assert.AreEqual("invalid_image", invalidError.Code);
        Assert.IsTrue(invalid.All(value => value == 0));

        byte[] oversized = new byte[MealImageSanitizer.MaximumBytes + 1];
        MealEstimationException sizeError = await Assert.ThrowsAsync<MealEstimationException>(() =>
            new MealImageSanitizer().SanitizeAsync(new MealImageInput(oversized, "image/jpeg")));
        Assert.AreEqual("invalid_image_size", sizeError.Code);
    }

    [TestMethod]
    public async Task DimensionsAreRejectedBeforeDecodeAndMetadataIsRemoved()
    {
        byte[] tooWide;
        using (var image = new Image<Rgba32>(MealImageSanitizer.MaximumDimension + 1, 1))
        await using (var output = new MemoryStream())
        {
            await image.SaveAsync(output, new PngEncoder());
            tooWide = output.ToArray();
        }
        MealEstimationException dimensions = await Assert.ThrowsAsync<MealEstimationException>(() =>
            new MealImageSanitizer().SanitizeAsync(new MealImageInput(tooWide, "image/png")));
        Assert.AreEqual("invalid_image_dimensions", dimensions.Code);
        Assert.IsTrue(tooWide.All(value => value == 0));

        byte[] withMetadata;
        using (var image = new Image<Rgba32>(2, 2))
        await using (var output = new MemoryStream())
        {
            image.Metadata.ExifProfile = new ExifProfile();
            image.Metadata.ExifProfile.SetValue(ExifTag.ImageDescription, "private meal note");
            await image.SaveAsync(output, new PngEncoder());
            withMetadata = output.ToArray();
        }
        SanitizedMealImage sanitized = await new MealImageSanitizer().SanitizeAsync(
            new MealImageInput(withMetadata, "image/png"));
        using Image decoded = Image.Load(sanitized.Bytes);
        Assert.IsTrue(decoded.Metadata.ExifProfile is null || decoded.Metadata.ExifProfile.Values.Count == 0);
    }
}
