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
import Buffer "mo:base/Buffer";

actor {

  // Counter that is increased for every call to avoid being able to serve a cached result.
  var counter = 0;
  var target_canister_id = "";
  // Should be a Tuple of Text!
  var results : HashMap.HashMap<Text, [Float]> = HashMap.HashMap<Text, [Float]>(1000, Text.equal, Text.hash);
  var num_failures = 0;
  var failures = Buffer.Buffer<XRC.ExchangeRateError>(10);

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
    let time = Nat64.fromIntWrap(time_sec - counter * 60000);
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
        let key = Text.concat(symbol, second_symbol);
        let previous = results.get(key);
        switch (previous) {
          case (?p) { results.put(key, Array.append(p, [float_rate])) };
          case null { results.put(key, [float_rate]) };
        };
      };
      case (#Err(e)) {
        // Might want to have a hashmap of failures here ..
        num_failures += 1;
        switch e {
          case (?err) {
            failures.add(err);
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

  /// Extract the current exchange rate for the given symbol.
  public query func fetch_results(symbol : Text, second_symbol : Text) : async ?[Float] {
    let key = Text.concat(symbol, second_symbol);
    return results.get(key);
  };

  public query func get_num_failures() : async Nat {
    return num_failures;
  };

  public query func get_failures() : async [XRC.ExchangeRateError] {
    return Buffer.toArray(failures);
  };
};
