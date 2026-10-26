using System.Net;

namespace Gainer.IntegrationTests;

/// <summary>
/// Reusable black-box contract for every user-owned HTTP resource. A module supplies an adapter
/// backed by two independently authenticated clients; the matrix owns the isolation assertions.
/// </summary>
internal static class TwoUserApiIsolationMatrix
{
    public static async Task VerifyAsync<TActor>(ITwoUserApiIsolationScenario<TActor> scenario)
    {
        Guid[] firstIds =
        [
            await scenario.CreateAsync(scenario.FirstUser, "first-private-one"),
            await scenario.CreateAsync(scenario.FirstUser, "first-private-two"),
            await scenario.CreateAsync(scenario.FirstUser, "first-private-three"),
        ];
        Guid[] secondIds =
        [
            await scenario.CreateAsync(scenario.SecondUser, "second-private-one"),
            await scenario.CreateAsync(scenario.SecondUser, "second-private-two"),
        ];

        Assert.AreEqual(firstIds.Length, await scenario.CountAsync(scenario.FirstUser));
        Assert.AreEqual(secondIds.Length, await scenario.CountAsync(scenario.SecondUser));
        CollectionAssert.AreEquivalent(
            firstIds,
            (await scenario.ListIdsAsync(scenario.FirstUser, offset: 0, limit: 100)).ToArray());
        CollectionAssert.AreEquivalent(
            secondIds,
            (await scenario.ListIdsAsync(scenario.SecondUser, offset: 0, limit: 100)).ToArray());

        IReadOnlyList<Guid> firstPage = await scenario.ListIdsAsync(scenario.FirstUser, offset: 0, limit: 2);
        IReadOnlyList<Guid> secondPage = await scenario.ListIdsAsync(scenario.FirstUser, offset: 2, limit: 2);
        Assert.HasCount(2, firstPage);
        Assert.HasCount(1, secondPage);
        Assert.AreEqual(3, firstPage.Concat(secondPage).Distinct().Count());
        CollectionAssert.AreEquivalent(firstIds, firstPage.Concat(secondPage).ToArray());

        Guid unknownId = Guid.NewGuid();
        await AssertForeignResponseIsNeutralAsync(
            () => scenario.DetailAsync(scenario.FirstUser, secondIds[0]),
            () => scenario.DetailAsync(scenario.FirstUser, unknownId),
            scenario);

        IsolationApiResponse beforeForeignUpdate = await scenario.DetailAsync(scenario.FirstUser, firstIds[0]);
        await AssertForeignResponseIsNeutralAsync(
            () => scenario.UpdateAsync(scenario.SecondUser, firstIds[0], "second-user-overwrite"),
            () => scenario.UpdateAsync(scenario.SecondUser, unknownId, "second-user-overwrite"),
            scenario);
        Assert.AreEqual(
            beforeForeignUpdate.Representation,
            (await scenario.DetailAsync(scenario.FirstUser, firstIds[0])).Representation,
            "A foreign update changed the owner's representation.");

        await AssertForeignResponseIsNeutralAsync(
            () => scenario.DeleteAsync(scenario.SecondUser, firstIds[0]),
            () => scenario.DeleteAsync(scenario.SecondUser, unknownId),
            scenario);
        Assert.AreEqual(
            beforeForeignUpdate.Representation,
            (await scenario.DetailAsync(scenario.FirstUser, firstIds[0])).Representation,
            "A foreign delete changed the owner's representation.");

        IsolationApiResponse ownUpdate = await scenario.UpdateAsync(
            scenario.FirstUser,
            firstIds[0],
            "first-private-updated");
        Assert.IsTrue(ownUpdate.IsSuccessStatusCode, "The matrix adapter did not permit an own update.");
        Assert.Contains(
            "first-private-updated",
            (await scenario.DetailAsync(scenario.FirstUser, firstIds[0])).Representation);

        IsolationApiResponse ownDelete = await scenario.DeleteAsync(scenario.SecondUser, secondIds[1]);
        Assert.IsTrue(ownDelete.IsSuccessStatusCode, "The matrix adapter did not permit an own delete.");
        Assert.AreEqual(secondIds.Length - 1, await scenario.CountAsync(scenario.SecondUser));
        Assert.AreEqual(firstIds.Length, await scenario.CountAsync(scenario.FirstUser));
    }

