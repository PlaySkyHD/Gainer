using Gainer.Core.Nutrition;
using Gainer.Infrastructure.Nutrition;
using SkiaSharp;
using System.Text;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class MealImageSanitizerTests
{
    private static readonly byte[] TinyPng = Convert.FromBase64String(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=");

    [TestMethod]
    public async Task ValidImageIsReencodedAndOriginalBufferIsCleared()
    {
        foreach ((SKEncodedImageFormat format, string contentType) in new[]
        {
            (SKEncodedImageFormat.Jpeg, "image/jpeg"),
            (SKEncodedImageFormat.Png, "image/png"),
            (SKEncodedImageFormat.Webp, "image/webp"),
        })
        {
            byte[] source = CreateImage(format, 3, 2);
            SanitizedMealImage result = await new MealImageSanitizer().SanitizeAsync(new MealImageInput(source, contentType));

            Assert.AreEqual("image/jpeg", result.ContentType);
            CollectionAssert.AreEqual(new byte[] { 0xFF, 0xD8 }, result.Bytes[..2]);
            Assert.IsTrue(source.All(value => value == 0));
            Assert.AreEqual(3, result.Width);
            Assert.AreEqual(2, result.Height);
            using var outputStream = new MemoryStream(result.Bytes, writable: false);
            using SKCodec? decoded = SKCodec.Create(outputStream);
            Assert.IsNotNull(decoded);
            Assert.AreEqual(SKEncodedImageFormat.Jpeg, decoded.EncodedFormat);
        }
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
        Assert.IsTrue(oversized.All(value => value == 0));
    }

    [TestMethod]
    public async Task DimensionsAreRejectedBeforeDecodeAndMetadataIsRemoved()
    {
        byte[] tooWide = CreateImage(SKEncodedImageFormat.Png, MealImageSanitizer.MaximumDimension + 1, 1);
        MealEstimationException dimensions = await Assert.ThrowsAsync<MealEstimationException>(() =>
            new MealImageSanitizer().SanitizeAsync(new MealImageInput(tooWide, "image/png")));
        Assert.AreEqual("invalid_image_dimensions", dimensions.Code);
        Assert.IsTrue(tooWide.All(value => value == 0));

        byte[] withMetadata = AddExifDescription(CreateImage(SKEncodedImageFormat.Jpeg, 2, 2), "private meal note");
        SanitizedMealImage sanitized = await new MealImageSanitizer().SanitizeAsync(
            new MealImageInput(withMetadata, "image/jpeg"));
        Assert.IsFalse(Encoding.ASCII.GetString(sanitized.Bytes).Contains("private meal note", StringComparison.Ordinal));
    }

    private static byte[] CreateImage(SKEncodedImageFormat format, int width, int height)
    {
        using var surface = SKSurface.Create(new SKImageInfo(width, height, SKColorType.Rgba8888, SKAlphaType.Premul));
        Assert.IsNotNull(surface);
        surface.Canvas.Clear(new SKColor(40, 100, 180, 255));
        using SKImage image = surface.Snapshot();
        using SKData encoded = image.Encode(format, 85);
        return encoded.ToArray();
    }

    private static byte[] AddExifDescription(byte[] jpeg, string value)
    {
        byte[] description = Encoding.ASCII.GetBytes(value + "\0");
        using var tiff = new MemoryStream();
        using (var writer = new BinaryWriter(tiff, Encoding.ASCII, leaveOpen: true))
        {
            writer.Write((byte)'I');
            writer.Write((byte)'I');
            writer.Write((ushort)42);
            writer.Write((uint)8);
            writer.Write((ushort)1);
            writer.Write((ushort)0x010E); // ImageDescription
            writer.Write((ushort)2); // ASCII
            writer.Write((uint)description.Length);
            writer.Write((uint)26); // IFD0 header + one entry + next-IFD pointer
            writer.Write((uint)0);
            writer.Write(description);
        }

        byte[] payload = [.. Encoding.ASCII.GetBytes("Exif\0\0"), .. tiff.ToArray()];
        int segmentLength = payload.Length + 2;
        byte[] result = new byte[jpeg.Length + payload.Length + 4];
        result[0] = 0xFF;
        result[1] = 0xD8;
        result[2] = 0xFF;
        result[3] = 0xE1;
        result[4] = (byte)(segmentLength >> 8);
        result[5] = (byte)segmentLength;
        payload.CopyTo(result, 6);
        jpeg.AsSpan(2).CopyTo(result.AsSpan(6 + payload.Length));
        return result;
    }
}
