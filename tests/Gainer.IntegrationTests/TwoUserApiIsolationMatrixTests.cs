using System.Net;
using System.Text.RegularExpressions;

namespace Gainer.IntegrationTests;

[TestClass]
public sealed class TwoUserApiIsolationMatrixTests
{
    [TestMethod]
    public async Task MatrixCoversEveryRequiredOperationAgainstTwoIndependentActors()
    {
        await TwoUserApiIsolationMatrix.VerifyAsync(new InMemoryScenario());
    }

    private sealed class InMemoryScenario : ITwoUserApiIsolationScenario<string>
    {
        private readonly Dictionary<Guid, Item> items = [];

        public string FirstUser => "first-user";

        public string SecondUser => "second-user";

        public Regex FirstUserSecretPattern { get; } = new("first-(user|private)", RegexOptions.IgnoreCase);

        public Regex SecondUserSecretPattern { get; } = new("second-(user|private)", RegexOptions.IgnoreCase);

        public Task<Guid> CreateAsync(string actor, string privateMarker)
        {
            Guid id = Guid.NewGuid();
            items.Add(id, new Item(id, actor, privateMarker));
            return Task.FromResult(id);
        }

        public Task<IReadOnlyList<Guid>> ListIdsAsync(string actor, int offset, int limit)
        {
            IReadOnlyList<Guid> result = items.Values
                .Where(item => item.Owner == actor)
                .OrderBy(item => item.Id)
                .Skip(offset)
                .Take(limit)
                .Select(item => item.Id)
                .ToArray();
            return Task.FromResult(result);
        }

        public Task<int> CountAsync(string actor)
        {
            return Task.FromResult(items.Values.Count(item => item.Owner == actor));
        }

        public Task<IsolationApiResponse> DetailAsync(string actor, Guid id)
        {
            return Task.FromResult(items.TryGetValue(id, out Item? item) && item.Owner == actor
                ? Success(item.Marker)
                : NotFound());
        }

        public Task<IsolationApiResponse> UpdateAsync(string actor, Guid id, string privateMarker)
        {
            if (!items.TryGetValue(id, out Item? item) || item.Owner != actor)
            {
                return Task.FromResult(NotFound());
            }

            items[id] = item with { Marker = privateMarker };
            return Task.FromResult(Success(privateMarker));
        }

        public Task<IsolationApiResponse> DeleteAsync(string actor, Guid id)
        {
            if (!items.TryGetValue(id, out Item? item) || item.Owner != actor)
            {
                return Task.FromResult(NotFound());
            }

            items.Remove(id);
            return Task.FromResult(new IsolationApiResponse(HttpStatusCode.NoContent, string.Empty, string.Empty));
        }

        private static IsolationApiResponse Success(string marker) =>
            new(HttpStatusCode.OK, string.Empty, $"{{\"marker\":\"{marker}\"}}");

        private static IsolationApiResponse NotFound() =>
            new(HttpStatusCode.NotFound, "resource-not-found", "{\"code\":\"resource-not-found\"}");

        private sealed record Item(Guid Id, string Owner, string Marker);
    }
}
