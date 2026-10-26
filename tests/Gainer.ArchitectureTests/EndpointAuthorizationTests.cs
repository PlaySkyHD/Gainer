using System.Reflection;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;
using Microsoft.AspNetCore.RateLimiting;

namespace Gainer.ArchitectureTests;

[TestClass]
public sealed class EndpointAuthorizationTests
{
    // The only anonymous controller actions. Each one needs a rate limit. A new entry needs a reason
    // in the review, because it opens an endpoint without a session.
    private static readonly string[] AnonymousActionAllowList =
    [
        "AuthenticationController.Login",
        "AuthenticationController.Refresh",
        "PasskeysController.RequestOptions",
        "PasskeysController.Login",
        "StravaController.Callback",
        "InvitationAcceptanceController.Accept",
        "SystemController.GetStatus",
    ];

    [TestMethod]
    public void EveryControllerActionRequiresAuthorizationOrIsAnAllowListedRateLimitedAnonymousEndpoint()
    {
        List<string> violations = [];
        foreach ((Type controller, MethodInfo action) in ControllerActions())
        {
            string name = $"{controller.Name}.{action.Name}";
            bool anonymous = HasAttribute<AllowAnonymousAttribute>(controller, action);
            bool authorized = HasAttribute<AuthorizeAttribute>(controller, action);

            if (anonymous)
            {
                if (!AnonymousActionAllowList.Contains(name))
                {
                    violations.Add($"{name} is anonymous but not in the allow list.");
                }

                if (!HasAttribute<EnableRateLimitingAttribute>(controller, action)
                    || HasAttribute<DisableRateLimitingAttribute>(controller, action))
                {
                    violations.Add($"{name} is anonymous without an effective [EnableRateLimiting] (or has [DisableRateLimiting]).");
                }
            }
            else if (!authorized)
            {
                violations.Add($"{name} has neither [Authorize] nor [AllowAnonymous].");
            }
        }

        Assert.IsEmpty(violations, string.Join(Environment.NewLine, violations));
    }

    [TestMethod]
    public void EveryAllowListEntryStillExistsAndIsAnonymous()
    {
        string[] anonymousActions = ControllerActions()
            .Where(entry => HasAttribute<AllowAnonymousAttribute>(entry.Controller, entry.Action))
            .Select(entry => $"{entry.Controller.Name}.{entry.Action.Name}")
            .ToArray();

        foreach (string entry in AnonymousActionAllowList)
        {
            CollectionAssert.Contains(anonymousActions, entry, $"Allow list entry {entry} is stale.");
        }
    }

    // Counter check (done once by hand, not committed): a controller without any attribute, for example
    // [ApiController] public sealed class ProbeController : ControllerBase { [HttpGet("probe")] public IActionResult Get() => Ok(); },
    // is reported by the first test as "ProbeController.Get has neither [Authorize] nor [AllowAnonymous]".
    private static IEnumerable<(Type Controller, MethodInfo Action)> ControllerActions()
    {
        Type[] controllers = typeof(Gainer.Api.Controllers.AuthenticationController).Assembly.GetTypes()
            .Where(type => typeof(ControllerBase).IsAssignableFrom(type) && !type.IsAbstract)
            .ToArray();
        Assert.IsNotEmpty(controllers);

        foreach (Type controller in controllers)
        {
            // Every public instance method counts as an action (also inherited ones and ones with only
            // [Route] or [AcceptVerbs]), except [NonAction] and members that ControllerBase or object define.
            foreach (MethodInfo method in controller.GetMethods(BindingFlags.Public | BindingFlags.Instance))
            {
                Type? origin = method.GetBaseDefinition().DeclaringType;
                if (!method.IsSpecialName
                    && origin != typeof(ControllerBase)
                    && origin != typeof(object)
                    && !method.IsDefined(typeof(NonActionAttribute), inherit: true))
                {
                    yield return (controller, method);
                }
            }
        }
    }

    private static bool HasAttribute<T>(Type controller, MethodInfo action)
        where T : Attribute =>
        action.IsDefined(typeof(T), inherit: true) || controller.IsDefined(typeof(T), inherit: true);
}
