-module(diagnostics).
-export([code/1, warning_code/1, format/1, render/2, render_warning/2]).

code(Reason) ->
    {Code, _Message, _Help} = format(Reason),
    Code.

warning_code(Warning) ->
    {Code, _Message, _Help} = format_warning(Warning),
    Code.

format({in_function, Name, Reason}) ->
    {Code, Message, Help} = format(Reason),
    {Code, io_lib:format("In function ~s: ~s", [Name, Message]), Help};
format({with_span, Reason, _Span}) ->
    format(Reason);
format(bad_extension) ->
    {bad_extension,
     "The input file does not have the .terra extension.",
     "Pass a Terra source file whose name ends in .terra."};
format({read_failed, Reason}) ->
    {read_failed,
     io_lib:format("The source file could not be read: ~p.", [Reason]),
     "Check that the path exists and is readable."};
format(missing_entry_point) ->
    {missing_entry_point,
     "No Main function was found.",
     "Add: function strict *SInt Main(*String Args) { ... }"};
format(duplicate_entry_point) ->
    {duplicate_entry_point,
     "More than one Main function was defined.",
     "Keep exactly one function strict *SInt Main(*String Args)."};
format({duplicate_function, Name}) ->
    {duplicate_function,
     io_lib:format("Function ~s is defined more than once.", [Name]),
     "Keep one function with that name, or rename one of them."};
format({duplicate_record, Name}) ->
    {duplicate_record,
     io_lib:format("Struct ~s is defined more than once.", [Name]),
     "Keep one struct definition with that name."};
format({duplicate_user_type, Name}) ->
    {duplicate_user_type,
     io_lib:format("Type ~s is defined more than once.", [Name]),
     "Give each struct or enum a unique name."};
format({duplicate_definition, Name}) ->
    {duplicate_definition,
     io_lib:format("~s is used as both a struct and a function name.", [Name]),
     "Give the struct and function different names."};
format({duplicate_record_field, Name}) ->
    {duplicate_record_field,
     io_lib:format("Struct field ~s is defined more than once.", [Name]),
     "Keep one field with that name in the struct."};
format({unknown_record_type, Name}) ->
    {unknown_record_type,
     io_lib:format("Struct type ~s is not defined.", [Name]),
     "Add a top-level struct definition or check the type name."};
format({unknown_user_type, Name}) ->
    {unknown_user_type,
     io_lib:format("User-defined type ~s is not defined.", [Name]),
     "Add a top-level struct or enum definition, or check the type name."};
format({unknown_record_field, Record, Field}) ->
    {unknown_record_field,
     io_lib:format("Struct ~s has no field named ~s.", [Record, Field]),
     "Use a field declared in the struct definition."};
format({invalid_update_target, Type}) ->
    {invalid_update_target,
     io_lib:format("Immutable updates require a Map, RestrictedMap, or struct, but this is ~s.",
                   [type_name(Type)]),
     "Update a map-like value or construct a new value explicitly."};
format({duplicate_update_field, Name}) ->
    {duplicate_update_field,
     io_lib:format("Field ~s is updated more than once.", [Name]),
     "Keep one update entry for each struct field."};
format({record_update_type_mismatch, Record, Field, Expected, Actual}) ->
    {record_update_type_mismatch,
     io_lib:format("Struct ~s field ~s expects ~s, but received ~s.",
                   [Record, Field, type_name(Expected), type_name(Actual)]),
     "Use a replacement value with the field's declared type."};
format(record_update_requires_field) ->
    {record_update_requires_field,
     "Struct updates require field assignments.",
     "Write value{ field = replacement } for structs."};
format({expected_update_entry, _Tokens}) ->
    {expected_update_entry,
     "This immutable update entry is not valid Terra syntax.",
     "Use field = value for structs or key => value for maps."};
format({expected_update_separator_or_close, _Tokens}) ->
    {expected_update_separator_or_close,
     "This immutable update entry is missing a separator or closing brace.",
     "Separate update entries with commas and close the update with }."};
format(unterminated_record_body) ->
    {unterminated_record_body,
     "A struct definition is missing its closing brace.",
     "Add } after the final struct field."};
format({expected_record_field, _Tokens}) ->
    {expected_record_field,
     "This struct field is not valid Terra syntax.",
     "Write one typed field per line, such as Int score;"};
format({duplicate_variable, Name}) ->
    {duplicate_variable,
     io_lib:format("Variable ~s is bound more than once in the same binding.",
                   [Name]),
     "Use each variable name once in a parameter, destructuring, or multi-binding list."};
format({duplicate_global, Name}) ->
    {duplicate_global,
     io_lib:format("Global variable ~s is declared more than once.", [Name]),
     "Keep one module-wide declaration for each global name."};
format({invalid_shadowing, Name}) ->
    {invalid_shadowing,
     io_lib:format("Variable ~s cannot shadow an implicit binding here.", [Name]),
     "Choose a different name so the implicit binding remains unambiguous."};
format({invalid_atomic_type, Type}) ->
    {invalid_atomic_type,
     io_lib:format("Atomic storage requires Int or SInt, but received ~s.",
                   [type_name(Type)]),
     "Use an integer atomic binding or choose an ordinary immutable binding."};
format({invalid_storage_combination, Scope, Modifier}) ->
    {invalid_storage_combination,
     io_lib:format("The ~s scope cannot be combined with ~s storage.",
                   [name(Scope), name(Modifier)]),
     "Use a local modifier or a plain global/const/atomic declaration."};
format({invalid_pointer_storage, Scope, Modifier}) ->
    {invalid_pointer_storage,
     io_lib:format("Pointer storage cannot use ~s scope with ~s evaluation.",
                   [name(Scope), name(Modifier)]),
     "Use a local pointer; const, global, and temp declarations remain immutable."};
format({pointer_type_mismatch, Expected, Actual}) ->
    {pointer_type_mismatch,
     io_lib:format("This pointer stores ~s, but the value is ~s.",
                   [type_name(Expected), type_name(Actual)]),
     "Initialize or write the pointer with a value matching its pointee type."};