    /// <summary>
    /// For resources without list, update or delete endpoints: the second user must be unable to read
    /// or change what the first user owns, and the answer must match the answer for an unknown id.
    /// Operations the resource does not offer are switched off through the scenario's Supports flags.
    /// </summary>
    public static async Task VerifyForeignAccessAsync<TActor>(ITwoUserApiIsolationScenario<TActor> scenario)
    {
        Assert.IsTrue(
            scenario.SupportsDetail || scenario.SupportsUpdate || scenario.SupportsDelete,
            "The scenario offers no operation to verify.");
        Guid firstId = await scenario.CreateAsync(scenario.FirstUser, "first-private-one");
        Guid secondId = await scenario.CreateAsync(scenario.SecondUser, "second-private-one");
        Guid unknownId = Guid.NewGuid();

        IsolationApiResponse? ownerBefore = null;
        if (scenario.SupportsDetail)
        {
            ownerBefore = await scenario.DetailAsync(scenario.FirstUser, firstId);
            Assert.IsTrue(ownerBefore.IsSuccessStatusCode, "The owner cannot read the resource.");
            await AssertForeignResponseIsNeutralAsync(
                () => scenario.DetailAsync(scenario.SecondUser, firstId),
                () => scenario.DetailAsync(scenario.SecondUser, unknownId),
                scenario);
            Assert.IsTrue(
                (await scenario.DetailAsync(scenario.SecondUser, secondId)).IsSuccessStatusCode,
                "The second user cannot read their own resource.");
        }

        if (scenario.SupportsUpdate)
        {
            await AssertForeignResponseIsNeutralAsync(
                () => scenario.UpdateAsync(scenario.SecondUser, firstId, "second-user-overwrite"),
                () => scenario.UpdateAsync(scenario.SecondUser, unknownId, "second-user-overwrite"),
                scenario);
        }

        if (scenario.SupportsDelete)
        {
            await AssertForeignResponseIsNeutralAsync(
                () => scenario.DeleteAsync(scenario.SecondUser, firstId),
                () => scenario.DeleteAsync(scenario.SecondUser, unknownId),
                scenario);
        }

        if (ownerBefore is not null)
        {
            Assert.AreEqual(
                ownerBefore.Representation,
                (await scenario.DetailAsync(scenario.FirstUser, firstId)).Representation,
                "A foreign operation changed the owner's representation.");
        }

        // Positive control: the foreign attempts above did not damage the owner's resource.
        IsolationApiResponse control = scenario.SupportsUpdate
            ? await scenario.UpdateAsync(scenario.FirstUser, firstId, "first-private-updated")
            : await scenario.DeleteAsync(scenario.FirstUser, firstId);
        Assert.IsTrue(control.IsSuccessStatusCode, $"The owner's own operation failed with {control.StatusCode}.");
    }

    private static async Task AssertForeignResponseIsNeutralAsync<TActor>(
        Func<Task<IsolationApiResponse>> foreignOperation,
        Func<Task<IsolationApiResponse>> unknownOperation,
        ITwoUserApiIsolationScenario<TActor> scenario)
    {
        IsolationApiResponse foreign = await foreignOperation();
        IsolationApiResponse unknown = await unknownOperation();

        Assert.AreEqual(HttpStatusCode.NotFound, foreign.StatusCode);
        Assert.AreEqual(unknown.StatusCode, foreign.StatusCode);
        Assert.AreEqual(unknown.PublicErrorCode, foreign.PublicErrorCode);
        Assert.IsFalse(scenario.FirstUserSecretPattern.IsMatch(foreign.Representation));
        Assert.IsFalse(scenario.SecondUserSecretPattern.IsMatch(foreign.Representation));
    }
}

internal interface ITwoUserApiIsolationScenario<TActor>
{
    TActor FirstUser { get; }

    TActor SecondUser { get; }

    System.Text.RegularExpressions.Regex FirstUserSecretPattern { get; }

    System.Text.RegularExpressions.Regex SecondUserSecretPattern { get; }

    /// <summary>Whether the resource can be read by id; only <c>VerifyForeignAccessAsync</c> honours the Supports flags.</summary>
    bool SupportsDetail => true;

    bool SupportsUpdate => true;

    bool SupportsDelete => true;

    Task<Guid> CreateAsync(TActor actor, string privateMarker);

    Task<IReadOnlyList<Guid>> ListIdsAsync(TActor actor, int offset, int limit);

    Task<int> CountAsync(TActor actor);

    Task<IsolationApiResponse> DetailAsync(TActor actor, Guid id);

    Task<IsolationApiResponse> UpdateAsync(TActor actor, Guid id, string privateMarker);

    Task<IsolationApiResponse> DeleteAsync(TActor actor, Guid id);
}

internal sealed record IsolationApiResponse(
    HttpStatusCode StatusCode,
    string PublicErrorCode,
    string Representation)
{
    public bool IsSuccessStatusCode => (int)StatusCode is >= 200 and <= 299;
}
