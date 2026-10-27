using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.OpenApi;

namespace Gainer.Api.Composition;

/// <summary>Corrects the generated OpenAPI contract where reflection alone describes the API wrongly.</summary>
internal static class GainerOpenApiTransformers
{
    private const string BearerSchemeName = "Bearer";
    private const string MultipartMediaType = "multipart/form-data";
    private const string MealEstimatesPath = "/api/v1/nutrition/meal-estimates";
    private const string LabelScansPath = "/api/v1/nutrition/label-scans";

    internal static OpenApiOptions AddGainerTransformers(this OpenApiOptions options)
    {
        options.AddDocumentTransformer(TransformDocument);
        options.AddOperationTransformer(TransformOperation);
        return options;
    }

    private static Task TransformDocument(
        OpenApiDocument document,
        OpenApiDocumentTransformerContext context,
        CancellationToken cancellationToken)
    {
        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();
        document.Components.SecuritySchemes[BearerSchemeName] = new OpenApiSecurityScheme
        {
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            Description = "Opaque short-lived access token of a device session.",
        };

        document.Components.Schemas ??= new Dictionary<string, IOpenApiSchema>();
        document.Components.Schemas["ProblemDetails"] = new OpenApiSchema
        {
            Type = JsonSchemaType.Object,
            Properties = new Dictionary<string, IOpenApiSchema>
            {
                ["type"] = new OpenApiSchema { Type = JsonSchemaType.String | JsonSchemaType.Null },
                ["title"] = new OpenApiSchema { Type = JsonSchemaType.String | JsonSchemaType.Null },
                ["status"] = new OpenApiSchema { Type = JsonSchemaType.Integer | JsonSchemaType.Null, Format = "int32" },
                ["detail"] = new OpenApiSchema { Type = JsonSchemaType.String | JsonSchemaType.Null },
                ["instance"] = new OpenApiSchema { Type = JsonSchemaType.String | JsonSchemaType.Null },
                ["code"] = new OpenApiSchema
                {
                    Type = JsonSchemaType.String,
                    Description = "Stable machine-readable error code; clients branch on it, never on title.",
                },
                ["traceId"] = new OpenApiSchema { Type = JsonSchemaType.String },
                ["correlationId"] = new OpenApiSchema { Type = JsonSchemaType.String },
                ["errors"] = new OpenApiSchema
                {
                    Type = JsonSchemaType.Object,
                    Description = "Validation messages by field name.",
                    AdditionalProperties = new OpenApiSchema
                    {
                        Type = JsonSchemaType.Array,
                        Items = new OpenApiSchema { Type = JsonSchemaType.String },
                    },
                },
            },
        };
        return Task.CompletedTask;
    }

    private static Task TransformOperation(
        OpenApiOperation operation,
        OpenApiOperationTransformerContext context,
        CancellationToken cancellationToken)
    {
        IList<object> metadata = context.Description.ActionDescriptor.EndpointMetadata;
        bool anonymous = metadata.OfType<IAllowAnonymous>().Any();
        // The fallback policy protects every endpoint that is not explicitly anonymous.
        if (!anonymous)
        {
            operation.Security ??= [];
            operation.Security.Add(new OpenApiSecurityRequirement
            {
                [new OpenApiSecuritySchemeReference(BearerSchemeName, context.Document)] = [],
            });
        }

        string? path = context.Description.RelativePath is { } relative ? '/' + relative : null;
        if (path == MealEstimatesPath)
        {
            operation.RequestBody = MultipartBody(
                requiredImage: false,
                new KeyValuePair<string, IOpenApiSchema>("text", new OpenApiSchema { Type = JsonSchemaType.String }),
                new KeyValuePair<string, IOpenApiSchema>("imageConsent", new OpenApiSchema { Type = JsonSchemaType.Boolean }));
        }
        else if (path == LabelScansPath)
        {
            operation.RequestBody = MultipartBody(requiredImage: true);
        }

        return Task.CompletedTask;
    }

    private static OpenApiRequestBody MultipartBody(
        bool requiredImage,
        params KeyValuePair<string, IOpenApiSchema>[] extraFields)
    {
        var properties = new Dictionary<string, IOpenApiSchema>
        {
            ["image"] = new OpenApiSchema { Type = JsonSchemaType.String, Format = "binary" },
        };
        foreach (KeyValuePair<string, IOpenApiSchema> field in extraFields)
        {
            properties[field.Key] = field.Value;
        }

        var schema = new OpenApiSchema { Type = JsonSchemaType.Object, Properties = properties };
        if (requiredImage)
        {
            schema.Required = new HashSet<string> { "image" };
        }

        return new OpenApiRequestBody
        {
            Required = true,
            Content = new Dictionary<string, OpenApiMediaType>
            {
                [MultipartMediaType] = new OpenApiMediaType { Schema = schema },
            },
        };
    }
}