format({strict_pointer_mismatch, Expected, Actual}) ->
    {strict_pointer_mismatch,
     io_lib:format("A strict pointer to ~s requires an explicit pointer with that exact pointee type, but received ~s.",
                   [type_name(Expected), type_name(Actual)]),
     "Create the pointer explicitly with * and make its pointee type match exactly."};
format(strict_requires_pointer) ->
    {strict_requires_pointer,
     "The strict qualifier applies only to pointer types.",
     "Write strict *Type, with one or more pointer stars."};
format({dereference_non_pointer, Type}) ->
    {dereference_non_pointer,
     io_lib:format("The .* helper requires a pointer, but this value is ~s.",
                   [type_name(Type)]),
     "Use .* only on a value declared with *Type."};
format({global_initializer_not_closed, Name}) ->
    {global_initializer_not_closed,
     io_lib:format("Global ~s depends on a lexical variable.", [Name]),
     "Use a closed initializer that does not reference parameters or local bindings."};
format({variable_requires_scope, Scope}) ->
    {variable_requires_scope,
     io_lib:format("The ~s declaration must be inside a function body.",
                   [name(Scope)]),
     "Only global and const declarations may be written at module scope."};
format({variable_requires_scope, Scope, _Tokens}) ->
    format({variable_requires_scope, Scope});
format({duplicate_case, Pattern}) ->
    {duplicate_case,
     io_lib:format("Switch case ~s is already handled.", [pattern_name(Pattern)]),
     "Remove the duplicate case or combine its body with the first matching case."};
format({invalid_entry_point_signature, Signature}) ->
    {invalid_entry_point_signature,
     "Main has the wrong return type, parameter, or parameter name.",
     io_lib:format("Use: ~s", [Signature])};
format(void_return_type) ->
    {void_return_type,
     "Terra does not have void functions.",
     "Declare a concrete return type and return a value on every path."};
format(empty_return) ->
    {empty_return,
     "A return statement must return at least one value.",
     "Write return value; using a value that matches the function's declared return type."};
format({unknown_function, Name}) ->
    {unknown_function,
     io_lib:format("Function ~s is not defined.", [name(Name)]),
     "Define it before checking the program, or check the spelling."};
format({duplicate_import, Name}) ->
    {duplicate_import,
     io_lib:format("Module ~s is imported more than once.", [Name]),
     "Keep one import line for each module."};
format({import_requires_source_path, Name}) ->
    {import_requires_source_path,
     io_lib:format("Import ~s needs a source file path.", [Name]),
     "Check imports through a file so Terra can resolve sibling modules."};
format({cyclic_import, Path}) ->
    {cyclic_import,
     io_lib:format("Import cycle reached ~s.", [Path]),
     "Keep Terra module imports acyclic for now."};
format({unknown_import, Name}) ->
    {unknown_import,
     io_lib:format("Module ~s is not imported.", [Name]),
     "Add import ModuleName; at module scope and place ModuleName.terra beside this file."};
format({unknown_imported_function, ModuleName, FunctionName}) ->
    {unknown_imported_function,
     io_lib:format("Module ~s does not export function ~s.",
                   [ModuleName, FunctionName]),
     "Add export FunctionName; in the imported module or call an exported function."};
format({duplicate_export, Name}) ->
    {duplicate_export,
     io_lib:format("Function ~s is exported more than once.", [Name]),
     "Keep one export line for each function."};
format({unknown_export, Name}) ->
    {unknown_export,
     io_lib:format("Exported function ~s is not defined.", [Name]),
     "Define the function in this module or remove the export line."};
format({expected_erlang_external, _Tokens}) ->
    {expected_erlang_external,
     "This Erlang external declaration is not valid.",
     "Use: extern ReturnType erlang.module.function(Type argument);"};
format({duplicate_erlang_external, ModuleName, FunctionName}) ->
    {duplicate_erlang_external,
     io_lib:format("Erlang function ~s:~s is declared more than once.",
                   [ModuleName, FunctionName]),
     "Keep one extern declaration for each Erlang module/function pair."};
format({undeclared_erlang_module, ModuleName}) ->
    {undeclared_erlang_module,
     io_lib:format("Erlang module ~s has no selected external functions.", [ModuleName]),
     "Add an exact extern signature before calling this Erlang module."};
format({undeclared_erlang_function, ModuleName, FunctionName}) ->
    {undeclared_erlang_function,
     io_lib:format("Erlang function ~s:~s has not been selected.",
                   [ModuleName, FunctionName]),
     "Add an exact extern signature for this function before calling it."};
format({invalid_erlang_ffi_type, Type}) ->
    {invalid_erlang_ffi_type,
     io_lib:format("~s cannot cross the Erlang FFI boundary.", [type_name(Type)]),
     "Use a concrete value type; pointers, Var, and State are process/compiler-local."};
format({invalid_erlang_export_type, Name, Type}) ->
    {invalid_erlang_export_type,
     io_lib:format("Exported function ~s uses boundary-unsafe type ~s.",
                   [Name, type_name(Type)]),
     "Use concrete Erlang-mapped parameters and returns for exported functions."};
format({type_has_no_constructor, Type}) ->
    {type_has_no_constructor,
     io_lib:format("~s does not have a value constructor.", [type_name(Type)]),
     "Use to_binary for Binary or obtain PID/Reference values from a typed BEAM call."};
format({function_call_required, Name}) ->
    {function_call_required,
     io_lib:format("~s names a user-defined type, not a function.", [name(Name)]),
     "Construct the value with parentheses; once-only calls and pipelines require functions."};
format({duplicate_enum_variant, Name}) ->
    {duplicate_enum_variant,
     io_lib:format("Enum variant ~s is defined more than once.", [Name]),
     "Keep one variant with that name in the enum."};
