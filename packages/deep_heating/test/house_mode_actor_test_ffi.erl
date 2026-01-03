-module(house_mode_actor_test_ffi).
-export([create_counter/0, increment_counter/1, delete_counter/1]).

%% Create an atomic counter (can be safely accessed from any process)
create_counter() ->
    atomics:new(1, [{signed, false}]).

%% Atomically increment counter and return new value
increment_counter(Ref) ->
    atomics:add_get(Ref, 1, 1).

%% No-op for atomics (they're garbage collected)
delete_counter(_Ref) ->
    nil.
