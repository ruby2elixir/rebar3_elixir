-module(rebar3_elixir_resource).

-behaviour(rebar_resource).

-export([lock/2
        ,download/3
        ,needs_update/2
        ,make_vsn/1]).

lock(_Dir, Source) ->
    Source.

download(Dir, {elixir, Name, Vsn}, State) ->
    rebar_api:console("===> Adding Dir ~p", [Dir]),
    Pkg = {pkg, Name, Vsn},
    fetch_and_compile(State, Dir, Pkg),
    rebar_api:console("===> Adding Elixir Deps download ~p", [Name]),
    {ok, true}.

needs_update(Dir, {pkg, _Name, Vsn}) ->
    [AppInfo] = rebar_app_discover:find_apps([Dir], all),
    case rebar_app_info:original_vsn(AppInfo) =:= ec_cnv:to_list(Vsn) of
        true ->
            false;
        false ->
            true
    end.

make_vsn(_) ->
    {error, "Replacing version of type elixir not supported."}.

fetch_and_compile(State, Dir, Pkg = {pkg, Name, _Vsn}) ->
    fetch(Pkg),
    State1 = rebar3_elixir_util:add_elixir(State),
    State2 = rebar_state:set(State1, libs_target_dir, default),
    BaseDir = filename:join(rebar_dir:root_dir(State2), "_elixir_build/"),
    BaseDirState = rebar_state:set(State2, elixir_base_dir, BaseDir),
    Env = rebar_state:get(BaseDirState, mix_env),
    AppDir = filename:join(BaseDir, Name),
    LibDir = filename:join([AppDir, "_build/", Env , "lib/"]),
    rebar3_elixir_util:compile_libs(BaseDirState),
    rebar3_elixir_util:transfer_libs(rebar_state:set(BaseDirState, libs_target_dir, Dir), [Name], LibDir).

fetch({pkg, Name_, Vsn_}) ->
    Dir = filename:join([filename:absname("_elixir_build"), Name_]),
    Name = atom_to_binary(Name_, utf8), 
    Vsn  = list_to_binary(Vsn_),
    case filelib:is_dir(Dir) of
        false ->
            CDN = "https://repo.hex.pm/tarballs",
            Package = binary_to_list(<<Name/binary, "-", Vsn/binary, ".tar">>),
            Url = string:join([CDN, Package], "/"),
            case request(Url) of
                {ok, Binary} ->
                    {ok, Contents} = extract(Binary),
                    ok = erl_tar:extract({binary, Contents}, [{cwd, Dir}, compressed]);
                _ ->
                    rebar_api:console("Error: Unable to fetch package ~p ~p~n", [Name, Vsn])
            end;
        true ->
            rebar_api:console("Dependency ~s already exists~n", [Name])
    end.

extract(Binary) ->
    {ok, Files} = erl_tar:extract({binary, Binary}, [memory]),
    {"contents.tar.gz", Contents} = lists:keyfind("contents.tar.gz", 1, Files),
    {ok, Contents}.

request(Url) ->
    case httpc:request(get, {Url, []},
                       [{relaxed, true}],
                       [{body_format, binary}],
                       rebar) of
        {ok, {{_Version, 200, _Reason}, _Headers, Body}} ->
            {ok, Body};
        Error ->
            Error
    end.