% Parse list of command-line options.
%
% Parses list of command-line arguments assuming it is composed of a list of options as defined below. The function
% tries to give accurate user-friendly errors (not assertions) for non-compliant arguments and absence of required
% arguments. The order of the options is arbitrary.
%
%
% DEFINITIONS OF TERMS
% ====================
% Example argument list referred to below: --verbose --file ~/bicas.conf --setting varX 123
% --
% Option header   = A predefined (hardcoded, more or less) string meant to match a single argument, e.g. "--verbose",
%                   "--file", "--setting". It does not have to begin with "--" or "-" but that is the convention.
% Option value(s) = A sequence of arguments (could be zero arguments) following an option header with which they are
%                   associated, e.g. none, "bicas.conf", or "X" & "123". The number of expected option values should be
%                   predefined for the option.
% Option          = The combination of an option header and the subsequent option values.
% Option ID       = Unique, arbitrary string used to refer to the definition of an option and the corresponding results
%                   from parsing CLI arguments.
%
%
% ARGUMENTS
% =========
% cliArgumentsList             : 1D cell array of strings representing a sequence of CLI arguments.
% OptionsConfigMap             : containers.Map
%    <keys>                    : Option ID.
%    <values>                  : Struct. Information about each specified option (syntax).
%       .optionHeaderRegexp    : The option header, including any prefix (e.g. dash) expressed as regular expression.
%       .interprPriority       : Optional. Default=0. "Interpretation Priority". In case multiple regexp match,
%                                the priority determines which interpretation is used. If multiple options have the same
%                                priority, then assertion error.
%       .occurrenceRequirement : String specifying the number of times the option may occur.
%                                Permitted alternatives (strings):
%                                   '0-1'   = Option must occur once or never.
%                                   '1'     = Option must occur exactly once.
%                                   '0-inf' = Option may occur any number of times (zero or more).
%                                IMPLEMENTATION NOTE: This option exists so that multiple optionHeaderRegexp can be
%                                allowed to overlap in their coverage. Regexps can not express negation ("match all of
%                                this, except this") which can create problems and this tries to mitigate that.
%       .nValues               : The number of option values that must follow the option header.
%
%
% RETURN VALUES
% =============
% OptionValuesMap : containers.Map
%    <keys>   : Option ID.
%    <values> : Cell array of cell arrays of option values, {iOptionOccurrence}{iValue}.
%               iValue = 1..(nValues+1), where iValue==1 corresponds to the exact option header found (can vary because
%               of regular expressions).
%               NOTE: From this one can always read out whether an option was found or not: even an option without
%               option values contains a list of zero values.
%               NOTE: Can read out the order of occurrence, e.g. for having a later occurrence override a preceding one.
%               NOTE: An option occurrence with zero values has a 1x0 cell array (not 0x0).
%
%
% Author: Erik P G Johansson, IRF-U, Uppsala, Sweden
% First created 2016-06-02, reworked 2017-02-09, reworked 2019-07-22.
%
function OptionValuesMap = parse_CLI_options(cliArgumentsList, OptionsConfigMap)
%
% IMPLEMENTATION NOTE: Reasons for using containers.Map (instead of arrays, array of structs, cell
% array, structure of structures).
% 1) Caller can easily build up list of options by amending list.
% 2) Can use key strings to identify options rather than the CLI option headers themselves (the latter could be short
% and cryptic, and can change).
% 3) Can use more key strings (more permitted characters) than for structure field names.
% 4) Easy for caller to group subsets of options by keeping track of sets of keys. The caller can
% merge groups of options (before submitting as one parameter), and can split the returned result into
% the groups of options. Ex: Input files as opposed to output directory, log directory, config file.
% NOTE: The caller can easily(?) convert result into struct (one field per key-value pair).
%
% PROPOSAL: Return some kind of help information to display proper user-friendly error message.
% PROPOSAL: Shorten occurrenceRequirement
%   PROPOSAL: occReq, occurrenceReq
% PROPOSAL: Somehow return the order/argument number of the arguments found.
%   PRO: Can test for order, e.g. S/W mode must come first.
% PROPOSAL: Return struct array, one index for every option header+values (combined).
%   .index/.location : Number. Tells the order of (the groups of) arguments.
%   .optionId      : 
%   .optionHeader  : String
%   .optionValues  : Cell array of strings
%   NOTE: Might want to sort/search by either .index or .optionId . Therefore not Map. When there are several
%       occurrences, then one can use e.g. syntax
%           s=struct('x', {1,3,2,3}, 'y', {9,8,7,6})
%           xa = [s.x]; s(find(xa==3, 1, 'last')).y
%   CON: Return format is harder to search through when searching.
%       CON: Mostly/only when there are many occurrences.



