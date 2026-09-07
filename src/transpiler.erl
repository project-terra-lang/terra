-module(transpiler).
-export([transpile_file/1, emit_file/2, compile_file/2, run_file/3, module_name/1,
         codegen_pass/1]).

transpile_file(Path) ->
    case program:parse_file(Path) of
        {ok, Program} ->
            Module = module_name(Path),
            try
                case codegen_pass(#{module => Module, program => Program}) of
                    {ok, #{source := Source}} -> {ok, Module, Source};
                    Error -> Error
                end
            catch
                throw:{backend_error, Reason} -> {error, {backend, Reason}}
            end;
        Error -> Error
    end.

emit_file(Path, OutputPath) ->
    case transpile_file(Path) of
        {ok, Module, Source} ->
            ok = filelib:ensure_dir(OutputPath),
            case file:write_file(OutputPath, iolist_to_binary(Source)) of
                ok -> {ok, Module, OutputPath};
                {error, Reason} -> {error, {write_failed, Reason}}
            end;
        Error -> Error
    end.

compile_file(Path, OutDir) ->
    ModuleName = atom_to_list(module_name(Path)),
    ErlangPath = filename:join(OutDir, ModuleName ++ ".erl"),
    BeamPath = filename:join(OutDir, ModuleName ++ ".beam"),
    case emit_file(Path, ErlangPath) of
        {ok, Module, _} ->
            ok = filelib:ensure_dir(filename:join(OutDir, "placeholder")),
            case compile:file(ErlangPath, [debug_info, deterministic,
                                           return_errors, return_warnings,
                                           {outdir, OutDir}]) of
                {ok, Module} -> {ok, Module, BeamPath, ErlangPath};
                {ok, Module, _Warnings} -> {ok, Module, BeamPath, ErlangPath};
                {error, Errors, Warnings} ->
                    {error, {erlang_compile, Errors, Warnings}}
            end;
        Error -> Error
    end.

run_file(Path, Args, OutDir) ->
    case compile_file(Path, OutDir) of
        {ok, Module, BeamPath, ErlangPath} ->
            code:purge(Module),
            code:delete(Module),
            BeamRoot = filename:rootname(BeamPath),
            case code:load_abs(BeamRoot) of
                {module, Module} ->
                    try
                        Result = apply(Module, main, [Args]),
                        {ok, Module, Result, BeamPath, ErlangPath}
                    catch
                        Class:Reason:Stacktrace ->
                            {error, {runtime_error, Class, Reason, Stacktrace}}
                    end;
                {error, Reason} -> {error, {beam_load_failed, Reason}}
            end;
        Error -> Error
    end.

module_name(Path) ->
    Base = filename:basename(Path, filename:extension(Path)),
    list_to_atom("terra_" ++ sanitize_lower(Base)).

codegen_pass(#{module := Module, program := Program} = Context) ->
    Source = generate_module(Module, Program),
    Passes = maps:get(passes, Program, []) ++ [codegen],
    {ok, Context#{source => Source, passes => Passes}}.

generate_module(Module, #{functions := Functions} = Program) ->
    SourcePath = maps:get(source_path, Program, "terra_source"),
    ModuleDeclarations = maps:get(module_declarations, Program, []),
    MainLine = function_source_line("Main", Functions),
    RegionCapacity = maps:get(region_capacity, Program, {auto, 0}),
    UsesPointers = uses_pointer_region(RegionCapacity),
    ["-module(", atom_to_list(Module), ").\n",
     "-export([main/1]).\n\n",
     source_attribute(SourcePath, MainLine),
     main_wrapper(RegionCapacity, UsesPointers),
     [generate_function(Function#{module_declarations => ModuleDeclarations}, SourcePath)
     || Function <- Functions],
     "-file(\"terra_runtime\", 1).\n",
     runtime_helpers(),
     case UsesPointers of true -> pointer_runtime_helpers(); false -> "" end].

uses_pointer_region({fixed, _Capacity}) -> true;
uses_pointer_region({auto, Estimate}) -> Estimate > 0.

main_wrapper(Capacity, true) ->
    ["main(Args) ->\n",
     "    TerraRegion = terra_region_start(", region_capacity(Capacity), "),\n",
     "    try terra_fn_main(terra_args(Args))\n",
     "    after terra_region_cleanup(TerraRegion) end.\n\n"];
main_wrapper(_Capacity, false) ->
    "main(Args) ->\n    terra_fn_main(terra_args(Args)).\n\n".

region_capacity({fixed, Capacity}) -> integer_to_list(Capacity);
region_capacity({auto, Estimate}) -> ["{auto, ", integer_to_list(Estimate), "}"].

function_source_line(Name, Functions) ->
    case [maps:get(source_line, Function, 1) || Function <- Functions,
                                               maps:get(name, Function) == Name] of
        [Line] -> Line;
        _ -> 1
    end.

generate_function(Function, SourcePath) ->
    case lists:usort(tail_calls(maps:get(statements, Function, []))) of
        [] -> generate_regular_function(Function, SourcePath);
        TailCalls -> generate_tail_function(Function, TailCalls, SourcePath)
    end.

generate_regular_function(Function, SourcePath) ->
    Name = maps:get(name, Function),
    Params = maps:get(params, Function),
    {ParamNames, Env, Counter} = bind_parameters(Params, 1, [], #{}),
    {ModulePrelude, ModuleEnv, ModuleCounter} =
        generate_statements(maps:get(module_declarations, Function, []),
                            Env, Counter, 2, Name),
    {Body, _FinalEnv, _FinalCounter} =
        generate_statements(maps:get(statements, Function, []),
                            ModuleEnv, ModuleCounter, 2, Name),
    Default = default_value(maps:get(return_types, Function)),
    Expressions = ModulePrelude ++ Body ++ [[indent(2), Default]],
    [source_attribute(SourcePath, maps:get(source_line, Function, 1)),
     function_name(Name), "(", lists:join(", ", ParamNames), ") ->\n",
     indent(1), "try\n",
     join_expressions(Expressions), "\n",
     indent(1), "catch\n",
     indent(2), "throw:{terra_return, TerraReturnValue} -> TerraReturnValue\n",
     indent(1), "end.\n\n"].

generate_tail_function(Function, TailCalls, SourcePath) ->
    Name = maps:get(name, Function),
    Params = maps:get(params, Function),
    {ParamNames, Env, Counter} = bind_parameters(Params, 1, [], #{}),
    {ModulePrelude, ModuleEnv, ModuleCounter} =
        generate_statements(maps:get(module_declarations, Function, []),
                            Env, Counter, 2, Name),
    StepName = tail_step_name(Name),
    Dispatch = [tail_dispatch_clause(Target, Arity) || {Target, Arity} <- TailCalls] ++
               [["{terra_return, TerraReturnValue} -> TerraReturnValue"]],
    {Body, _FinalEnv, _FinalCounter} =
        generate_statements(maps:get(statements, Function, []),
                            ModuleEnv, ModuleCounter, 2, Name),
    Default = default_value(maps:get(return_types, Function)),
    Expressions = ModulePrelude ++ Body ++ [[indent(2), Default]],
    SourceLine = maps:get(source_line, Function, 1),
    [source_attribute(SourcePath, SourceLine),
     function_name(Name), "(", lists:join(", ", ParamNames), ") ->\n",
     indent(1), "case ", StepName, "(", lists:join(", ", ParamNames), ") of\n",
     indent(2), lists:join([";\n", indent(2)], Dispatch), "\n",
     indent(1), "end.\n\n",
     source_attribute(SourcePath, SourceLine),
     StepName, "(", lists:join(", ", ParamNames), ") ->\n",
     indent(1), "try\n",
     join_expressions(Expressions), "\n",
     indent(1), "catch\n",
     indent(2), "throw:{terra_return, TerraReturnValue} -> ",
     "{terra_return, TerraReturnValue};\n",
     indent(2), "throw:{terra_tail_call, TerraTarget, TerraArgs} -> ",
     "{terra_tail_call, TerraTarget, TerraArgs}\n",
     indent(1), "end.\n\n"].

source_attribute(Path, Line) ->
    ["-file(", io_lib:format("~p", [Path]), ", ", integer_to_list(max(1, Line)), ").\n"].

tail_dispatch_clause(Target, Arity) ->
    Args = ["TerraTailArg" ++ integer_to_list(Index)
            || Index <- lists:seq(1, Arity)],
    ["{terra_tail_call, ", io_lib:format("~p", [Target]), ", [",
     lists:join(", ", Args), "]} -> ", function_name(Target), "(",
     lists:join(", ", Args), ")"].

tail_calls(#{kind := return, values := [{call, Name, Args}]}) when is_list(Name) ->
    [{Name, length(Args)}];
tail_calls(#{kind := return, values := [{try_call, Name, Args}]}) ->
    [{Name, length(Args)}];
tail_calls(#{kind := return, values := [{pipe_call, _Left, Name, Args}]}) ->
    [{Name, length(Args) + 1}];
tail_calls(Value) when is_map(Value) ->
    lists:append([tail_calls(Child) || Child <- maps:values(Value)]);
tail_calls(Value) when is_list(Value) ->
    lists:append([tail_calls(Child) || Child <- Value]);
tail_calls(_Value) ->
    [].

bind_parameters([], Counter, Names, Env) ->
    {lists:reverse(Names), Env, Counter};
bind_parameters([Param | Rest], Counter, Names, Env) ->
    TerraName = maps:get(name, Param),
    ErlangName = variable_name(TerraName, Counter),
    bind_parameters(Rest, Counter + 1, [ErlangName | Names],
                    maps:put(TerraName, {direct, ErlangName}, Env)).

generate_statements([], Env, Counter, _Level, _FunctionName) ->
    {[], Env, Counter};
generate_statements([Statement | Rest], Env, Counter, Level, FunctionName) ->
    {Code, NewEnv, NextCounter} =
        generate_statement(Statement, Env, Counter, Level, FunctionName),
    {Remaining, FinalEnv, FinalCounter} =
        generate_statements(Rest, NewEnv, NextCounter, Level, FunctionName),
    {[Code | Remaining], FinalEnv, FinalCounter}.

generate_statement(#{kind := variable, name := Name, value := Value} = Statement,
                   Env, Counter, Level, FunctionName) ->
    ErlangName = variable_name(Name, Counter),
    ValueCode = expression(Value, Env),
    Eval = maps:get(eval, Statement, runtime),
    Scope = maps:get(scope, Statement, local),
    Concurrency = maps:get(concurrency, Statement, shared),
    case {Scope, Eval, Concurrency} of
        {_AnyScope, computed, _AnyConcurrency} ->
            {[indent(Level), ErlangName, " = fun() -> ", ValueCode, " end"],
             maps:put(Name, {computed, ErlangName}, Env), Counter + 1};
        {global, _AnyEval, atomic} ->
            {[indent(Level), ErlangName, " = terra_global_atomic(",
              io_lib:format("~p", [Name]), ", fun() -> ", ValueCode, " end)"],
             maps:put(Name, {atomic, ErlangName}, Env), Counter + 1};
        {_AnyScope, _AnyEval, atomic} ->
            {[indent(Level), ErlangName, " = terra_atomic(", ValueCode, ")"],
             maps:put(Name, {atomic, ErlangName}, Env), Counter + 1};
        {_AnyScope, _AnyEval, thread_local} ->
            Key = {FunctionName, Name, Counter},
            {[indent(Level), ErlangName, " = terra_thread_local(",
              io_lib:format("~p", [Key]), ", fun() -> ", ValueCode, " end)"],
             maps:put(Name, {direct, ErlangName}, Env), Counter + 1};
        {global, _AnyEval, _AnyConcurrency} ->
            {[indent(Level), ErlangName, " = terra_global(",
              io_lib:format("~p", [Name]), ", fun() -> ", ValueCode, " end)"],
             maps:put(Name, {direct, ErlangName}, Env), Counter + 1};
        {_AnyScope, lazy, _AnyConcurrency} ->
            {[indent(Level), ErlangName, " = fun() -> ", ValueCode, " end"],
             maps:put(Name, {lazy, ErlangName}, Env), Counter + 1};
        _ ->
            {[indent(Level), ErlangName, " = ", ValueCode],
             maps:put(Name, {direct, ErlangName}, Env), Counter + 1}
    end;
generate_statement(#{kind := multi_binding, scope := global, bindings := Bindings,
                     value := Value},
                   Env, Counter, Level, _FunctionName) ->
    {Names, NewEnv, NextCounter} = bind_result_names(Bindings, Counter, Env, []),
    Key = {multi, [maps:get(name, Binding) || Binding <- Bindings]},
    {[indent(Level), "{", lists:join(", ", Names), "} = terra_global(",
      io_lib:format("~p", [Key]), ", fun() -> ", expression(Value, Env), " end)"],
     NewEnv, NextCounter};
generate_statement(#{kind := multi_binding, bindings := Bindings, value := Value},
                   Env, Counter, Level, _FunctionName) ->
    {Names, NewEnv, NextCounter} = bind_result_names(Bindings, Counter, Env, []),
    {[indent(Level), "{", lists:join(", ", Names), "} = ", expression(Value, Env)],
     NewEnv, NextCounter};
generate_statement(#{kind := call, name := stdout, args := Args},
                   Env, Counter, Level, _FunctionName) ->
    Values = [expression(Arg, Env) || Arg <- Args],
    {[indent(Level), "terra_stdout([", lists:join(", ", Values), "])"],
     Env, Counter};
generate_statement(#{kind := pointer_write, pointer := Pointer, value := Value},
                   Env, Counter, Level, _FunctionName) ->
    {[indent(Level), "terra_pointer_write(", expression(Pointer, Env), ", ",
      expression(Value, Env), ")"], Env, Counter};
generate_statement(#{kind := call, name := Name, args := Args,
                     invocation := Invocation} = Statement,
                   Env, Counter, Level, _FunctionName) ->
    Call = function_call(Name, Args, Env),
    Invoked = case Invocation of
                  once -> ["terra_once(", io_lib:format("~p", [Name]),
                           ", fun() -> ", Call, " end)"];
                  repeated -> Call
              end,
    Code = case maps:get(propagation, Statement, normal) of
               'try' -> ["terra_try(fun() -> ", Invoked, " end)"];
               normal -> Invoked
           end,
    {[indent(Level), Code], Env, Counter};
generate_statement(#{kind := return, values := [{call, Name, Args}]}, Env, Counter,
                   Level, _FunctionName) when is_list(Name) ->
    TailArgs = [expression(Arg, Env) || Arg <- Args],
    Code = ["throw({terra_tail_call, ", io_lib:format("~p", [Name]), ", [",
            lists:join(", ", TailArgs), "]})"],
    {[indent(Level), Code], Env, Counter};
generate_statement(#{kind := return, values := [{try_call, Name, Args}]}, Env, Counter,
                   Level, _FunctionName) ->
    TailArgs = [expression(Arg, Env) || Arg <- Args],
    Code = ["throw({terra_tail_call, ", io_lib:format("~p", [Name]), ", [",
            lists:join(", ", TailArgs), "]})"],
    {[indent(Level), Code], Env, Counter};
generate_statement(#{kind := return,
                     values := [{pipe_call, Left, Name, Args}]}, Env, Counter,
                   Level, _FunctionName) ->
    TailArgs = [expression(Left, Env) | [expression(Arg, Env) || Arg <- Args]],
    Code = ["throw({terra_tail_call, ", io_lib:format("~p", [Name]), ", [",
            lists:join(", ", TailArgs), "]})"],
    {[indent(Level), Code], Env, Counter};
generate_statement(#{kind := return, values := Values}, Env, Counter,
                   Level, _FunctionName) ->
    Value = return_expression(Values, Env),
    {[indent(Level), "throw({terra_return, ", Value, "})"], Env, Counter};
generate_statement(#{kind := 'if', branches := Branches, else_branch := Else},
                   Env, Counter, Level, FunctionName) ->
    {Code, NextCounter} = generate_if(Branches, Else, Env, Counter, Level,
                                      FunctionName),
    {Code, Env, NextCounter};
generate_statement(#{kind := unless, condition := Condition,
                     statements := Statements, else_branch := Else},
                   Env, Counter, Level, FunctionName) ->
    {Body, _BodyEnv, Counter1} =
        generate_statements(Statements, Env, Counter, Level + 2, FunctionName),
    {ElseCode, Counter2} = generate_optional_block(Else, Env, Counter1,
                                                   Level + 2, FunctionName),
    Code = [indent(Level), "case ", expression(Condition, Env), " of\n",
            indent(Level + 1), "false ->\n", block(Body, Level + 2), ";\n",
            indent(Level + 1), "true ->\n", ElseCode, "\n",
            indent(Level), "end"],
    {Code, Env, Counter2};
generate_statement(#{kind := switch, subject := Subject, cases := Cases},
                   Env, Counter, Level, FunctionName) ->
    SubjectName = variable_name("switch_subject", Counter),
    {SwitchCode, NextCounter} =
        generate_switch_cases(Cases, SubjectName, Env, Counter + 1,
                              Level + 1, FunctionName),
    {[indent(Level), "begin\n",
      indent(Level + 1), SubjectName, " = ", expression(Subject, Env), ",\n",
      SwitchCode, "\n", indent(Level), "end"],
     Env, NextCounter};
generate_statement(#{kind := for_each, binding := Binding, iterable := Iterable,
                     statements := Statements}, Env, Counter, Level, FunctionName) ->
    ElementName = variable_name(Binding, Counter),
    ItName = variable_name("it", Counter + 1),
    LoopEnv = maps:put("it", {direct, ItName},
                       maps:put(Binding, {direct, ElementName}, Env)),
    {Body, _BodyEnv, NextCounter} =
        generate_statements(Statements, LoopEnv, Counter + 2, Level + 1, FunctionName),
    {[indent(Level), "terra_for_each(", expression(Iterable, Env),
      ", fun(", ElementName, ", ", ItName, ") ->\n",
      block(Body, Level + 1), "\n", indent(Level), "end)"], Env, NextCounter};
generate_statement(#{kind := 'for', iterator := {call, range, [Limit]},
                     statements := Statements}, Env, Counter, Level, FunctionName) ->
    ItName = variable_name("it", Counter),
    LoopEnv = maps:put("it", {direct, ItName}, Env),
    {Body, _BodyEnv, NextCounter} =
        generate_statements(Statements, LoopEnv, Counter + 1, Level + 1, FunctionName),
    {[indent(Level), "terra_for_range(", expression(Limit, Env),
      ", fun(", ItName, ") ->\n", block(Body, Level + 1), "\n",
      indent(Level), "end)"], Env, NextCounter};
generate_statement(#{kind := while, condition := Condition, statements := Statements},
                   Env, Counter, Level, FunctionName) ->
    generate_condition_loop("terra_while", Condition, Statements, Env, Counter,
                            Level, FunctionName);
generate_statement(#{kind := do_while, condition := Condition, statements := Statements},
                   Env, Counter, Level, FunctionName) ->
    generate_condition_loop("terra_do_while", Condition, Statements, Env, Counter,
                            Level, FunctionName);
generate_statement(#{kind := Kind}, _Env, _Counter, _Level, _FunctionName) ->
    throw({backend_error, {unsupported_statement, Kind}}).

generate_condition_loop(Helper, Condition, Statements, Env, Counter,
                        Level, FunctionName) ->
    ItName = variable_name("it", Counter),
    LoopEnv = maps:put("it", {direct, ItName}, Env),
    {Body, _BodyEnv, NextCounter} =
        generate_statements(Statements, LoopEnv, Counter + 1, Level + 1, FunctionName),
    Code = [indent(Level), Helper, "(fun(", ItName, ") -> ",
            expression(Condition, LoopEnv),
            " end, fun(", ItName, ") ->\n", block(Body, Level + 1), "\n",
            indent(Level), "end)"],
    {Code, Env, NextCounter}.

generate_if([Branch | Rest], Else, Env, Counter, Level, FunctionName) ->
    {Body, _BodyEnv, Counter1} =
        generate_statements(maps:get(statements, Branch), Env, Counter,
                            Level + 2, FunctionName),
    {Fallback, Counter2} = case Rest of
                               [] -> generate_optional_block(Else, Env, Counter1,
                                                             Level + 2, FunctionName);
                               _ -> generate_if(Rest, Else, Env, Counter1,
                                                Level + 2, FunctionName)
                           end,
    {[indent(Level), "case ", expression(maps:get(condition, Branch), Env), " of\n",
      indent(Level + 1), "true ->\n", block(Body, Level + 2), ";\n",
      indent(Level + 1), "false ->\n", Fallback, "\n",
      indent(Level), "end"], Counter2}.

generate_optional_block(none, _Env, Counter, Level, _FunctionName) ->
    {[indent(Level), "ok"], Counter};
generate_optional_block(Statements, Env, Counter, Level, FunctionName) ->
    {Body, _BodyEnv, NextCounter} =
        generate_statements(Statements, Env, Counter, Level, FunctionName),
    {block(Body, Level), NextCounter}.

generate_switch_cases([], _SubjectName, _Env, Counter, Level, _FunctionName) ->
    {[indent(Level), "ok"], Counter};
generate_switch_cases([#{pattern := default, statements := Statements}],
                      _SubjectName, Env, Counter, Level, FunctionName) ->
    {Body, _BodyEnv, NextCounter} =
        generate_statements(Statements, Env, Counter, Level, FunctionName),
    {block(Body, Level), NextCounter};
generate_switch_cases([#{pattern := {variant_pattern, EnumName, VariantName, Bindings},
                         statements := Statements} | Rest],
                      SubjectName, Env, Counter, Level, FunctionName) ->
    {Pattern, PatternEnv, Counter1} =
        generate_variant_pattern(EnumName, VariantName, Bindings, Env, Counter),
    {Body, _BodyEnv, Counter2} =
        generate_statements(Statements, PatternEnv, Counter1, Level + 2, FunctionName),
    {Fallback, NextCounter} =
        generate_switch_cases(Rest, SubjectName, Env, Counter2,
                              Level + 2, FunctionName),
    Code = [indent(Level), "case ", SubjectName, " of\n",
            indent(Level + 1), Pattern, " ->\n", block(Body, Level + 2),
            ";\n", indent(Level + 1), "_ ->\n", Fallback, "\n",
            indent(Level), "end"],
    {Code, NextCounter};
generate_switch_cases([#{pattern := Pattern, statements := Statements} | Rest],
                      SubjectName, Env, Counter, Level, FunctionName) ->
    {Body, _BodyEnv, Counter1} =
        generate_statements(Statements, Env, Counter, Level + 2, FunctionName),
    {Fallback, NextCounter} =
        generate_switch_cases(Rest, SubjectName, Env, Counter1,
                              Level + 2, FunctionName),
    Code = [indent(Level), "case ", expression(Pattern, Env), " of\n",
            indent(Level + 1), SubjectName, " ->\n", block(Body, Level + 2),
            ";\n", indent(Level + 1), "_ ->\n", Fallback, "\n",
            indent(Level), "end"],
    {Code, NextCounter}.

generate_variant_pattern(EnumName, VariantName, Bindings, Env, Counter) ->
    Base = [["'$terra_enum' := ", io_lib:format("~p", [list_to_atom(EnumName)])],
            ["tag := ", io_lib:format("~p", [list_to_atom(VariantName)])]],
    {Fields, PatternEnv, NextCounter} =
        generate_pattern_bindings(Bindings, Env, Counter, []),
    {["#{", lists:join(", ", Base ++ Fields), "}"], PatternEnv, NextCounter}.

generate_pattern_bindings([], Env, Counter, Acc) ->
    {lists:reverse(Acc), Env, Counter};
generate_pattern_bindings([#{binding := ignore} | Rest], Env, Counter, Acc) ->
    generate_pattern_bindings(Rest, Env, Counter, Acc);
generate_pattern_bindings([#{name := Field, binding := Name} | Rest],
                          Env, Counter, Acc) ->
    ErlangName = variable_name(Name, Counter),
    Entry = [io_lib:format("~p", [list_to_atom(Field)]), " := ", ErlangName],
    generate_pattern_bindings(Rest, maps:put(Name, {direct, ErlangName}, Env),
                              Counter + 1, [Entry | Acc]).

bind_result_names([], Counter, Env, Acc) ->
    {lists:reverse(Acc), Env, Counter};
bind_result_names([Binding | Rest], Counter, Env, Acc) ->
    Name = maps:get(name, Binding),
    ErlangName = variable_name(Name, Counter),
    bind_result_names(Rest, Counter + 1,
                      maps:put(Name, {direct, ErlangName}, Env),
                      [ErlangName | Acc]).

expression({int, Value}, _Env) -> integer_to_list(Value);
expression({sint, Value}, _Env) -> integer_to_list(Value);
expression({float, Value}, _Env) -> float_to_list(Value, [short]);
expression({string, Value}, _Env) -> io_lib:format("~p", [Value]);
expression({char, Value}, _Env) -> io_lib:format("$~c", [Value]);
expression({bool, true}, _Env) -> "true";
expression({bool, false}, _Env) -> "false";
expression({atom, Value}, _Env) -> io_lib:format("~p", [Value]);
expression({list, Values}, Env) ->
    ["[", lists:join(", ", [expression(Value, Env) || Value <- Values]), "]"];
expression({tuple, Values}, Env) ->
    ["{", lists:join(", ", [expression(Value, Env) || Value <- Values]), "}"];
expression({map, Pairs}, Env) ->
    Entries = [[expression(Key, Env), " => ", expression(Value, Env)]
               || {Key, Value} <- Pairs],
    ["#{", lists:join(", ", Entries), "}"];
expression({record, Name, Fields}, Env) ->
    Entries = [[io_lib:format("~p", [list_to_atom(Field)]), " => ", expression(Value, Env)]
               || {Field, Value} <- Fields],
    ["#{'$terra_struct' => ", io_lib:format("~p", [list_to_atom(Name)]),
     case Entries of [] -> ""; _ -> [", ", lists:join(", ", Entries)] end, "}"];
expression({variant, EnumName, VariantName, Fields}, Env) ->
    Entries = [[io_lib:format("~p", [list_to_atom(Field)]), " => ", expression(Value, Env)]
               || {Field, Value} <- Fields],
    ["#{'$terra_enum' => ", io_lib:format("~p", [list_to_atom(EnumName)]),
     ", tag => ", io_lib:format("~p", [list_to_atom(VariantName)]),
     case Entries of [] -> ""; _ -> [", ", lists:join(", ", Entries)] end, "}"];
expression({pointer_new, Value}, Env) ->
    ["terra_pointer_new(", expression(Value, Env), ")"];
expression({pointer_read, Value}, Env) ->
    ["terra_pointer_read(", expression(Value, Env), ")"];
expression({var_ref, Name}, Env) ->
    case maps:find(Name, Env) of
        {ok, {direct, ErlangName}} -> ErlangName;
        {ok, {lazy, ErlangName}} -> [ErlangName, "()"];
        {ok, {computed, ErlangName}} -> [ErlangName, "()"];
        {ok, {atomic, ErlangName}} -> ["atomics:get(", ErlangName, ", 1)"];
        error -> throw({backend_error, {unknown_codegen_variable, Name}})
    end;
expression({member, Value, Name}, Env) ->
    ["terra_member(", expression(Value, Env), ", ", io_lib:format("~p", [list_to_atom(Name)]), ")"];
expression({unary, bang, Value}, Env) ->
    ["(not ", expression(Value, Env), ")"];
expression({unary, minus, Value}, Env) ->
    ["(-", expression(Value, Env), ")"];
expression({binary, Op, Left, Right}, Env) ->
    ["(", expression(Left, Env), " ", operator(Op), " ", expression(Right, Env), ")"];
expression({try_call, Name, Args}, Env) ->
    ["terra_try(fun() -> ", function_call(Name, Args, Env), " end)"];
expression({pipe_call, Left, Name, Args}, Env) ->
    ["terra_pipe(fun() -> ", expression(Left, Env), " end, ",
     "fun(TerraPipeValue) -> ", pipe_function_call(Name, Args, Env), " end)"];
expression({call, Name, Args}, Env) -> function_call(Name, Args, Env).

pipe_function_call(Name, Args, Env) ->
    [function_name(Name), "(TerraPipeValue",
     [[", ", expression(Arg, Env)] || Arg <- Args], ")"].

function_call(Name, Args, Env) when is_list(Name) ->
    [function_name(Name), "(",
     lists:join(", ", [expression(Arg, Env) || Arg <- Args]), ")"];
function_call(tuple, Args, Env) ->
    ["{", lists:join(", ", [expression(Arg, Env) || Arg <- Args]), "}"];
function_call(list, Args, Env) ->
    ["[", lists:join(", ", [expression(Arg, Env) || Arg <- Args]), "]"];
function_call(map, [], _Env) -> "#{}";
function_call(restricted_map, [Capacity], Env) ->
    ["terra_restricted_map(", expression(Capacity, Env), ", #{})"];
function_call(restricted_map, [Capacity, Value], Env) ->
    ["terra_restricted_map(", expression(Capacity, Env), ", ",
     expression(Value, Env), ")"];
function_call(state, [], _Env) -> "#{}";
function_call(string, [Arg], Env) ->
    ["unicode:characters_to_binary(", expression(Arg, Env), ")"];
function_call(number, [Arg], Env) -> expression(Arg, Env);
function_call(int, [Arg], Env) -> ["terra_to_int(", expression(Arg, Env), ")"];
function_call(sint, [Arg], Env) -> ["terra_to_sint(", expression(Arg, Env), ")"];
function_call(float, [Arg], Env) -> ["terra_to_float(", expression(Arg, Env), ")"];
function_call(Name, [Arg], Env) when Name == atom; Name == bool -> expression(Arg, Env);
function_call(range, [Limit], Env) ->
    ["terra_range(", expression(Limit, Env), ")"];
function_call(Name, _Args, _Env) ->
    throw({backend_error, {unsupported_constructor, Name}}).

return_expression([Value], Env) -> expression(Value, Env);
return_expression(Values, Env) ->
    ["{", lists:join(", ", [expression(Value, Env) || Value <- Values]), "}"].

default_value([Type]) -> default_type(Type);
default_value(Types) ->
    ["{", lists:join(", ", [default_type(Type) || Type <- Types]), "}"].

default_type(number) -> "0";
default_type(int) -> "0";
default_type(sint) -> "0";
default_type(float) -> "0.0";
default_type(string) -> "<<>>";
default_type(bool) -> "false";
default_type(atom) -> "undefined";
default_type(list) -> "[]";
default_type(tuple) -> "{}";
default_type(map) -> "#{}";
default_type(restricted_map) -> "{terra_restricted_map, 0, #{}}";
default_type(_) -> "undefined".

operator(plus) -> "+";
operator(minus) -> "-";
operator(times) -> "*";
operator(div_op) -> "/";
operator(eq_eq) -> "==";
operator(not_eq) -> "/=";
operator(lt) -> "<";
operator(lt_eq) -> "=<";
operator(gt) -> ">";
operator(gt_eq) -> ">=";
operator(and_and) -> "andalso";
operator(or_or) -> "orelse".

function_name(Name) -> "terra_fn_" ++ sanitize_lower(Name).

tail_step_name(Name) -> function_name(Name) ++ "_tail_step".

variable_name(Name, Counter) ->
    "Terra_" ++ sanitize_title(Name) ++ "_" ++ integer_to_list(Counter).

sanitize_lower(Value) ->
    [sanitize_char(C) || C <- string:lowercase(Value)].

sanitize_title(Value) ->
    [sanitize_char(C) || C <- Value].

sanitize_char(C) when C >= $a, C =< $z -> C;
sanitize_char(C) when C >= $A, C =< $Z -> C;
sanitize_char(C) when C >= $0, C =< $9 -> C;
sanitize_char($_) -> $_;
sanitize_char(_) -> $_.

join_expressions(Expressions) -> lists:join(",\n", Expressions).

block([], Level) -> [indent(Level), "ok"];
block(Expressions, _Level) -> join_expressions(Expressions).

indent(Level) -> lists:duplicate(Level * 4, $\s).

runtime_helpers() ->
    "terra_args(Value) when is_binary(Value) -> Value;\n"
    "terra_args(Value) -> unicode:characters_to_binary(Value).\n\n"
    "terra_stdout([]) -> io:nl();\n"
    "terra_stdout(Values) ->\n"
    "    lists:foreach(fun terra_stdout_value/1, Values),\n"
    "    ok.\n\n"
    "terra_stdout_value(Value) when is_binary(Value) -> io:format(\"~ts~n\", [Value]);\n"
    "terra_stdout_value(Value) -> io:format(\"~tp~n\", [Value]).\n\n"
    "terra_to_int(Value) when is_integer(Value) -> Value;\n"
    "terra_to_int(Value) when is_float(Value) -> trunc(Value).\n\n"
    "terra_to_sint(Value) when is_integer(Value) -> Value;\n"
    "terra_to_sint(Value) when is_float(Value) -> trunc(Value).\n\n"
    "terra_to_float(Value) when is_float(Value) -> Value;\n"
    "terra_to_float(Value) when is_integer(Value) -> float(Value).\n\n"
    "terra_global(Key, Fun) ->\n"
    "    StoreKey = {?MODULE, terra_global, Key},\n"
    "    case persistent_term:get(StoreKey, terra_missing) of\n"
    "        {done, Value} -> Value;\n"
    "        terra_missing -> terra_initialize_global(StoreKey, Fun)\n"
    "    end.\n\n"
    "terra_initialize_global(StoreKey, Fun) ->\n"
    "    RunningKey = {?MODULE, terra_global_running, StoreKey},\n"
    "    case erlang:get(RunningKey) of\n"
    "        true -> erlang:error({terra_global_reentrant, StoreKey});\n"
    "        undefined ->\n"
    "            erlang:put(RunningKey, true),\n"
    "            try\n"
    "                global:trans({StoreKey, self()}, fun() ->\n"
    "                    case persistent_term:get(StoreKey, terra_missing) of\n"
    "                        {done, Existing} -> Existing;\n"
    "                        terra_missing ->\n"
    "                            Value = Fun(),\n"
    "                            persistent_term:put(StoreKey, {done, Value}),\n"
    "                            Value\n"
    "                    end\n"
    "                end)\n"
    "            after erlang:erase(RunningKey) end\n"
    "    end.\n\n"
    "terra_thread_local(Key, Fun) ->\n"
    "    StoreKey = {?MODULE, terra_thread_local, Key},\n"
    "    case erlang:get(StoreKey) of\n"
    "        undefined ->\n"
    "            erlang:put(StoreKey, running),\n"
    "            try\n"
    "                Value = Fun(),\n"
    "                erlang:put(StoreKey, {done, Value}),\n"
    "                Value\n"
    "            catch\n"
    "                Class:Reason:Stacktrace ->\n"
    "                    erlang:erase(StoreKey),\n"
    "                    erlang:raise(Class, Reason, Stacktrace)\n"
    "            end;\n"
    "        running -> erlang:error({terra_thread_local_reentrant, Key});\n"
    "        {done, Value} -> Value\n"
    "    end.\n\n"
    "terra_atomic(Value) when is_integer(Value) ->\n"
    "    Ref = atomics:new(1, [{signed, true}]),\n"
    "    ok = atomics:put(Ref, 1, Value),\n"
    "    Ref.\n\n"
    "terra_global_atomic(Key, Fun) ->\n"
    "    terra_global({atomic, Key}, fun() -> terra_atomic(Fun()) end).\n\n"
    "terra_once(Key, Fun) ->\n"
    "    StoreKey = {?MODULE, terra_once, Key},\n"
    "    case erlang:get(StoreKey) of\n"
    "        undefined ->\n"
    "            erlang:put(StoreKey, running),\n"
    "            try\n"
    "                Value = Fun(),\n"
    "                erlang:put(StoreKey, {done, Value}),\n"
    "                Value\n"
    "            catch\n"
    "                Class:Reason:Stacktrace ->\n"
    "                    erlang:erase(StoreKey),\n"
    "                    erlang:raise(Class, Reason, Stacktrace)\n"
    "            end;\n"
    "        running -> erlang:error({terra_once_reentrant, Key});\n"
    "        {done, Value} -> Value\n"
    "    end.\n\n"
    "terra_try(Fun) ->\n"
    "    try Fun()\n"
    "    catch\n"
    "        Class:Reason:Stacktrace -> erlang:raise(Class, Reason, Stacktrace)\n"
    "    end.\n\n"
    "terra_pipe(ValueFun, NextFun) ->\n"
    "    terra_try(fun() -> NextFun(ValueFun()) end).\n\n"
    "terra_range(Limit) when Limit =< 0 -> [];\n"
    "terra_range(Limit) -> lists:seq(0, trunc(Limit) - 1).\n\n"
    "terra_for_range(Limit, Fun) -> lists:foreach(Fun, terra_range(Limit)).\n\n"
    "terra_for_each(Value, Fun) ->\n"
    "    Items = terra_iterable(Value),\n"
    "    Indexed = lists:zip(Items, lists:seq(0, length(Items) - 1)),\n"
    "    lists:foreach(fun({Item, Index}) -> Fun(Item, Index) end, Indexed).\n\n"
    "terra_iterable({terra_restricted_map, _Capacity, Value}) -> maps:to_list(Value);\n"
    "terra_iterable(Value) when is_list(Value) -> Value;\n"
    "terra_iterable(Value) when is_tuple(Value) -> tuple_to_list(Value);\n"
    "terra_iterable(Value) when is_map(Value) -> maps:to_list(Value);\n"
    "terra_iterable(Value) when is_binary(Value) -> binary_to_list(Value).\n\n"
    "terra_while(Condition, Body) -> terra_while(Condition, Body, 0).\n"
    "terra_while(Condition, Body, It) ->\n"
    "    case Condition(It) of\n"
    "        true -> Body(It), terra_while(Condition, Body, It + 1);\n"
    "        false -> ok\n"
    "    end.\n\n"
    "terra_do_while(Condition, Body) -> terra_do_while(Condition, Body, 0).\n"
    "terra_do_while(Condition, Body, It) ->\n"
    "    Body(It),\n"
    "    case Condition(It) of\n"
    "        true -> terra_do_while(Condition, Body, It + 1);\n"
    "        false -> ok\n"
    "    end.\n\n"
    "terra_restricted_map(Capacity, Value)\n"
    "  when is_integer(Capacity), Capacity >= 0, is_map(Value), map_size(Value) =< Capacity ->\n"
    "    {terra_restricted_map, Capacity, Value};\n"
    "terra_restricted_map(Capacity, Value) ->\n"
    "    erlang:error({invalid_restricted_map, Capacity, Value}).\n\n"
    "terra_member({terra_restricted_map, _Capacity, Value}, count) -> map_size(Value);\n"
    "terra_member({terra_restricted_map, _Capacity, Value}, members) -> maps:to_list(Value);\n"
    "terra_member({terra_restricted_map, _Capacity, Value}, Key) -> maps:get(Key, Value);\n"
    "terra_member(Value, count) when is_map(Value) -> map_size(Value);\n"
    "terra_member(Value, members) when is_map(Value) -> maps:to_list(Value);\n"
    "terra_member(Value, Key) when is_map(Value) -> maps:get(Key, Value);\n"
    "terra_member(Value, Key) -> erlang:error({cannot_access_member, Key, Value}).\n".

pointer_runtime_helpers() ->
    "\nterra_region_start(Capacity) ->\n"
    "    Ref = make_ref(),\n"
    "    Key = {?MODULE, terra_region, Ref},\n"
    "    erlang:put(Key, #{capacity => Capacity, next => 0, values => #{}}),\n"
    "    erlang:put({?MODULE, terra_current_region}, Ref),\n"
    "    Ref.\n\n"
    "terra_region_cleanup(Ref) ->\n"
    "    erlang:erase({?MODULE, terra_region, Ref}),\n"
    "    case erlang:get({?MODULE, terra_current_region}) of\n"
    "        Ref -> erlang:erase({?MODULE, terra_current_region});\n"
    "        _ -> ok\n"
    "    end,\n"
    "    ok.\n\n"
    "terra_pointer_new(Value) ->\n"
    "    case erlang:get({?MODULE, terra_current_region}) of\n"
    "        undefined -> erlang:error(terra_pointer_outside_region);\n"
    "        Ref ->\n"
    "            Key = {?MODULE, terra_region, Ref},\n"
    "            Region = erlang:get(Key),\n"
    "            Slot = maps:get(next, Region),\n"
    "            terra_region_require_capacity(maps:get(capacity, Region), Slot),\n"
    "            Values = maps:put(Slot, Value, maps:get(values, Region)),\n"
    "            erlang:put(Key, Region#{next := Slot + 1, values := Values}),\n"
    "            {terra_pointer, self(), Ref, Slot}\n"
    "    end.\n\n"
    "terra_region_require_capacity({auto, _Estimate}, _Slot) -> ok;\n"
    "terra_region_require_capacity(Capacity, Slot) when Slot < Capacity -> ok;\n"
    "terra_region_require_capacity(Capacity, _Slot) ->\n"
    "    erlang:error({terra_temporary_region_full, Capacity}).\n\n"
    "terra_pointer_read(Pointer) ->\n"
    "    {_Key, Slot, Region} = terra_pointer_region(Pointer),\n"
    "    case maps:find(Slot, maps:get(values, Region)) of\n"
    "        {ok, Value} -> Value;\n"
    "        error -> erlang:error(terra_dangling_pointer)\n"
    "    end.\n\n"
    "terra_pointer_write(Pointer, Value) ->\n"
    "    {Key, Slot, Region} = terra_pointer_region(Pointer),\n"
    "    Values = maps:put(Slot, Value, maps:get(values, Region)),\n"
    "    erlang:put(Key, Region#{values := Values}),\n"
    "    Value.\n\n"
    "terra_pointer_region({terra_pointer, Owner, Ref, Slot}) when Owner == self() ->\n"
    "    Key = {?MODULE, terra_region, Ref},\n"
    "    case erlang:get(Key) of\n"
    "        Region when is_map(Region) -> {Key, Slot, Region};\n"
    "        _ -> erlang:error(terra_dangling_pointer)\n"
    "    end;\n"
    "terra_pointer_region({terra_pointer, _Owner, _Ref, _Slot}) ->\n"
    "    erlang:error(terra_cross_process_pointer);\n"
    "terra_pointer_region(_) -> erlang:error(terra_invalid_pointer).\n".
