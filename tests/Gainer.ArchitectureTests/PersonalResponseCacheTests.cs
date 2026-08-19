using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Gainer.ArchitectureTests;

[TestClass]
public sealed class PersonalResponseCacheTests
{
    [TestMethod]
    public void EveryAuthorizedApiControllerDisablesSharedAndBrowserCaching()
    {
        Type controllerBase = typeof(Gainer.Api.Controllers.AuthenticationController);
        Type[] authorizedControllers = controllerBase.Assembly.GetTypes()
            .Where(type => typeof(ControllerBase).IsAssignableFrom(type) && !type.IsAbstract)
            .Where(type => type.GetCustomAttributes(typeof(AuthorizeAttribute), inherit: true).Length > 0)
            .ToArray();

        Assert.IsNotEmpty(authorizedControllers);
        foreach (Type controller in authorizedControllers)
        {
            ResponseCacheAttribute? cache = controller
                .GetCustomAttributes(typeof(ResponseCacheAttribute), inherit: true)
                .Cast<ResponseCacheAttribute>()
                .SingleOrDefault();
            Assert.IsNotNull(cache, $"{controller.FullName} must declare a personal no-store cache policy.");
            Assert.IsTrue(cache.NoStore, $"{controller.FullName} must use no-store.");
            Assert.AreEqual(ResponseCacheLocation.None, cache.Location, $"{controller.FullName} must disable shared caching.");
        }
    }
}
