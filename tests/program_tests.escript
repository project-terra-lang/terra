#!/usr/bin/env escript

main(_Args) ->
    code:add_pathz("./ebin"),
    Cases = [{"main ok", "tests/programs/main_ok.terra", fun expect_main_ok/1},
             {"functions", "tests/programs/functions.terra", fun expect_functions/1},
             {"control flow", "tests/programs/control_flow.terra", fun expect_control_flow/1},
             {"loops and recursion", "tests/programs/loops.terra", fun expect_loops/1},
             {"loop condition", "tests/programs/loops_bad_condition.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main",
                                      {expected_boolean_condition, int, {int, 10}}}}
              end},
             {"loop iterable", "tests/programs/loops_bad_iterable.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main",
                                      {expected_iterable, int, {int, 10}}}}
              end},
             {"non-boolean condition", "tests/programs/control_bad_condition.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main",
                                      {expected_boolean_condition, int, {int, 1}}}}
              end},
             {"non-exhaustive switch", "tests/programs/control_non_exhaustive.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main", non_exhaustive_switch}}
              end},
             {"bad function return", "tests/programs/functions_bad_return.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "T",
                                      {return_type_mismatch,
                                       [string, number], [int, string]}}}
              end},
             {"bad multi binding", "tests/programs/functions_bad_binding.terra",
              fun(Result) ->
                  Result =:= {error, {in_function, "Main",
                                      {return_type_mismatch,
                                       [number, string], [string, number]}}}
              end},
             {"top level code", "tests/programs/top_level_code.terra",
             fun(Result) ->
                  case Result of
                      {error, {with_span, {variable_requires_scope, local, _Tokens}, Span}} ->
                          maps:get(start, Span) == #{line => 1, column => 1, offset => 0};
                      {error, {variable_requires_scope, local, _Tokens}} -> true;
                      _ -> false
                  end
              end},
             {"missing main", "tests/programs/missing_main.terra",
              fun(Result) -> Result =:= {error, missing_entry_point} end},
             {"bad signature", "tests/programs/main_bad_signature.terra",
              fun(Result) ->
                  Result =:= {error, {invalid_entry_point_signature,
                                      "function strict *SInt Main(*String Args) { ... }"}}
              end},
             {"void return type", "tests/programs/void_return_type.terra",
              fun(Result) -> Result =:= {error, void_return_type} end},
             {"missing return type", "tests/programs/missing_return_type.terra",
              fun expect_missing_return_type/1},
             {"empty return", "tests/programs/empty_return.terra",
              fun expect_empty_return/1},
             {"missing return", "tests/programs/missing_return.terra",
              fun expect_missing_return/1},
             {"partial branch return", "tests/programs/partial_branch_return.terra",
              fun expect_partial_branch_return/1},
             {"unreachable after return", "tests/programs/unreachable_after_return.terra",
              fun expect_unreachable_after_return/1},
             {"duplicate parameter", "tests/programs/duplicate_param.terra",
              fun(Result) -> Result =:= {error, {duplicate_variable, "Args"}} end},
             {"duplicate multi binding", "tests/programs/duplicate_multi_binding.terra",
              fun expect_duplicate_binding/1},
             {"duplicate destructure binding", "tests/programs/duplicate_destructure_binding.terra",
              fun expect_duplicate_binding/1},
             {"duplicate case", "tests/programs/duplicate_case.terra",
              fun expect_duplicate_case/1},
             {"invalid loop shadowing", "tests/programs/invalid_loop_shadowing.terra",
              fun expect_invalid_loop_shadowing/1},
             {"expression precedence and boolean operators",
              "tests/programs/expression_precedence_bool.terra",
              fun expect_expression_precedence/1},
             {"numeric rules", "tests/programs/numeric_rules.terra",
              fun(Result) -> element(1, Result) =:= ok end},
             {"SInt accepts Int values", "tests/programs/sint_accepts_int.terra",
             fun(Result) -> element(1, Result) =:= ok end},
             {"invalid numeric conversion", "tests/programs/numeric_bad_conversion.terra",
              fun expect_invalid_numeric_conversion/1},
             {"conversion helpers", "tests/programs/conversions.terra",
              fun expect_conversions/1},
             {"conversion helper argument type",
              "tests/programs/conversion_bad_argument.terra",
              fun expect_conversion_bad_argument/1},
             {"conversion helper scalar type",
              "tests/programs/conversion_bad_to_string.terra",
              fun expect_conversion_bad_to_string/1},
             {"console and formatting helpers", "examples/console_helpers.terra",
              fun expect_console_helpers/1},
             {"format requires a String template",
              "tests/programs/format_bad_argument.terra",
              fun expect_format_bad_argument/1},
             {"format requires a template",
              "tests/programs/format_missing_template.terra",
              fun expect_format_missing_template/1},
             {"once-only calls require zero arguments",
              "tests/programs/once_requires_zero_args.terra",
              fun expect_once_requires_zero_args/1},
             {"global initializer is closed", "tests/programs/global_captures_local.terra",
              fun expect_global_captures_local/1},
             {"invalid global computed storage",
              "tests/programs/global_computed_invalid.terra",
              fun expect_global_computed_invalid/1},
             {"invalid atomic Number storage", "tests/programs/atomic_number_invalid.terra",
              fun expect_atomic_number_invalid/1},
             {"duplicate global storage", "tests/programs/duplicate_global.terra",
              fun(Result) -> Result =:= {error, {duplicate_global, "shared"}} end},
             {"warnings remain separate from errors", "tests/programs/warnings.terra",
              fun expect_warnings/1},
             {"restricted map properties", "tests/programs/restricted_map.terra",
              fun expect_restricted_map/1},
             {"restricted map capacity", "tests/programs/restricted_map_overflow.terra",
              fun expect_restricted_map_overflow/1},
             {"immutable updates", "tests/programs/immutable_updates.terra",
              fun expect_immutable_updates/1},
             {"record update field names", "tests/programs/record_update_bad_field.terra",
              fun expect_record_update_bad_field/1},
             {"record update field types", "tests/programs/record_update_bad_type.terra",
              fun expect_record_update_bad_type/1},
             {"user-defined records", "tests/programs/records.terra",
              fun expect_records/1},
             {"record constructor types", "tests/programs/record_bad_constructor.terra",
              fun expect_record_bad_constructor/1},
             {"record field names", "tests/programs/record_unknown_field.terra",
              fun expect_record_unknown_field/1},
             {"record constructors are not pipeline functions",
              "tests/programs/record_pipeline_invalid.terra",
              fun expect_record_pipeline_invalid/1},
             {"tagged enums", "tests/programs/enums.terra", fun expect_enums/1},
             {"inline user types", "tests/programs/inline_user_types.terra",
              fun expect_inline_user_types/1},
             {"enum variant payload types", "tests/programs/enum_bad_variant.terra",
              fun expect_enum_bad_variant/1},
             {"unknown enum variant", "tests/programs/enum_unknown_variant.terra",
              fun expect_enum_unknown_variant/1},
             {"bare enum variants",
              "tests/programs/enum_implicit_variant.terra",
              fun expect_enum_implicit_variant/1},
             {"enum pattern arity", "tests/programs/enum_pattern_arity.terra",
              fun expect_enum_pattern_arity/1},
             {"enum pattern bindings do not leak",
              "tests/programs/enum_pattern_binding_leak.terra",
              fun expect_enum_pattern_binding_leak/1},
             {"enum pattern bindings are unique",
              "tests/programs/enum_pattern_duplicate_binding.terra",
              fun expect_enum_pattern_duplicate_binding/1},
             {"enum pattern payload ignore", "tests/programs/enum_pattern_ignore.terra",
              fun(Result) -> element(1, Result) == ok end},
             {"temporary-region pointers", "tests/programs/pointers.terra",
              fun expect_pointers/1},
             {"nested and strict pointers", "tests/programs/pointer_depth.terra",
              fun expect_pointer_depth/1},
             {"strict pointers require explicit construction",
              "tests/programs/strict_pointer_implicit.terra",
              fun expect_strict_pointer_implicit/1},
             {"strict pointers require exact pointee types",
              "tests/programs/strict_pointer_mismatch.terra",
              fun expect_strict_pointer_mismatch/1},
             {"strict applies only to pointers",
              "tests/programs/strict_non_pointer.terra",
              fun expect_strict_non_pointer/1},
             {"automatic pointer region", "tests/programs/pointer_auto_region.terra",
              fun expect_auto_pointer_region/1},
             {"entry region minimum",
              "tests/programs/region_capacity_too_small.terra",
              fun expect_region_capacity_too_small/1},
             {"region safety limit",
              "tests/programs/region_capacity_too_large.terra",
              fun expect_region_capacity_too_large/1},
             {"temp pointer storage is rejected", "tests/programs/pointer_bad_temp.terra",
              fun expect_bad_temp_pointer/1},
             {"try propagation expressions", "tests/programs/try_success.terra",
              fun expect_try_propagation/1},
             {"try requires function call", "tests/programs/try_invalid.terra",
              fun expect_invalid_try/1},
             {"pipe propagation chain", "tests/programs/pipe_success.terra",
             fun expect_pipe_propagation/1},
             {"pipe requires function call", "tests/programs/pipe_invalid.terra",
              fun expect_invalid_pipe/1},
             {"module-scope global and const declarations",
             "tests/programs/module_declarations.terra",
              fun expect_module_declarations/1},
             {"module imports and exports",
              "tests/programs/imports_exports.terra",
              fun expect_imports_exports/1},
             {"standard library import",
              "tests/programs/std_collection_usage.terra",
              fun expect_std_collection/1},
             {"unexported imported function",
              "tests/programs/import_unexported.terra",
              fun expect_import_unexported/1},
             {"unknown export",
              "tests/programs/export_unknown.terra",
              fun expect_export_unknown/1},
             {"boundary-unsafe export",
              "tests/programs/export_pointer.terra",
              fun expect_export_pointer/1},
             {"selected Erlang FFI call",
              "tests/programs/erlang_ffi.terra",
              fun expect_erlang_ffi/1},
             {"webserver Erlang FFI example",
              "tests/programs/webserver_ffi.terra",
              fun expect_webserver_ffi/1},
             {"undeclared Erlang FFI call",
              "tests/programs/erlang_ffi_undeclared.terra",
              fun expect_erlang_ffi_undeclared/1},
             {"undeclared Erlang FFI module",
              "tests/programs/erlang_ffi_unknown_module.terra",
              fun expect_erlang_ffi_unknown_module/1},
             {"duplicate Erlang FFI declaration",
              "tests/programs/erlang_ffi_duplicate.terra",
              fun expect_erlang_ffi_duplicate/1},
             {"process-local FFI type",
              "tests/programs/erlang_ffi_pointer.terra",
              fun expect_erlang_ffi_pointer/1},
             {"opaque BEAM type constructor",
              "tests/programs/beam_type_constructor.terra",
              fun expect_beam_type_constructor/1},
             {"process primitives",
              "tests/programs/process_primitives.terra",
              fun expect_process_primitives/1},
             {"spawn requires a function call",
              "tests/programs/process_spawn_invalid.terra",
              fun expect_process_spawn_invalid/1},
             {"send requires a PID",
              "tests/programs/process_send_invalid.terra",
              fun expect_process_send_invalid/1},
             {"receive requires a transferable type",
              "tests/programs/process_receive_invalid.terra",
              fun expect_process_receive_invalid/1},
             {"spawn rejects pointer arguments",
              "tests/programs/process_pointer_argument.terra",
              fun expect_process_pointer_argument/1},
             {"top-level local requires function scope",
              "tests/programs/top_level_local.terra",
              fun expect_top_level_local/1},
             {"branch binding does not leak", "tests/programs/branch_binding_leak.terra",
              fun expect_branch_binding_leak/1},
             {"switch binding does not leak", "tests/programs/switch_binding_leak.terra",
              fun expect_switch_binding_leak/1},
             {"loop binding does not leak", "tests/programs/loop_binding_leak.terra",
              fun expect_loop_binding_leak/1},
             {"explicit compiler passes", "tests/programs/main_ok.terra",
              fun expect_passes/1},
             {"complete ast has no raw-token fallbacks",
              "examples/feature_showcase.terra", fun expect_complete_ast/1}],
    Results = [run_case(Case) || Case <- Cases],
    case lists:member(fail, Results) of
        true ->
            io:format("program tests failed~n"),
            halt(1);
        false ->
            io:format("program tests passed~n"),
            ok
    end.

