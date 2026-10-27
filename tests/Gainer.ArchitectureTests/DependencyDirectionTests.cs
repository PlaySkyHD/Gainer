namespace Gainer.ArchitectureTests;

[TestClass]
public sealed class DependencyDirectionTests
{
    [TestMethod]
    public void CoreDoesNotReferenceInfrastructure()
    {
        var referencedAssemblyNames = typeof(Gainer.Core.Security.IUserContext)
            .Assembly
            .GetReferencedAssemblies()
            .Select(reference => reference.Name);

        Assert.DoesNotContain("Gainer.Infrastructure", referencedAssemblyNames.ToArray());
    }

    [TestMethod]
    public void ContractsDoNotReferenceImplementationProjects()
    {
        string?[] referencedAssemblyNames = typeof(Gainer.Contracts.System.SystemStatusResponse)
            .Assembly
            .GetReferencedAssemblies()
            .Select(reference => reference.Name)
            .ToArray();

        Assert.DoesNotContain("Gainer.Api", referencedAssemblyNames);
        Assert.DoesNotContain("Gainer.Core", referencedAssemblyNames);
        Assert.DoesNotContain("Gainer.Infrastructure", referencedAssemblyNames);
    }

    [TestMethod]
    public void InfrastructureDoesNotReferenceApiOrContracts()
    {
        string?[] referencedAssemblyNames = typeof(Gainer.Infrastructure.Persistence.AppDbContext)
            .Assembly
            .GetReferencedAssemblies()
            .Select(reference => reference.Name)
            .ToArray();

        Assert.DoesNotContain("Gainer.Api", referencedAssemblyNames);
        Assert.DoesNotContain("Gainer.Contracts", referencedAssemblyNames);
    }

    [TestMethod]
    public void ControllersDoNotReceiveTheDatabaseContextDirectly()
    {
        Type databaseContextType = typeof(Gainer.Infrastructure.Persistence.AppDbContext);
        Type[] controllerTypes = typeof(Program).Assembly.GetTypes()
            .Where(type => typeof(Microsoft.AspNetCore.Mvc.ControllerBase).IsAssignableFrom(type))
            .ToArray();

        bool hasDirectContextDependency = controllerTypes
            .SelectMany(type => type.GetConstructors())
            .SelectMany(constructor => constructor.GetParameters())
            .Any(parameter => parameter.ParameterType == databaseContextType);

        Assert.IsFalse(hasDirectContextDependency);
    }

    [TestMethod]
    public void AccountOperatorProvisioningDependsOnlyOnIdentityAndConfiguration()
    {
        Type[] dependencies = typeof(Gainer.Api.Security.InitialAccountOperatorProvisioner)
            .GetConstructors()
            .SelectMany(constructor => constructor.GetParameters())
            .Select(parameter => parameter.ParameterType)
            .ToArray();

        Assert.DoesNotContain(type =>
            typeof(Gainer.Core.Security.IUserScopedRepository).IsAssignableFrom(type), dependencies);
        Assert.DoesNotContain(type =>
            type.Namespace?.Contains("Insights", StringComparison.Ordinal) == true, dependencies);
        Assert.IsFalse(dependencies.Contains(typeof(Gainer.Infrastructure.Persistence.AppDbContext)));
    }

    [TestMethod]
    public void AccountStatusManagementDoesNotDependOnFitnessRepositoriesOrInsights()
    {
        Type[] dependencies = new[]
            {
                typeof(Gainer.Infrastructure.Persistence.AccountStatusService),
                typeof(Gainer.Infrastructure.Persistence.AccountDirectoryService),
            }
            .SelectMany(type => type.GetConstructors())
            .SelectMany(constructor => constructor.GetParameters())
            .Select(parameter => parameter.ParameterType)
            .ToArray();

        Assert.DoesNotContain(type =>
            typeof(Gainer.Core.Security.IUserScopedRepository).IsAssignableFrom(type), dependencies);
        Assert.DoesNotContain(type =>
            type.Namespace?.Contains("Insights", StringComparison.Ordinal) == true, dependencies);
        Assert.IsFalse(dependencies.Contains(typeof(Gainer.Infrastructure.Persistence.AppDbContext)));
    }
}
