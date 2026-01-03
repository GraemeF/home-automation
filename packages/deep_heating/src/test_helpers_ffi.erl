-module(test_helpers_ffi).
-export([silence_otp_logs/0, restore_otp_logs/1, with_silenced_io/1]).

%% Silence all OTP/SASL logs by setting logger level to none
%% Returns the previous log level so it can be restored
silence_otp_logs() ->
    #{level := OldLevel} = logger:get_primary_config(),
    logger:set_primary_config(level, none),
    OldLevel.

%% Restore the previous log level
restore_otp_logs(Level) ->
    logger:set_primary_config(level, Level),
    nil.

%% Execute a function with silenced io output
%% Captures any io:put_chars output and discards it
with_silenced_io(Fun) ->
    OldGroupLeader = erlang:group_leader(),
    {ok, NullDev} = file:open("/dev/null", [write]),
    erlang:group_leader(NullDev, self()),
    try
        Fun()
    after
        erlang:group_leader(OldGroupLeader, self()),
        file:close(NullDev)
    end.