format({duplicate_variant_field, Variant, Field}) ->
    {duplicate_variant_field,
     io_lib:format("Variant ~s defines field ~s more than once.", [Variant, Field]),
     "Give every payload field in a variant a unique name."};
format(unterminated_enum_body) ->
    {unterminated_enum_body,
     "An enum definition is missing its closing brace.",
     "Add } after the final enum variant."};
format({expected_enum_variant, _Tokens}) ->
    {expected_enum_variant,
     "This enum variant is not valid Terra syntax.",
     "Declare it explicitly with variant Name; or variant Name(Type field);"};
format({unknown_enum, Name}) ->
    {unknown_enum,
     io_lib:format("Enum ~s is not defined.", [Name]),
     "Add a top-level enum definition or check its name."};
format({not_an_enum, Name}) ->
    {not_an_enum,
     io_lib:format("~s is not an enum.", [Name]),
     "Use EnumName.Variant(...) with a declared enum."};
format({unknown_enum_variant, Enum, Variant}) ->
    {unknown_enum_variant,
     io_lib:format("Enum ~s has no variant named ~s.", [Enum, Variant]),
     "Use a variant declared inside the enum."};
format({variant_type_mismatch, Enum, Variant, Expected, Actual}) ->
    {variant_type_mismatch,
     io_lib:format("~s.~s expects ~s, but received ~s.",
                   [Enum, Variant, type_list(Expected), type_list(Actual)]),
     "Pass payload values in the variant's declared type order."};
format({enum_variant_required, Name}) ->
    {enum_variant_required,
     io_lib:format("Enum ~s cannot be constructed without a variant.", [Name]),
     "Write EnumName.Variant(...) to choose a tagged value."};
format({unknown_enum_field, Enum, Field}) ->
    {unknown_enum_field,
     io_lib:format("Enum ~s has no payload field named ~s.", [Enum, Field]),
     "Use .tag or a payload field declared by one of the enum variants."};
format({expected_variant_pattern_binding, _Tokens}) ->
    {expected_variant_pattern_binding,
     "Enum pattern payloads must explicitly bind or ignore each field.",
     "Use bind name to capture a payload or _ to ignore it."};
format({enum_pattern_type_mismatch, SubjectType, Enum}) ->
    {enum_pattern_type_mismatch,
     io_lib:format("This switch handles ~s, not enum ~s.",
                   [type_name(SubjectType), Enum]),
     "Match variants belonging to the switch subject's enum type."};
format({variant_pattern_arity, Enum, Variant, Expected, Actual}) ->
    {variant_pattern_arity,
     io_lib:format("Pattern ~s.~s expects ~p payload field(s), but received ~p.",
                   [Enum, Variant, Expected, Actual]),
     "Bind or ignore every payload field in declaration order."};
format({duplicate_pattern_binding, Name}) ->
    {duplicate_pattern_binding,
     io_lib:format("Pattern binding ~s is written more than once.", [Name]),
     "Give each bound payload a distinct name."};
format({unknown_variable, Name}) ->
    {unknown_variable,
     io_lib:format("Variable ~s is not available here.", [Name]),
     "Declare the variable before using it and check its scope."};
format({immutable_variable, Name}) ->
    {immutable_variable,
     io_lib:format("Variable ~s cannot be reassigned.", [Name]),
     "Terra variables are immutable; declare a new variable instead."};
format({expected_boolean_condition, Type, _Expression}) ->
    {expected_boolean_condition,
     io_lib:format("A condition must be Bool, but this is ~s.", [type_name(Type)]),
     "Use a comparison such as x < 10 or a Bool value."};
format({expected_iterable, Type, _Expression}) ->
    {expected_iterable,
     io_lib:format("for_each cannot iterate over ~s.", [type_name(Type)]),
     "Use a List, Tuple, Map, or String."};
format(non_exhaustive_switch) ->
    {non_exhaustive_switch,
     "The switch does not handle every possible value.",
     "Add a final default branch written as case:"};
format(default_case_must_be_last) ->
    {default_case_must_be_last,
     "The default case is not the final switch branch.",
     "Move case: after all cases with explicit patterns."};
format({return_type_mismatch, Expected, Actual}) ->
    {return_type_mismatch,
     io_lib:format("Expected return values ~s, but received ~s.",
                   [type_list(Expected), type_list(Actual)]),
     "Return and assign the same number of values in the declared type order."};
format({missing_return, ReturnTypes}) ->
    {missing_return,
     io_lib:format("This function must return ~s on every path.",
                   [type_list(ReturnTypes)]),
     "Add an explicit return, or make every if/unless/switch branch return."};
format({unreachable_statement, Kind}) ->
    {unreachable_statement,
     io_lib:format("A ~s statement appears after a guaranteed return.",
                   [statement_name(Kind)]),
     "Remove the unreachable statement or move it before the return."};
format({argument_type_mismatch, Name, Expected, Actual}) ->
    {argument_type_mismatch,
     io_lib:format("Call to ~s expects ~s, but received ~s.",
                   [name(Name), type_list(Expected), type_list(Actual)]),
     "Check the function signature and argument order."};
format({case_type_mismatch, Expected, Actual}) ->
    {case_type_mismatch,
     io_lib:format("Switch value is ~s, but this case is ~s.",
                   [type_name(Expected), type_name(Actual)]),
     "Use a case pattern compatible with the switched value."};
format({expected_range_number, Type}) ->
    {expected_range_number,
     io_lib:format("range expects a Number, but received ~s.", [type_name(Type)]),
     "Pass an Int, SInt, Float, or Number value to range."};
format({range_arity, Expected, Actual}) ->
    {range_arity,
     io_lib:format("range expects ~p argument, but received ~p.", [Expected, Actual]),
     "Write range(limit), for example range(10)."};
format({invalid_numeric_conversion, Source, Target}) ->
    {invalid_numeric_conversion,
     io_lib:format("Cannot convert ~s to ~s.", [type_name(Source), type_name(Target)]),
     "Numeric constructors accept only Int, SInt, Float, or Number values."};
