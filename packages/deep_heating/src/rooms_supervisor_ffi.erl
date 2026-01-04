-module(rooms_supervisor_ffi).
-export([identity/1]).

%% Identity function for type coercion.
%% At runtime, this just returns the input unchanged.
%% This allows Gleam to "cast" between Subject types that have
%% compatible underlying message representations.
identity(X) -> X.
