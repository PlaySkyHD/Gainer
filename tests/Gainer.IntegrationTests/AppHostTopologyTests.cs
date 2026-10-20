using Aspire.Hosting.ApplicationModel;
using Aspire.Hosting.Azure;
using Aspire.Hosting.Testing;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class AppHostTopologyTests
{
    private static readonly string[] ExpectedResourceNames = ["postgres", "gainer-db", "backup-storage", "backup-blobs", "api"];

    [TestMethod]
    public async Task AppHostDefinesPostgresAzuriteAndApiWithReferences()
    {
        var appHost = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.Gainer_AppHost>();

        var resources = appHost.Resources.ToDictionary(resource => resource.Name);

        CollectionAssert.IsSubsetOf(
            ExpectedResourceNames,
            resources.Keys.ToArray());

        Assert.IsInstanceOfType<PostgresServerResource>(resources["postgres"]);
        Assert.IsInstanceOfType<PostgresDatabaseResource>(resources["gainer-db"]);
        Assert.IsInstanceOfType<AzureStorageResource>(resources["backup-storage"]);
        Assert.IsInstanceOfType<AzureBlobStorageResource>(resources["backup-blobs"]);
        AssertHasReference(resources["api"], resources["gainer-db"]);
    }

    private static void AssertHasReference(IResource source, IResource target)
    {
        var referencedResources = source.Annotations
            .OfType<ResourceRelationshipAnnotation>()
            .Where(annotation => annotation.Type == "Reference")
            .Select(annotation => annotation.Resource);

        CollectionAssert.Contains(referencedResources.ToArray(), target);
    }
}