format({numeric_conversion_arity, Target, Expected, Actual}) ->
    {numeric_conversion_arity,
     io_lib:format("~s conversion expects ~p argument, but received ~p.",
                   [type_name(Target), Expected, Actual]),
     "Pass exactly one numeric value to the conversion."};
format({conversion_arity, Name, Expected, Actual}) ->
    {conversion_arity,
     io_lib:format("Conversion helper ~s expects ~p argument, but received ~p.",
                   [Name, Expected, Actual]),
     "Pass the helper the documented number of values."};
format({console_helper_arity, Name, Expected, Actual}) ->
    {console_helper_arity,
     io_lib:format("Console helper ~s expects at least ~p argument, but received ~p.",
                   [Name, Expected, Actual]),
     "Pass format a String template followed by zero or more replacement values."};
format({invalid_conversion_argument, Name, Type}) ->
    {invalid_conversion_argument,
     io_lib:format("Conversion helper ~s does not accept ~s.",
                   [Name, type_name(Type)]),
     "Use a scalar Number, Int, SInt, Float, Atom, Bool, or String value."};
format({region_capacity_too_small, Capacity, Minimum}) ->
    {region_capacity_too_small,
     io_lib:format("Temporary region capacity ~p is below the entry minimum of ~p slots.",
                   [Capacity, Minimum]),
     "Reserve at least one slot for Main Args and one for its returned SInt pointer."};
format({region_capacity_too_large, Capacity, Maximum}) ->
    {region_capacity_too_large,
     io_lib:format("Temporary region capacity ~p exceeds the safe limit of ~p slots.",
                   [Capacity, Maximum]),
     "Choose a capacity at or below the documented per-process safety limit."};
format({automatic_region_too_large, Estimate, Maximum}) ->
    {automatic_region_too_large,
     io_lib:format("The compiler estimates ~p pointer slots, above the safe limit of ~p.",
                   [Estimate, Maximum]),
     "Reduce pointer allocations or split the work across shorter-lived processes."};
format({process_primitive_arity, Name, Expected, Actual}) ->
    {process_primitive_arity,
     io_lib:format("Process primitive ~s expects ~p argument(s), but received ~p.",
                   [Name, Expected, Actual]),
     "Use self(), spawn(Function(arguments)), send(pid, value), or receive(Type)."};
format(spawn_requires_function_call) ->
    {spawn_requires_function_call,
     "spawn expects one direct Terra function call.",
     "Write spawn(Worker(arguments)); lambdas and function values are not required."};
format({send_requires_pid, Type}) ->
    {send_requires_pid,
     io_lib:format("send expects a PID first, but received ~s.", [type_name(Type)]),
     "Pass a PID returned by self(), spawn(...), receive(PID), or typed Erlang FFI."};
format({invalid_process_value_type, Type}) ->
    {invalid_process_value_type,
     io_lib:format("~s cannot cross a Terra process boundary.", [type_name(Type)]),
     "Send immutable BEAM values; temporary pointers, State, and Var stay process-local."};
format({unknown_message_type, Name}) ->
    {unknown_message_type,
     io_lib:format("Message type ~s is not defined.", [Name]),
     "Use a built-in concrete type or a declared struct or enum in receive(Type)."};
format({restricted_map_arity, Actual}) ->
    {restricted_map_arity,
     io_lib:format("RestrictedMap expects one or two arguments, but received ~p.",
                   [Actual]),
     "Use RestrictedMap(capacity) or RestrictedMap(capacity, map)."};
format({invalid_restricted_map_capacity, Type}) ->
    {invalid_restricted_map_capacity,
     io_lib:format("RestrictedMap capacity must be Int, but received ~s.",
                   [type_name(Type)]),
     "Pass a non-negative integer capacity as the first argument."};
format({invalid_restricted_map_value, Type}) ->
    {invalid_restricted_map_value,
     io_lib:format("RestrictedMap contents must be Map, but received ~s.",
                   [type_name(Type)]),
     "Pass a map literal or Map value as the second argument."};
format({restricted_map_capacity_exceeded, Capacity, Count}) ->
    {restricted_map_capacity_exceeded,
     io_lib:format("RestrictedMap capacity is ~p, but its initializer has ~p members.",
                   [Capacity, Count]),
     "Increase the capacity or remove members from the initializer."};
format({try_requires_function_call, _Value}) ->
    {try_requires_function_call,
     "try must be followed by a checked function or helper call.",
     "Write try Function(arguments); constructors and ordinary values do not need try."};
format({pipe_requires_function_call, _Tokens}) ->
    {pipe_requires_function_call,
     "The right side of |> must be a checked function or helper call.",
     "Write value |> Function(arguments); the piped value becomes the first argument."};
format(null_not_allowed) ->
    {null_not_allowed,
     "null and nil are not valid variable values.",
     "Use a concrete value or model absence with an enum variant or atom."};
format({expected_function_declaration, _Tokens}) ->
    {expected_function_declaration,
     "Code was found outside a function.",
     "Move executable code into Main or another function."};
format({expected_return_type, _Tokens}) ->
    {expected_return_type,
     "Every function must declare a return type.",
     "Write function Number Name(...) or another concrete return type."};
format({expected_variable_declaration, _Tokens}) ->
    {expected_variable_declaration,
     "This variable declaration is not valid Terra syntax.",
     "Use scope, optional modifier, type, name, initializer, and a semicolon."};
format({expected_module_declaration, _Tokens}) ->
    {expected_module_declaration,
     "This module-scope declaration is not valid Terra syntax.",
     "Write global Type name = value; or const Type name = value; before functions."};
format({unsupported_statement, _Tokens}) ->
    {unsupported_statement,
     "This statement is not valid Terra syntax yet.",
     "Use a declaration, call, return, condition, switch, or loop statement."};
format(unterminated_function_body) ->
    {unterminated_function_body,
     "A function body is missing its closing brace.",
     "Add } to close the function."};
