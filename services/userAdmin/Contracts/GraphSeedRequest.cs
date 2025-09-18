using System.Collections.Generic;

namespace UserAdmin.Contracts;

public sealed record GraphSeedRequest(
    int Users = 10,
    int? Seed = null,
    double AvgFollows = 1,
    double HomophilyBoost = 1.8,
    double InfluencerBoost = 4.0,
    double TriadicProb = 0.12,
    double ReciprocityProb = 0.28,
    double NoiseFollowProb = 0.02);

public sealed record GraphSeedTopHub(string User, int Followers);

public sealed record GraphSeedStats(
    int Users,
    int AccountsCreated,
    int Edges,
    double AvgOut,
    double AvgIn,
    int TriadicAdded,
    int ReciprocalAdded,
    double Reciprocity,
    double GiniFollowers,
    IReadOnlyList<GraphSeedTopHub> TopHubs);

public sealed record GraphSeedResult(string Message, GraphSeedStats Stats, double TotalRequestCharge);
