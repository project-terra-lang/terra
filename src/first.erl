-module(first).
-export([check_file_extension/1]).

% Check if the File extension is our defined extension
% If not return an atom saying we dont match with it 
% This is to prevent our Language from allowing different file extensions than the 
% ones we want
check_file_extension(File) ->
    Result = case filename:extension(File) == ".terra" of
        true -> match;
        false -> not_match
    end,
    Result.