format(unterminated_statement) ->
    {unterminated_statement,
     "A statement is incomplete.",
     "Finish the statement and add ; where required."};
format({tokenize, {illegal_character, [Character]}}) ->
    {invalid_token,
     io_lib:format("I found the unexpected character '~c'.", [Character]),
     "Remove it or replace it with valid Terra punctuation."};
format({tokenize, unterminated_string}) ->
    {unterminated_string,
     "This string does not have a closing quote.",
     "Add a closing double quote before the end of the line."};
format({tokenize, newline_in_string}) ->
    {newline_in_string,
     "A string continued onto the next line.",
     "Close the string on this line or use an escaped newline."};
format({tokenize, Reason}) ->
    {invalid_token,
     io_lib:format("The source contains an invalid token: ~p.", [Reason]),
     "Check quotes, characters, and punctuation near the invalid text."};
format({backend, {unsupported_statement, Kind}}) ->
    {unsupported_backend_statement,
     io_lib:format("The BEAM backend cannot generate the ~p statement yet.", [Kind]),
     "Run terra check and terra explain, or simplify this statement for now."};
format({backend, {unknown_codegen_variable, Name}}) ->
    {unknown_codegen_variable,
     io_lib:format("The backend could not resolve variable ~s.", [Name]),
     "Make sure the variable is declared before it is used."};
format({erlang_compile, _Errors, _Warnings}) ->
    {beam_compile_failed,
     "Erlang could not compile the generated module.",
     "Use terra emit to inspect the generated Erlang source."};
format({beam_load_failed, Reason}) ->
    {beam_load_failed,
     io_lib:format("The BEAM VM could not load the generated module: ~p.", [Reason]),
     "Rebuild the program and check that the output directory is writable."};
format({runtime_error, Class, Reason, _Stacktrace}) ->
    {runtime_error,
     io_lib:format("The program stopped at runtime (~p): ~p.", [Class, Reason]),
     "Inspect the generated Erlang with terra emit and check the failing value."};
format({write_failed, Reason}) ->
    {write_failed,
     io_lib:format("I could not write the generated Erlang file: ~p.", [Reason]),
     "Choose a writable output path."};
format(Reason) ->
    {compiler_error,
     io_lib:format("The program could not be checked: ~p.", [Reason]),
     "Review the surrounding syntax and run terra explain after it checks."}.

render(Path, Reason) ->
    {Code, Message, Help} = format(Reason),
    Title = diagnostic_title(Code),
    render_formatted(Path, Reason, Title, Message, Help).

render_warning(Path, Warning) ->
    {Code, Message, Help} = format_warning(Warning),
    Label = diagnostic_label(Code),
    Reason = warning_reason(Warning),
    Title = lists:flatten(["WARNING ", Label, " [", atom_to_list(Code), "]"]),
    render_formatted(Path, Reason, Title, Message, Help).

diagnostic_title(Code) ->
    Label = diagnostic_label(Code),
    lists:flatten([Label, " [", atom_to_list(Code), "]"]).

diagnostic_label(Code) ->
    Words = string:replace(atom_to_list(Code), "_", " ", all),
    string:uppercase(lists:flatten(Words)).

render_formatted(Path, Reason, Title, Message, Help) ->
    case file:read_file(Path) of
        {ok, Source} ->
            Lines = string:split(binary_to_list(Source), "\n", all),
            LocationResult = locate_for_source(Lines, Reason),
            case LocationResult of
                none ->
                    [diagnostic_header(Title, Path), "\n",
                     Message, "\n\nHint: ", Help, "\n"];
                {LineNumber, Column, Length} ->
                    Location = io_lib:format("~s:~p:~p", [Path, LineNumber, Column]),
                    [diagnostic_header(Title, Location), "\n",
                     code_frame(Lines, LineNumber, Column, Length), "\n",
                     Message, "\n\nHint: ", Help, "\n"]
            end;
        {error, _} ->
            [diagnostic_header(Title, Path), "\n",
             Message, "\n\nHint: ", Help, "\n"]
    end.

locate_for_source(Lines, {runtime_error, _Class, _Reason, Stacktrace} = Reason) ->
    case runtime_source_location(Lines, Stacktrace) of
        none -> locate(Lines, Reason);
        Location -> Location
    end;
locate_for_source(Lines, Reason) ->
    case locate(Reason) of
        none -> locate(Lines, Reason);
        SpanLocation -> SpanLocation
    end.

runtime_source_location(_Lines, []) -> none;
runtime_source_location(Lines, [{_Module, Function, _Arity, Info} | Rest]) ->
    File = proplists:get_value(file, Info, ""),
    Line = proplists:get_value(line, Info, 0),
    case filename:extension(File) == ".terra" andalso Line > 0 of
        true -> nearest_terra_line(Lines, Function, Line);
        false -> runtime_source_location(Lines, Rest)
    end;
runtime_source_location(Lines, [_Frame | Rest]) -> runtime_source_location(Lines, Rest).

nearest_terra_line(Lines, Function, MappedLine) ->
    case terra_function_bounds(Lines, Function) of
        none -> fallback_location(Lines, min(MappedLine, length(Lines)));
        {Start, End} ->
            Candidate = min(max(Start, MappedLine), End),
            nearest_executable_line(Lines, Candidate, Start)
    end.

terra_function_bounds(Lines, Function) ->
    Name = generated_terra_name(Function),
    case find_line(Lines, 1, length(Lines), fun(Line) ->
        is_function_line(Line) andalso function_name_lower(Line) == Name
    end) of
        none -> none;
        {Start, _Line} ->
            case find_line(Lines, Start + 1, length(Lines), fun is_function_line/1) of
                none -> {Start, length(Lines)};
                {Next, _} -> {Start, Next - 1}
            end
    end.

generated_terra_name(Function) ->
    Raw = atom_to_list(Function),
    WithoutPrefix = case lists:prefix("terra_fn_", Raw) of
                        true -> string:slice(Raw, length("terra_fn_"));
                        false -> Raw
                    end,
    case string:split(WithoutPrefix, "_tail_step", leading) of
        [Name, _] -> Name;
        [Name] -> Name
    end.

