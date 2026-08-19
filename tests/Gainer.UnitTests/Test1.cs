namespace Gainer.UnitTests;

[TestClass]
public sealed class CoreSmokeTests
{
    [TestMethod]
    public void CoreAssemblyCanBeLoaded()
    {
        var assemblyName = typeof(Gainer.Core.Security.IUserContext).Assembly.GetName().Name;

        Assert.AreEqual("Gainer.Core", assemblyName);
    }
}