% ASSERTIONS: Check argument types, sizes.
assert(iscell(cliArgumentsList), 'cliArgumentsList is not a cell array.')
if length(cliArgumentsList) ~= numel(cliArgumentsList)
    error('BICAS:parse_CLI_options:Assertion:IllegalArgument', 'Parameter is not a 1D cell array.')
end
EJ_library.utils.assert.isa(OptionsConfigMap, 'containers.Map')



%===========================================
% Initializations before algorithm.
%
% 1) Assertions
% 2) Initialize empty OptionValuesMap
%===========================================
OptionValuesMap = containers.Map;
optionIdsList   = OptionsConfigMap.keys;   % List to iterate over map.
for iOption = 1:length(optionIdsList)
    optionId     = optionIdsList{iOption};
    OptionConfig = OptionsConfigMap(optionId);
    if ~isfield(OptionConfig, 'interprPriority')
        OptionConfig.interprPriority = 0;
        OptionsConfigMap(optionId) = OptionConfig;
    end
    assert(isfinite(OptionConfig.interprPriority))

    % ASSERTION: OptionConfig is the right struct.
    EJ_library.utils.assert.struct(OptionConfig, {'optionHeaderRegexp', 'interprPriority', 'occurrenceRequirement', 'nValues'})
    
    % Create empty return structure (default value) with the same keys (optionId values).
    % NOTE: Applies to both options with and without values!
    OptionValuesMap(optionId) = {};
end
OptionsConfigArray = cellfun(@(x) (x), OptionsConfigMap.values);    % Convert to struct array (NOT cell array of structs).



%====================================
% Iterate over list of CLI arguments
%====================================
iCliArg = 1;
while iCliArg <= length(cliArgumentsList)
    cliArgument = cliArgumentsList{iCliArg};

    %=========================================
    % Search for a matching CLI option string
    %=========================================
    % NOTE: More convenient to work with arrays than maps here.
    iRegexpMatches  = find(EJ_library.utils.regexpf(cliArgument, {OptionsConfigArray.optionHeaderRegexp}));

    ipArray = [OptionsConfigArray(iRegexpMatches).interprPriority];    % Array over regexp matches. IP = Interpretation Priority
    ip      = max(ipArray);    % Scalar
    iMatch  = iRegexpMatches(ip == ipArray);

    
    
    nMatchingOptions = numel(iMatch);
    % UI ASSERTION
    if nMatchingOptions == 0
        % NOTE: Phrase chosen for case that there may be multiple sequences of arguments which are parsed separately.
        error('BICAS:parse_CLI_options:CLISyntax', ...
            'Can not interpret command-line argument "%s". It is not a permitted option header in this sequence of arguments.', ...
            cliArgument)
    end
    % ASSERTION
    if nMatchingOptions >= 2
        error('BICAS:parse_CLI_options:Assertion', 'Can interpret CLI option in multiple ways, because the interpretation of CLI arguments is badly configured.')
    end
    
    
    
    % CASE: There is exacly one matching option.
    optionId = optionIdsList{iMatch};
    
    % Store values for this option. (May be zero option values).
    OptionConfig = OptionsConfigMap(optionId);
    optionValues = OptionValuesMap(optionId);
    
    iCliArgLastValue  = iCliArg + OptionConfig.nValues;
    if iCliArgLastValue > length(cliArgumentsList)
        error('BICAS:parse_CLI_options:CLISyntax', ...
            'Can not find the argument(s) that is/are expected to follow command-line option header "%s".', cliArgument)
    end
    optionValues{end+1} = cliArgumentsList(iCliArg:iCliArgLastValue);
    OptionValuesMap(optionId) = optionValues;
    
    iCliArg = iCliArgLastValue + 1;
end   % while



%=====================================================
% ASSERTION: Check that all required options were set
%=====================================================
for iOption = 1:length(optionIdsList)
    optionId     = optionIdsList{iOption};
    OptionConfig = OptionsConfigMap(optionId);
    optionValues = OptionValuesMap(optionId);
    
    if strcmp(OptionConfig.occurrenceRequirement, '0-1')
        if numel(optionValues) > 1
            error('BICAS:parse_CLI_options:CLISyntax', 'Found more than one occurrence of command-line option "%s".', OptionConfig.optionHeaderRegexp)
        end
    elseif strcmp(OptionConfig.occurrenceRequirement, '1')
        if numel(optionValues) ~= 1
            error('BICAS:parse_CLI_options:CLISyntax', 'Could not find required command-line option matching regular expression "%s".', OptionConfig.optionHeaderRegexp)
        end
    elseif strcmp(OptionConfig.occurrenceRequirement, '0-inf')
        ;   % Do nothing.
    else
        error('BICAS:parse_CLI_options:Assertion', 'Can not interpret occurrenceRequirement="%s".', OptionConfig.occurrenceRequirement)
    end
end

end