function_name_lower(Line) ->
    case re:run(Line, "^\\s*function\\s+.*?\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(",
                [{capture, [1], list}]) of
        {match, [Name]} -> string:lowercase(Name);
        nomatch -> ""
    end.

nearest_executable_line(Lines, Number, Start) when Number >= Start ->
    Line = lists:nth(Number, Lines),
    Trimmed = string:trim(Line),
    case Trimmed =/= [] andalso Trimmed =/= "}" andalso
         not lists:prefix("--", Trimmed) andalso
         not lists:prefix("function ", Trimmed) of
        true ->
            Column = length(Line) - length(string:trim(Line, leading)) + 1,
            {Number, Column, max(1, length(Trimmed))};
        false -> nearest_executable_line(Lines, Number - 1, Start)
    end;
nearest_executable_line(Lines, _Number, Start) -> fallback_location(Lines, Start).

format_warning(#{code := unused_variable, function := Function, name := Name}) ->
    {unused_variable,
     io_lib:format("In function ~s: Variable ~s is never used.", [Function, Name]),
     "Remove the binding or use its value."};
format_warning(#{code := unused_parameter, function := Function, name := Name}) ->
    {unused_parameter,
     io_lib:format("In function ~s: Parameter ~s is never used.", [Function, Name]),
     "Use the parameter, or remove it and update call sites."};
format_warning(#{code := shadowed_variable, function := Function, name := Name}) ->
    {shadowed_variable,
     io_lib:format("In function ~s: Variable ~s shadows an earlier binding.",
                   [Function, Name]),
     "Rename the new binding if the shadowing is not intentional."};
format_warning(#{code := ignored_return_value, function := Function, callee := Callee}) ->
    {ignored_return_value,
     io_lib:format("In function ~s: The return value from ~s is ignored.",
                   [Function, Callee]),
     "Bind or return the value when the result matters."}.

warning_reason(#{code := unused_variable, function := Function, name := Name}) ->
    {in_function, Function, {unused_variable, Name}};
warning_reason(#{code := unused_parameter, function := Function, name := Name}) ->
    {in_function, Function, {unused_parameter, Name}};
warning_reason(#{code := shadowed_variable, function := Function, name := Name}) ->
    {in_function, Function, {shadowed_variable, Name}};
warning_reason(#{code := ignored_return_value, function := Function, callee := Callee}) ->
    {in_function, Function, {ignored_return_value, Callee}}.

locate({with_span, _Reason, Span}) ->
    span_location(Span);
locate({in_function, _Name, Reason}) ->
    locate(Reason);
locate({runtime_error, _Class, _Reason, Stacktrace}) ->
    runtime_stack_location(Stacktrace);
locate(_Reason) ->
    none.

runtime_stack_location([]) -> none;
runtime_stack_location([{_Module, _Function, _Arity, Info} | Rest]) ->
    File = proplists:get_value(file, Info, ""),
    Line = proplists:get_value(line, Info, 0),
    case filename:extension(File) == ".terra" andalso Line > 0 of
        true -> {Line, 1, 1};
        false -> runtime_stack_location(Rest)
    end;
runtime_stack_location([_Frame | Rest]) -> runtime_stack_location(Rest).

span_location(#{start := #{line := Line, column := Column},
                'end' := #{line := Line, column := EndColumn}})
  when Line > 0, Column > 0 ->
    {Line, Column, max(1, EndColumn - Column)};
span_location(#{start := #{line := Line, column := Column}})
  when Line > 0, Column > 0 ->
    {Line, Column, 1};
span_location(_Span) ->
    none.

diagnostic_header(Title, Location) ->
    DashCount = max(3, 34 - length(Title)),
    io_lib:format("-- ~s ~s ~s~n",
                  [Title, lists:duplicate(DashCount, $-), Location]).

locate(Lines, Reason) ->
    {FunctionName, InnerReason} = reason_context(Reason),
    {Start, End} = function_bounds(Lines, FunctionName),
    locate_reason(Lines, Start, End, InnerReason).

reason_context({in_function, Name, Reason}) -> {Name, Reason};
reason_context(Reason) -> {none, Reason}.

function_bounds(Lines, none) -> {1, length(Lines)};
function_bounds(Lines, Name) ->
    case find_line(Lines, 1, length(Lines),
                   fun(Line) -> function_line(Line, Name) end) of
        none -> {1, length(Lines)};
        {Start, _Line} ->
            case find_line(Lines, Start + 1, length(Lines), fun is_function_line/1) of
                none -> {Start, length(Lines)};
                {Next, _} -> {Start, Next - 1}
            end
    end.

function_line(Line, Name) ->
    is_function_line(Line) andalso
    re:run(Line, "\\b" ++ Name ++ "\\s*\\(", [{capture, none}]) == match.

is_function_line(Line) ->
    lists:prefix("function ", string:trim(Line, leading)).

locate_reason(Lines, _Start, _End, {tokenize, {illegal_character, [Character]}}) ->
    locate_substring(Lines, 1, length(Lines), [Character], first);
locate_reason(Lines, Start, End, {expected_boolean_condition, _Type, Expression}) ->
    locate_expression(Lines, Start, End, Expression);
locate_reason(Lines, Start, End, {expected_iterable, _Type, Expression}) ->
    locate_expression(Lines, Start, End, Expression);
locate_reason(Lines, Start, End, non_exhaustive_switch) ->
    locate_substring(Lines, Start, End, "== {", first);
locate_reason(Lines, Start, End, default_case_must_be_last) ->
    locate_substring(Lines, Start, End, "case:", first);
locate_reason(Lines, Start, End, duplicate_default_case) ->
    locate_substring(Lines, Start, End, "case:", last);
locate_reason(Lines, Start, End, {duplicate_case, default}) ->
    locate_substring(Lines, Start, End, "case:", last);
locate_reason(Lines, Start, End, {duplicate_case, _Pattern}) ->
    locate_substring(Lines, Start, End, "case ", last);
locate_reason(Lines, Start, End, {duplicate_variable, Name}) ->
    locate_substring(Lines, Start, End, Name, last);
locate_reason(Lines, Start, End, {invalid_shadowing, Name}) ->
    locate_substring(Lines, Start, End, Name, first);
locate_reason(Lines, Start, End, {unused_variable, Name}) ->
    locate_declaration(Lines, Start, End, Name, first);
locate_reason(Lines, Start, End, {unused_parameter, Name}) ->
    locate_substring(Lines, Start, End, Name, first);
locate_reason(Lines, Start, End, {shadowed_variable, Name}) ->
    locate_declaration(Lines, Start, End, Name, last);
locate_reason(Lines, Start, End, {ignored_return_value, Callee}) ->
    locate_substring(Lines, Start, End, Callee, first);
locate_reason(Lines, Start, End, {return_type_mismatch, _Expected, _Actual}) ->
    case locate_after(Lines, Start, End, "return ") of
        none -> locate_after(Lines, Start, End, " = ");
        Location -> Location
    end;
locate_reason(Lines, Start, End, {argument_type_mismatch, Name, _Expected, _Actual}) ->
    locate_substring(Lines, Start, End, name(Name), first);
locate_reason(Lines, Start, End, {unknown_function, Name}) ->
    locate_substring(Lines, Start, End, name(Name), first);
locate_reason(Lines, Start, End, {unknown_variable, Name}) ->
    locate_substring(Lines, Start, End, Name, first);
locate_reason(Lines, Start, End, {immutable_variable, Name}) ->
    locate_substring(Lines, Start, End, Name, last);
locate_reason(Lines, Start, End, {case_type_mismatch, _Expected, _Actual}) ->
    locate_substring(Lines, Start, End, "case ", first);
locate_reason(Lines, Start, End, {expected_range_number, _Type}) ->
    locate_substring(Lines, Start, End, "range", first);
locate_reason(Lines, Start, End, {range_arity, _Expected, _Actual}) ->
    locate_substring(Lines, Start, End, "range", first);
locate_reason(Lines, Start, End, null_not_allowed) ->
    case locate_substring(Lines, Start, End, "null", first) of
        none -> locate_substring(Lines, Start, End, "nil", first);
        Location -> Location
    end;
locate_reason(Lines, _Start, _End, {invalid_entry_point_signature, _Signature}) ->
    locate_substring(Lines, 1, length(Lines), "Main", first);
locate_reason(_Lines, _Start, _End, missing_entry_point) -> none;
locate_reason(Lines, _Start, _End, {expected_function_declaration, _Tokens}) ->
    first_source_line(Lines);
locate_reason(Lines, Start, _End, unterminated_function_body) ->
    fallback_location(Lines, Start);
locate_reason(Lines, Start, _End, unterminated_statement) ->
    fallback_location(Lines, Start);
locate_reason(Lines, Start, _End, _Reason) ->
    fallback_location(Lines, Start).

is_condition_line(Line) ->
    Trimmed = string:trim(Line, leading),
    lists:any(fun(Keyword) -> lists:prefix(Keyword ++ " ", Trimmed) end,
              ["if", "elseif", "unless", "while", "do_while"]).

locate_expression(Lines, Start, End, Expression) ->
    Text = lists:flatten(expression_text(Expression)),
    case Text == [] of
        true -> locate_condition_fallback(Lines, Start, End);
        false -> locate_expression_text(Lines, Start, End, Text)
    end.

locate_expression_text(Lines, Start, End, Text) ->
    case locate_substring(Lines, Start, End, Text, first) of
        none ->
            locate_condition_fallback(Lines, Start, End);
        Location -> Location
    end.

locate_condition_fallback(Lines, Start, End) ->
    case find_line(Lines, Start, End, fun is_condition_line/1) of
        none -> fallback_location(Lines, Start);
        {Number, Line} -> condition_location(Number, Line)
    end.

expression_text({int, Value}) -> integer_to_list(Value);
expression_text({sint, Value}) -> integer_to_list(Value);
expression_text({float, Value}) -> float_to_list(Value, [short]);
expression_text({string, Value}) -> [$" | binary_to_list(Value)] ++ [$"];
expression_text({bool, true}) -> "true";
expression_text({bool, false}) -> "false";
expression_text({var_ref, Name}) -> Name;
expression_text({binary, Op, Left, Right}) ->
    [expression_text(Left), " ", operator_text(Op), " ", expression_text(Right)];
expression_text(_Expression) -> "".

operator_text(eq_eq) -> "==";
operator_text(not_eq) -> "!=";
operator_text(lt) -> "<";
operator_text(lt_eq) -> "<=";
operator_text(gt) -> ">";
operator_text(gt_eq) -> ">=";
operator_text(plus) -> "+";
operator_text(minus) -> "-";
operator_text(times) -> "*";
operator_text(div_op) -> "/".

condition_location(Number, Line) ->
    Leading = length(Line) - length(string:trim(Line, leading)),
    Trimmed = string:trim(Line, leading),
    Keyword = hd([Word || Word <- ["do_while", "elseif", "unless", "while", "if"],
                          lists:prefix(Word ++ " ", Trimmed)]),
    AfterKeyword = string:slice(Line, Leading + length(Keyword)),
    ExtraSpaces = length(AfterKeyword) - length(string:trim(AfterKeyword, leading)),
    Start = Leading + length(Keyword) + ExtraSpaces,
    Tail = string:slice(Line, Start),
    Condition = case string:split(Tail, "{", leading) of
                    [Value, _] -> string:trim(Value, trailing);
                    [Value] -> string:trim(Value, trailing)
                end,
    {Number, Start + 1, max(1, length(Condition))}.

locate_after(Lines, Start, End, Prefix) ->
    case find_line(Lines, Start, End,
                   fun(Line) -> string:str(Line, Prefix) > 0 end) of
        none -> none;
        {Number, Line} ->
            Position = string:str(Line, Prefix) + length(Prefix),
            Tail = string:slice(Line, Position - 1),
            Value = take_until_delimiter(Tail),
            {Number, Position, max(1, length(Value))}
    end.

take_until_delimiter(Text) ->
    string:trim(take_until_delimiter(Text, [])).

take_until_delimiter([], Acc) -> lists:reverse(Acc);
take_until_delimiter([C | _], Acc) when C == ${; C == $;; C == $, ->
    lists:reverse(Acc);
take_until_delimiter([C | Rest], Acc) ->
    take_until_delimiter(Rest, [C | Acc]).

locate_substring(Lines, Start, End, Needle, Direction) ->
    Matches = [{Number, Line} || {Number, Line} <- numbered_lines(Lines),
                                Number >= Start, Number =< End,
                                string:str(Line, Needle) > 0],
    case choose_match(Matches, Direction) of
        none -> none;
        {Number, Line} -> {Number, string:str(Line, Needle), max(1, length(Needle))}
    end.

locate_declaration(Lines, Start, End, Name, Direction) ->
    Matches = [{Number, Line} || {Number, Line} <- numbered_lines(Lines),
                                Number >= Start, Number =< End,
                                is_declaration_line(Line, Name)],
    case choose_match(Matches, Direction) of
        none -> locate_substring(Lines, Start, End, Name, Direction);
        {Number, Line} -> {Number, string:str(Line, Name), max(1, length(Name))}
    end.

is_declaration_line(Line, Name) ->
    Trimmed = string:trim(Line, leading),
    HasScope = lists:any(fun(Scope) -> lists:prefix(Scope ++ " ", Trimmed) end,
                         ["global", "local", "temp"]),
    HasScope andalso
    re:run(Trimmed, "\\b" ++ Name ++ "\\b", [{capture, none}]) == match.

choose_match([], _Direction) -> none;
choose_match(Matches, first) -> hd(Matches);
choose_match(Matches, last) -> lists:last(Matches).

first_source_line(Lines) ->
    case find_line(Lines, 1, length(Lines),
                   fun(Line) ->
                       Trimmed = string:trim(Line),
                       Trimmed =/= [] andalso not lists:prefix("--", Trimmed)
                   end) of
        none -> none;
        {Number, Line} ->
            Leading = length(Line) - length(string:trim(Line, leading)),
            {Number, Leading + 1, max(1, length(string:trim(Line)))}
    end.

fallback_location(Lines, LineNumber) when LineNumber >= 1 ->
    case line_at(Lines, LineNumber) of
        none -> none;
        Line ->
            Leading = length(Line) - length(string:trim(Line, leading)),
            {LineNumber, Leading + 1, max(1, length(string:trim(Line)))}
    end.

find_line(Lines, Start, End, Predicate) when Start =< End ->
    case [{Number, Line} || {Number, Line} <- numbered_lines(Lines),
                            Number >= Start, Number =< End, Predicate(Line)] of
        [] -> none;
        [Match | _] -> Match
    end;
find_line(_Lines, _Start, _End, _Predicate) -> none.

numbered_lines(Lines) -> lists:zip(lists:seq(1, length(Lines)), Lines).

line_at(Lines, Number) when Number =< length(Lines) -> lists:nth(Number, Lines);
line_at(_Lines, _Number) -> none.

code_frame(Lines, LineNumber, Column, Length) ->
    Width = length(integer_to_list(LineNumber + 1)),
    Before = frame_line(Lines, LineNumber - 1, Width, " "),
    Current = frame_line(Lines, LineNumber, Width, ">"),
    Pointer = [" ", lists:duplicate(Width, $\s), " | ",
               lists:duplicate(max(0, Column - 1), $\s),
               lists:duplicate(max(1, Length), $^), "\n"],
    After = frame_line(Lines, LineNumber + 1, Width, " "),
    [Before, Current, Pointer, After].

frame_line(Lines, Number, Width, Marker) when Number >= 1, Number =< length(Lines) ->
    io_lib:format("~s ~*B | ~s~n", [Marker, Width, Number, lists:nth(Number, Lines)]);
frame_line(_Lines, _Number, _Width, _Marker) -> [].

name(Value) when is_atom(Value) -> atom_to_list(Value);
name(Value) -> Value.

pattern_name(default) -> "default";
pattern_name({atom, Value}) -> ":" ++ atom_to_list(Value);
pattern_name({int, Value}) -> integer_to_list(Value);
pattern_name({sint, Value}) -> integer_to_list(Value);
pattern_name({float, Value}) -> io_lib:format("~p", [Value]);
pattern_name({string, Value}) -> binary_to_list(Value);
pattern_name({bool, Value}) -> atom_to_list(Value);
pattern_name(Pattern) -> io_lib:format("~p", [Pattern]).

type_list(Types) ->
    ["(", lists:join(", ", [type_name(Type) || Type <- Types]), ")"].

type_name(number) -> "Number";
type_name(int) -> "Int";
type_name(sint) -> "SInt";
type_name(float) -> "Float";
type_name(atom) -> "Atom";
type_name(bool) -> "Bool";
type_name(map) -> "Map";
type_name(restricted_map) -> "RestrictedMap";
type_name(list) -> "List";
type_name(tuple) -> "Tuple";
type_name(string) -> "String";
type_name(binary) -> "Binary";
type_name(pid) -> "PID";
type_name(reference) -> "Reference";
type_name(var) -> "Var";
type_name({named, Name}) -> Name;
type_name({pointer, Type}) -> ["*", type_name(Type)];
type_name({strict_pointer, Type}) -> ["strict *", type_name(Type)];
type_name(Type) -> io_lib:format("~p", [Type]).

statement_name('if') -> "if";
statement_name('for') -> "for";
statement_name(for_each) -> "for_each";
statement_name(do_while) -> "do_while";
statement_name(Kind) -> io_lib:format("~p", [Kind]).
