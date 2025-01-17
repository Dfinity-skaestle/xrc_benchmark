/// This is a simple example showing how to interact with the
/// exchange rate canister (XRC).

import XRC "canister:xrc";
import Cycles "mo:base/ExperimentalCycles";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Float "mo:base/Float";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Dbg "mo:base/Debug";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Array "mo:base/Array";
import Error "mo:base/Error";
import List "mo:base/List";
import Iter "mo:base/Iter";
import Option "mo:base/Option";

actor {
  // Counter that is increased for every call to avoid being able to serve a cached result.
  var counter = 0;
  var target_canister_id = "";

  var results : List.List<Float> = List.nil();
  var failures = HashMap.HashMap<Text, Nat32>(10, Text.equal, Text.hash);

  /// Set canister ID of the XRC canister dynamically at runtime
  public func set_xrc_canister_id(canister_id : Text) : async () {
    target_canister_id := canister_id;
  };

  /// Extract the current exchange rate for the given symbol.
  public func get_exchange_rate(symbol : Text, second_symbol : Text) : async Float {
    counter += 1;
    let xrc_canister_actor = actor (target_canister_id) : actor {
      get_exchange_rate : (XRC.GetExchangeRateRequest) -> async (XRC.GetExchangeRateResult);
    };

    let time_sec = Time.now() / 1_000_000_000;
    // Use the previous minute to increase the chance of getting a rate because
    // not every exchange has data available for the current minute.
    let time = Nat64.fromIntWrap(time_sec - counter * 60);
    let request : XRC.GetExchangeRateRequest = {
      base_asset = {
        symbol = symbol;
        class_ = #Cryptocurrency;
      };
      quote_asset = {
        symbol = second_symbol;
        class_ = #Cryptocurrency;
      };
      timestamp = ?time;
    };

    // Every XRC call needs 10B cycles.
    Cycles.add(10_000_000_000);
    let response = await xrc_canister_actor.get_exchange_rate(request);
    switch (response) {
      case (#Ok(rate_response)) {
        // Extract result
        let float_rate = Float.fromInt(Nat64.toNat(rate_response.rate));
        // Remember result
        results := List.push(float_rate, results);
      };
      case (#Err(e)) {
        switch e {
          case (?err) {
            let key = switch err {
              case (#CryptoBaseAssetNotFound) { "CryptoBaseAssetNotFound" };
              case (#CryptoQuoteAssetNotFound) { "CryptoQuoteAssetNotFound" };
              case (#StablecoinRateNotFound) { "StablecoinRateNotFound" };
              case (#StablecoinRateTooFewRates) { "StablecoinRateTooFewRates" };
              case (#StablecoinRateZeroRate) { "StablecoinRateZeroRate" };
              case (#ForexInvalidTimestamp) { "ForexInvalidTimestamp" };
              case (#ForexBaseAssetNotFound) { "ForexBaseAssetNotFound" };
              case (#ForexQuoteAssetNotFound) { "ForexQuoteAssetNotFound" };
              case (#ForexAssetsNotFound) { "ForexAssetsNotFound" };
              case (#RateLimited) { "RateLimited" };
              case (#NotEnoughCycles) { "NotEnoughCycles" };
              case (#FailedToAcceptCycles) { "FailedToAcceptCycles" };
              case (#InconsistentRatesReceived) { "InconsistentRatesReceived" };
              case (#Other(_)) { "Other" };
            };
            let previous = failures.get(key);
            switch (previous) {
              case (?p) { failures.put(key, p + 1) };
              case null { failures.put(key, 1) };
            };
          };
          case _ {};
        };
      };
    };
    // Print out the response to get a detailed view.
    Dbg.print(debug_show (response));
    // Return 0.0 if there is an error for the sake of simplicity.
    switch (response) {
      case (#Ok(rate_response)) {
        let float_rate = Float.fromInt(Nat64.toNat(rate_response.rate));
        let float_divisor = Float.fromInt(Nat32.toNat(10 ** rate_response.metadata.decimals));
        return float_rate / float_divisor;
      };
      case _ {
        return 0.0;
      };
    };
  };

  /// Return previously fetched rates.
  public query func fetch_results() : async [Float] {
    return List.toArray(results);
  };

  public query func get_failures() : async [(Text, Nat32)] {
    return Iter.toArray(failures.entries());
  };

  /// Reset internal state of the canister. Clears all recorded failures and rates.
  public func reset() : async () {
    results := List.nil();
    failures := HashMap.HashMap<Text, Nat32>(10, Text.equal, Text.hash);
  };
};
