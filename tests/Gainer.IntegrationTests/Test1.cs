namespace Gainer.IntegrationTests;

[TestClass]
public sealed class PostgreSqlIntegrationTestProjectSmokeTests
{
    [TestMethod]
    public void InfrastructureAssemblyCanBeLoaded()
    {
        var assemblyName = typeof(Gainer.Infrastructure.Persistence.AppDbContext).Assembly.GetName().Name;

        Assert.AreEqual("Gainer.Infrastructure", assemblyName);
    }
}