run_case({Name, Path, Expect}) ->
    Result = program:parse_file(Path),
    case Expect(Result) of
        true ->
            io:format("ok - ~s~n", [Name]),
            pass;
        false ->
            io:format("not ok - ~s~n  got: ~p~n", [Name, Result]),
            fail
    end.

expect_main_ok({ok, Program}) ->
    Main = find_function("Main", maps:get(functions, Program)),
    maps:get(kind, Program) == program andalso
    maps:get(entry, Program) == "Main" andalso
    length(maps:get(functions, Program)) == 1 andalso
    maps:get(return_types, Main) == [{strict_pointer, sint}] andalso
    maps:get(params, Main) == [#{type => {pointer, string}, name => "Args"}];
expect_main_ok(_) ->
    false.

expect_functions({ok, Program}) ->
    Functions = maps:get(functions, Program),
    T = find_function("T", Functions),
    Main = find_function("Main", Functions),
    MainStatements = maps:get(statements, Main),
    maps:get(return_types, T) == [string, number] andalso
    count_calls("FunctionA", repeated, MainStatements) == 2 andalso
    count_calls("FunctionA", once, MainStatements) == 1 andalso
    has_multi_binding(MainStatements);
expect_functions(_) ->
    false.

expect_restricted_map({ok, Program}) ->
    Main = find_function("Main", maps:get(functions, Program)),
    Statements = maps:get(statements, Main),
    lists:any(fun(Statement) ->
        maps:get(kind, Statement, none) == variable andalso
        maps:get(type, Statement, none) == restricted_map
    end, Statements);
expect_restricted_map(_) ->
    false.

expect_restricted_map_overflow({error, {in_function, "Main",
                                        {restricted_map_capacity_exceeded, 1, 2}}}) -> true;
expect_restricted_map_overflow(_) -> false.

expect_immutable_updates({ok, Program}) ->
    Main = find_function("Main", maps:get(functions, Program)),
    Statements = maps:get(statements, Main),
    lists:any(fun(Statement) ->
        maps:get(kind, Statement, none) == variable andalso
        maps:get(name, Statement, none) == "updated_player" andalso
        maps:get(value, Statement, none) ==
            {update, {var_ref, "player"}, [{{field, "score"}, {int, 4}}]}
    end, Statements) andalso
    lists:any(fun(Statement) ->
        maps:get(kind, Statement, none) == variable andalso
        maps:get(name, Statement, none) == "updated_limited" andalso
        maps:get(type, Statement, none) == restricted_map
    end, Statements);
expect_immutable_updates(_) -> false.

expect_record_update_bad_field(
  {error, {in_function, "Main",
           {unknown_record_field, "Player", "missing"}}}) -> true;
expect_record_update_bad_field(_) -> false.

expect_record_update_bad_type(
  {error, {in_function, "Main",
           {record_update_type_mismatch, "Player", "score", int, string}}}) -> true;
expect_record_update_bad_type(_) -> false.

expect_records({ok, Program}) ->
    [Player, Team] = maps:get(records, Program),
    Main = find_function("Main", maps:get(functions, Program)),
    maps:get(name, Player) == "Player" andalso
    maps:get(fields, Player) ==
        [#{type => string, name => "name"}, #{type => int, name => "score"}] andalso
    maps:get(fields, Team) ==
        [#{type => string, name => "label"},
         #{type => {named, "Player"}, name => "captain"}] andalso
    lists:any(fun(Statement) ->
        maps:get(type, Statement, none) == {named, "Team"}
    end, maps:get(statements, Main));
expect_records(_) -> false.

expect_record_bad_constructor(
  {error, {in_function, "Main",
           {argument_type_mismatch, "Player",
            [string, int], [int, string]}}}) -> true;
expect_record_bad_constructor(_) -> false.

expect_record_unknown_field(
  {error, {in_function, "Main",
           {unknown_record_field, "Player", "score"}}}) -> true;
expect_record_unknown_field(_) -> false.

expect_record_pipeline_invalid(
  {error, {in_function, "Main", {function_call_required, "Score"}}}) -> true;
expect_record_pipeline_invalid(_) -> false.

expect_enums({ok, Program}) ->
    [Result] = maps:get(enums, Program),
    [Ok, Error, Pending] = maps:get(variants, Result),
    Load = find_function("Load", maps:get(functions, Program)),
    maps:get(name, Result) == "Result" andalso
    maps:get(fields, Ok) == [#{type => int, name => "value"}] andalso
    maps:get(fields, Error) == [#{type => string, name => "message"}] andalso
    maps:get(fields, Pending) == [] andalso
    maps:get(return_types, Load) == [{named, "Result"}];
expect_enums(_) -> false.

expect_inline_user_types({ok, Program}) ->
    [Wrapper, Inner] = maps:get(records, Program),
    [Status] = maps:get(enums, Program),
    [Ready, Down] = maps:get(variants, Status),
    maps:get(fields, Wrapper) == [#{type => {named, "Inner"}, name => "inner"}] andalso
    maps:get(fields, Inner) == [#{type => {named, "Status"}, name => "status"}] andalso
    maps:get(fields, Ready) == [] andalso
    maps:get(fields, Down) == [#{type => string, name => "reason"}];
expect_inline_user_types(_) -> false.

expect_enum_bad_variant(
  {error, {in_function, "Main",
           {variant_type_mismatch, "Result", "Ok", [int], [string]}}}) -> true;
expect_enum_bad_variant(_) -> false.

expect_enum_unknown_variant(
  {error, {in_function, "Main",
           {unknown_enum_variant, "Status", "Missing"}}}) -> true;
expect_enum_unknown_variant(_) -> false.

expect_enum_implicit_variant({ok, Program}) ->
    [Result] = maps:get(enums, Program),
    [Ok] = maps:get(variants, Result),
    maps:get(fields, Ok) == [#{type => int, name => "value"}];
expect_enum_implicit_variant(_) -> false.

expect_enum_pattern_arity(
  {error, {in_function, "Main",
           {variant_pattern_arity, "Result", "Ok", 1, 0}}}) -> true;
expect_enum_pattern_arity(_) -> false.

expect_enum_pattern_binding_leak(
  {error, {in_function, "Main", {unknown_variable, "value"}}}) -> true;
expect_enum_pattern_binding_leak(_) -> false.

expect_enum_pattern_duplicate_binding(
  {error, {in_function, "Main", {duplicate_pattern_binding, "value"}}}) -> true;
expect_enum_pattern_duplicate_binding(_) -> false.

expect_try_propagation({ok, Program}) ->
    Main = find_function("Main", maps:get(functions, Program)),
    Statements = maps:get(statements, Main),
    lists:any(fun(Statement) ->
        maps:get(kind, Statement, none) == variable andalso
        maps:get(value, Statement, none) == {try_call, "Add", [{int, 2}, {int, 3}]}
    end, Statements) andalso
    lists:any(fun(Statement) ->
        maps:get(kind, Statement, none) == call andalso
        maps:get(name, Statement, none) == "Observe" andalso
        maps:get(propagation, Statement, normal) == 'try'
    end, Statements);
expect_try_propagation(_) -> false.

expect_invalid_try({error, {in_function, "Main",
                            {try_requires_function_call, {int, 1}}}}) -> true;
expect_invalid_try(_) -> false.

expect_pipe_propagation({ok, Program}) ->
    Main = find_function("Main", maps:get(functions, Program)),
    [Return] = [Statement || Statement <- maps:get(statements, Main),
                             maps:get(kind, Statement) == return],
    maps:get(values, Return) ==
        [{pointer_new, {call, sint,
          [{pipe_call, {pipe_call, {int, 2}, "Increment", []}, "Add", [{int, 3}]}]}}];
expect_pipe_propagation(_) -> false.

expect_invalid_pipe({error, {in_function, "Main",
                             {pipe_requires_function_call, _Tokens}}}) -> true;
expect_invalid_pipe({error, {in_function, "Main",
                             {with_span, {pipe_requires_function_call, _Tokens}, Span}}}) ->
    maps:get(line, maps:get(start, Span)) == 2;
expect_invalid_pipe(_) -> false.

expect_module_declarations({ok, Program}) ->
    Declarations = maps:get(module_declarations, Program),
    Main = find_function("Main", maps:get(functions, Program)),
    [Base, Inferred, Shared] = Declarations,
    maps:get(scope, Base) == const andalso
    maps:get(eval, Base) == const andalso
    maps:get(value, Base) == {int, 2} andalso
    maps:get(scope, Inferred) == const andalso
    maps:get(type, Inferred) == int andalso
    maps:get(value, Inferred) == {binary, plus, {var_ref, "base"}, {int, 1}} andalso
    maps:get(scope, Shared) == global andalso
    maps:get(value, Shared) == {binary, plus, {var_ref, "inferred"}, {int, 4}} andalso
    maps:get(values, hd(maps:get(statements, Main))) ==
        [{pointer_new, {call, sint, [{var_ref, "shared"}]}}];
expect_module_declarations(_) ->
    false.

expect_imports_exports({ok, Program}) ->
    [#{name := "math_lib", path := Path}] = maps:get(imports, Program),
    Main = find_function("Main", maps:get(functions, Program)),
    [Value, _Stdout, Return] = maps:get(statements, Main),
    Path == "tests/programs/math_lib.terra" andalso
    maps:get(value, Value) == {remote_call, "math_lib", "Add", [{int, 2}, {int, 3}]} andalso
    maps:get(values, Return) ==
        [{pointer_new, {call, sint, [{var_ref, "value"}]}}];
expect_imports_exports(_) ->
    false.

expect_std_collection({ok, Program}) ->
    [#{name := "std_collection", path := Path}] = maps:get(imports, Program),
    Main = find_function("Main", maps:get(functions, Program)),
    [_Values, Count, Total, Reversed, _If, _Stdout, Return] = maps:get(statements, Main),
    filename:basename(Path) == "std_collection.terra" andalso
    filename:basename(filename:dirname(Path)) == "std" andalso
    maps:get(value, Count) == {remote_call, "std_collection", "Length",
                               [{var_ref, "values"}]} andalso
    maps:get(value, Total) == {remote_call, "std_collection", "Sum",
                               [{var_ref, "values"}]} andalso
    maps:get(value, Reversed) == {remote_call, "std_collection", "Reverse",
                                  [{var_ref, "values"}]} andalso
    maps:get(values, Return) ==
        [{pointer_new, {call, sint,
          [{binary, plus, {var_ref, "count"}, {var_ref, "total"}}]}}];
expect_std_collection(_) ->
    false.

expect_import_unexported({error, {in_function, "Main",
                                  {unknown_imported_function, "math_lib", "Hidden"}}}) ->
    true;
expect_import_unexported(_) ->
    false.

expect_export_unknown({error, {unknown_export, "Missing"}}) ->
    true;
expect_export_unknown(_) ->
    false.

expect_export_pointer(
  {error, {invalid_erlang_export_type, "Echo", {pointer, int}}}) -> true;
expect_export_pointer(_) -> false.

expect_erlang_ffi({ok, Program}) ->
    [#{kind := erlang_ffi, module := "lists", function := "sum",
       params := [#{type := list}], return_types := [number]}] = maps:get(externals, Program),
    Main = find_function("Main", maps:get(functions, Program)),
    [_Values, Call, Return] = maps:get(statements, Main),
    maps:get(kind, Call) == ffi_call andalso
    maps:get(values, Return) ==
        [{pointer_new, {call, sint,
          [{ffi_call, "lists", "sum", [{var_ref, "values"}], [number]}]}}];
expect_erlang_ffi(_) ->
    false.

expect_webserver_ffi({ok, Program}) ->
    Externals = maps:get(externals, Program),
    Main = find_function("Main", maps:get(functions, Program)),
    length(Externals) == 5 andalso
    lists:any(fun(#{module := "application", function := "ensure_all_started",
                    params := [#{type := atom}], return_types := [tuple]}) -> true;
                 (_) -> false
              end, Externals) andalso
    lists:any(fun(#{module := "inets", function := "start",
                    params := [#{type := atom}, #{type := list}],
                    return_types := [tuple]}) -> true;
                 (_) -> false
              end, Externals) andalso
    lists:any(fun(#{module := "inets", function := "stop",
                    params := [#{type := atom}, #{type := pid}],
                    return_types := [atom]}) -> true;
                 (_) -> false
              end, Externals) andalso
    maps:get(values, hd(lists:reverse(maps:get(statements, Main)))) ==
        [{pointer_new, {call, sint, [{int, 0}]}}];
expect_webserver_ffi(_) ->
    false.

expect_erlang_ffi_undeclared(
  {error, {in_function, "Main",
           {undeclared_erlang_function, "lists", "reverse"}}}) -> true;
expect_erlang_ffi_undeclared(_) -> false.

expect_erlang_ffi_unknown_module(
  {error, {in_function, "Main", {undeclared_erlang_module, "lists"}}}) -> true;
expect_erlang_ffi_unknown_module(_) -> false.

expect_erlang_ffi_duplicate(
  {error, {duplicate_erlang_external, "lists", "sum"}}) -> true;
expect_erlang_ffi_duplicate(_) -> false.

expect_erlang_ffi_pointer(
  {error, {invalid_erlang_ffi_type, {pointer, int}}}) -> true;
expect_erlang_ffi_pointer(_) -> false.

expect_beam_type_constructor(
  {error, {in_function, "Main", {type_has_no_constructor, pid}}}) -> true;
expect_beam_type_constructor(_) -> false.

expect_process_primitives({ok, Program}) ->
    Main = find_function("Main", maps:get(functions, Program)),
    Statements = maps:get(statements, Main),
    lists:any(fun
        (#{kind := variable, type := pid,
           value := {call, "spawn", [{call, "Worker", [{call, "self", []}]}]}}) -> true;
        (_) -> false
    end, Statements) andalso
    lists:any(fun
        (#{kind := variable, type := string,
           value := {call, "receive", [{type_spec, string}]}}) -> true;
        (_) -> false
    end, Statements);
expect_process_primitives(_) -> false.

expect_process_spawn_invalid(
  {error, {in_function, "Main", spawn_requires_function_call}}) -> true;
expect_process_spawn_invalid(_) -> false.

expect_process_send_invalid(
  {error, {in_function, "Main", {send_requires_pid, string}}}) -> true;
expect_process_send_invalid(_) -> false.

expect_process_receive_invalid(
  {error, {in_function, "Main", {invalid_process_value_type, state}}}) -> true;
expect_process_receive_invalid(_) -> false.

expect_process_pointer_argument(
  {error, {in_function, "Main", {invalid_process_value_type, {pointer, int}}}}) -> true;
expect_process_pointer_argument(_) -> false.

expect_top_level_local({error, {variable_requires_scope, local}}) ->
    true;
expect_top_level_local({error, {with_span, {variable_requires_scope, local, _Tokens}, _Span}}) ->
    true;
expect_top_level_local(_) ->
    false.

find_function(Name, Functions) ->
    hd([Function || Function <- Functions, maps:get(name, Function) == Name]).

count_calls(Name, Invocation, Statements) ->
    length([Statement || Statement <- Statements,
                         maps:get(kind, Statement) == call,
                         maps:get(name, Statement) == Name,
                         maps:get(invocation, Statement) == Invocation]).

has_multi_binding(Statements) ->
    lists:any(fun(Statement) ->
        maps:get(kind, Statement) == multi_binding andalso
        maps:get(bindings, Statement) ==
            [#{type => string, name => "x"}, #{type => number, name => "y"}] andalso
        maps:get(value, Statement) == {call, "T", []}
    end, Statements).

expect_control_flow({ok, Program}) ->
    Control = find_function("Control", maps:get(functions, Program)),
    Statements = maps:get(statements, Control),
    If = find_statement('if', Statements),
    Unless = find_statement(unless, Statements),
    Switch = find_statement(switch, Statements),
    length(maps:get(branches, If)) == 2 andalso
    length(maps:get(else_branch, If)) == 1 andalso
    maps:get(else_branch, Unless) =/= none andalso
    maps:get(exhaustive, Switch) == true andalso
    maps:get(break, Switch) == default andalso
    length(maps:get(cases, Switch)) == 2;
expect_control_flow(_) ->
    false.

find_statement(Kind, Statements) ->
    hd([Statement || Statement <- Statements, maps:get(kind, Statement) == Kind]).

expect_loops({ok, Program}) ->
    Functions = maps:get(functions, Program),
    LoopDemo = find_function("LoopDemo", Functions),
    Recur = find_function("Recur", Functions),
    LoopStatements = maps:get(statements, LoopDemo),
    RecurStatements = maps:get(statements, Recur),
    ForEach = find_statement(for_each, LoopStatements),
    ForRange = find_statement('for', LoopStatements),
    maps:get(binding, ForEach) == "x" andalso
    maps:get(iterable, ForEach) == {var_ref, "items"} andalso
    maps:get(iterator, ForRange) == {call, range, [{int, 10}]} andalso
    has_kind(while, LoopStatements) andalso
    has_kind(do_while, LoopStatements) andalso
    count_calls("Recur", repeated, RecurStatements) == 1;
expect_loops(_) ->
    false.

has_kind(Kind, Statements) ->
    lists:any(fun(Statement) -> maps:get(kind, Statement) == Kind end, Statements).

expect_branch_binding_leak({error, {in_function, "Main", {unknown_variable, "branch_value"}}}) ->
    true;
expect_branch_binding_leak(_) ->
    false.

expect_switch_binding_leak({error, {in_function, "Main", {unknown_variable, "case_value"}}}) ->
    true;
expect_switch_binding_leak(_) ->
    false.

expect_loop_binding_leak({error, {in_function, "Main", {unknown_variable, "it"}}}) ->
    true;
expect_loop_binding_leak(_) ->
    false.

expect_missing_return_type({error, {with_span, {expected_return_type, _Tokens}, _Span}}) ->
    true;
expect_missing_return_type({error, {expected_return_type, _Tokens}}) ->
    true;
expect_missing_return_type(_) ->
    false.

expect_empty_return({error, {in_function, "Main", empty_return}}) -> true;
expect_empty_return({error, {in_function, "Main", {with_span, empty_return, _Span}}}) -> true;
expect_empty_return(_) ->
    false.

expect_passes({ok, Program}) ->
    Expected = [parsing, name_resolution, type_checking, unreachable_code,
                definite_return, warning_analysis, lowering],
    program:passes() == Expected andalso maps:get(passes, Program) == Expected;
expect_passes(_) ->
    false.

expect_missing_return(
  {error, {in_function, "Main", {missing_return, [{strict_pointer, sint}]}}}) ->
    true;
expect_missing_return(_) ->
    false.

expect_partial_branch_return(
  {error, {in_function, "Main", {missing_return, [{strict_pointer, sint}]}}}) ->
    true;
expect_partial_branch_return(_) ->
    false.

expect_unreachable_after_return({error, {in_function, "Main",
                                         {unreachable_statement, call}}}) ->
    true;
expect_unreachable_after_return(_) ->
    false.

expect_duplicate_binding({error, {in_function, "Main",
                                  {duplicate_variable, "value"}}}) ->
    true;
expect_duplicate_binding(_) ->
    false.

expect_duplicate_case({error, {in_function, "Main", {duplicate_case, {int, 1}}}}) ->
    true;
expect_duplicate_case(_) ->
    false.

expect_invalid_loop_shadowing({error, {in_function, "Main",
                                       {invalid_shadowing, "it"}}}) ->
    true;
expect_invalid_loop_shadowing(_) ->
    false.

expect_expression_precedence({ok, Program}) ->
    Logic = find_function("Logic", maps:get(functions, Program)),
    [#{kind := return, values := [Expression]}] = maps:get(statements, Logic),
    Expression =:=
        {binary, or_or,
         {unary, bang, {var_ref, "a"}},
         {binary, and_and,
          {var_ref, "b"},
          {binary, eq_eq,
           {binary, plus,
            {var_ref, "n"},
            {binary, times, {int, 2}, {int, 3}}},
           {int, 7}}}};
expect_expression_precedence(_) ->
    false.

expect_invalid_numeric_conversion(
  {error, {in_function, "Main", {invalid_numeric_conversion, string, int}}}) ->
    true;
expect_invalid_numeric_conversion(_) ->
    false.

expect_conversions({ok, Program}) ->
    Main = find_function("Main", maps:get(functions, Program)),
    Statements = maps:get(statements, Main),
    lists:any(fun(Statement) ->
        maps:get(kind, Statement, none) == variable andalso
        maps:get(name, Statement, none) == "int_value" andalso
        maps:get(type, Statement, none) == int andalso
        maps:get(value, Statement, none) == {call, "parse_int", [{string, <<"12">>}]}
    end, Statements) andalso
    lists:any(fun(Statement) ->
        maps:get(kind, Statement, none) == variable andalso
        maps:get(name, Statement, none) == "atom_text" andalso
        maps:get(type, Statement, none) == binary andalso
        maps:get(value, Statement, none) == {call, "to_binary", [{atom, ready}]}
    end, Statements);
expect_conversions(_) ->
    false.

expect_conversion_bad_argument(
  {error, {in_function, "Main",
           {argument_type_mismatch, "parse_int", [string], [int]}}}) -> true;
expect_conversion_bad_argument(_) ->
    false.

expect_conversion_bad_to_string(
  {error, {in_function, "Main",
           {invalid_conversion_argument, "to_string", map}}}) -> true;
expect_conversion_bad_to_string(_) ->
    false.

expect_console_helpers({ok, Program}) ->
    Main = find_function("Main", maps:get(functions, Program)),
    [Message, Print, Println, _ArgsLine, Eprint, Eprintln, Blank, _Return] =
        maps:get(statements, Main),
    maps:get(value, Message) ==
        {call, "format", [{string, <<"name={} score={} braces={{ok}}">>},
                           {string, <<"Ada">>}, {int, 7}]} andalso
    [maps:get(name, Statement) || Statement <-
        [Print, Println, Eprint, Eprintln, Blank]] ==
        ["print", "println", "eprint", "eprintln", "println"] andalso
    maps:get(warnings, Program) == [];
expect_console_helpers(_) -> false.

expect_format_bad_argument(
  {error, {in_function, "Main",
           {argument_type_mismatch, "format", [string], [int]}}}) -> true;
expect_format_bad_argument(_) -> false.

expect_format_missing_template(
  {error, {in_function, "Main", {console_helper_arity, "format", 1, 0}}}) -> true;
expect_format_missing_template(_) -> false.

expect_pointers({ok, Program}) ->
    maps:get(region_capacity, Program) == {fixed, 4};
expect_pointers(_) -> false.

expect_pointer_depth({ok, Program}) ->
    Main = find_function("Main", maps:get(functions, Program)),
    maps:get(return_types, Main) == [{strict_pointer, sint}] andalso
    maps:get(region_capacity, Program) == {auto, 5, 65536};
expect_pointer_depth(_) -> false.

expect_strict_pointer_implicit(
  {error, {in_function, "Main", {strict_pointer_mismatch, int, int}}}) -> true;
expect_strict_pointer_implicit(_) -> false.

expect_strict_pointer_mismatch(
  {error, {in_function, "Main",
           {strict_pointer_mismatch, sint, {pointer, int}}}}) -> true;
expect_strict_pointer_mismatch(_) -> false.

expect_strict_non_pointer(
  {error, {in_function, "Main", strict_requires_pointer}}) -> true;
expect_strict_non_pointer(_) -> false.

expect_auto_pointer_region({ok, Program}) ->
    maps:get(region_capacity, Program) == {auto, 3, 65536};
expect_auto_pointer_region(_) -> false.

expect_region_capacity_too_small(
  {error, {region_capacity_too_small, 1, 2}}) -> true;
expect_region_capacity_too_small(_) -> false.

expect_region_capacity_too_large(
  {error, {region_capacity_too_large, 65537, 65536}}) -> true;
expect_region_capacity_too_large(_) -> false.

expect_bad_temp_pointer(
  {error, {in_function, "Main", {invalid_pointer_storage, temp, runtime}}}) -> true;
expect_bad_temp_pointer(_) -> false.

expect_once_requires_zero_args(
  {error, {in_function, "Main",
           {argument_type_mismatch, "NeedsValue", [int], []}}}) ->
    true;
expect_once_requires_zero_args(_) ->
    false.

expect_global_captures_local(
  {error, {in_function, "Main", {global_initializer_not_closed, "captured"}}}) ->
    true;
expect_global_captures_local(_) ->
    false.

expect_global_computed_invalid(
  {error, {in_function, "Main",
           {invalid_storage_combination, global, computed}}}) ->
    true;
expect_global_computed_invalid(_) ->
    false.

expect_atomic_number_invalid(
  {error, {in_function, "Main", {invalid_atomic_type, number}}}) -> true;
expect_atomic_number_invalid(_) -> false.

expect_warnings({ok, Program}) ->
    Warnings = maps:get(warnings, Program),
    Codes = [maps:get(code, Warning) || Warning <- Warnings],
    Repeated = [begin
                    {ok, Again} = program:parse_file("tests/programs/warnings.terra"),
                    maps:get(warnings, Again)
                end || _ <- lists:seq(1, 5)],
    lists:all(fun(Code) -> lists:member(Code, Codes) end,
              [unused_variable, unused_parameter, shadowed_variable,
               ignored_return_value]) andalso
    lists:all(fun(AgainWarnings) -> AgainWarnings == Warnings end, Repeated) andalso
    diagnostics:code({in_function, "Main", {missing_return, [number]}}) ==
        missing_return andalso
    diagnostics:warning_code(hd(Warnings)) == maps:get(code, hd(Warnings));
expect_warnings(_) -> false.

expect_complete_ast({ok, Program}) ->
    not has_raw_fallback(Program);
expect_complete_ast(_) ->
    false.

has_raw_fallback(Value) when is_map(Value) ->
    maps:is_key(tokens, Value) orelse
    maps:get(kind, Value, none) == unparsed_statement orelse
    maps:get(kind, Value, none) == variable_declaration orelse
    lists:any(fun has_raw_fallback/1, maps:values(Value));
has_raw_fallback(Value) when is_list(Value) ->
    lists:any(fun has_raw_fallback/1, Value);
has_raw_fallback(_Value) ->
    false.
