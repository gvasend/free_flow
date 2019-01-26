 
 :- module(argparse, []).

:- use_module(library(xpath)).
 
:- use_module(library(sha)). %
 :- use_module(library(base64)).

:- use_module(library(xpath)).
 :- use_module(library('http/json')).

replace(In, From, To, Out) :-
    atomic_list_concat(L, From, In),
    atomic_list_concat(L, To, Out).
    
    
%%%%%%%%%%%%%%%%
    
:- dynamic(argument/2).
:- dynamic(argument_value/2).

show_arguments :-
    findall(arg(Name,Value), argument_value(Name,Value), Arguments),
    format('known arguments ~w',[Arguments]).
 
 argument(X) :- argument(X,_).
 
%argument('--graph_output',[description='filename to use for graph output.']). 
 
 
add_argument(Arg, Attr) :-
    \+ argument(Arg, _),
    is_list(Attr),
    assert(argument(Arg, Attr)), 
    listing(argument),
    !.
add_argument(_) :- throw('Unable to add argument').
 
 argparse1(Exp,ArgList) :-
    findall(Ar, argument(Ar), Exp),
    current_prolog_flag(argv, AllArgs),
    writeln(AllArgs),
    findall(arg(AName,Sarg), (nextto(Farg, Sarg, AllArgs), atom_concat('--', AName, Farg)), ArgList1),
    findall(arg(AName,true), (member(Farg, AllArgs), \+atom_concat('--', AName, Farg), atom_concat('-',AName,Farg)), ArgList2),
    append(ArgList1, ArgList2, ArgList),
    writeln(ArgList).

tty_mode :-
    stream_property(user_input, tty(true)).
    
get_missing_args(Exp, Args, AllPlusDef) :-
    member(Arg, Exp),
    \+ member(arg(Arg, _), Args),
    \+ tty_mode,
    format('read missing arguments from stdin ~w\n',[arg(Arg)]),
    read_args(json(MoreArgs)),
    findall(arg(Ar1, Ar0a), (member(Ar0=Ar0a, MoreArgs), replace(Ar0, '--', '', Ar1)), MoreArgs1),
    append(Args, MoreArgs1, AllArgs),
    findall(arg(Name1,Value), (argument(Name,Opts), \+member(arg(Name,_), AllArgs), subset([default=Value],Opts), atom_concat('--',Name1,Name)), DefaultArgs),
    append(AllArgs,DefaultArgs,AllPlusDef),
    format('all ~w\n',[AllArgs]),
    !.
get_missing_args(_, Args, ArgsPlusDef) :-
    findall(arg(Name1,Value), (argument(Name,Opts), \+member(arg(Name,_), Args), subset([default=Value],Opts), atom_concat('--',Name1,Name)), DefaultArgs),
    append(Args,DefaultArgs,ArgsPlusDef).
    
get_argument(Name,Value) :-
    format('retrieve ~w \n',[Name]),
    argument_value(Name,Value),
    format('found ~w ~w\n',[Name,Value]),
    \+ atom_concat('*', _, Value), 
    format('found direct ~w\n',[Value]),
    !.
get_argument(Name,Value1) :-
    format('get_argument indirect\n',[]),
    argument_value(Name,Value),
    format('found ~w:~w\n',[Name,Value]),
    atom_concat('*', Name1, Value),
    format('value is indirect\n',[Name1]),
    get_argument(Name1, Value1), !.
get_argument(N,V) :- format('cannot find ~w\n',[N]).

read_args(JsonTerm) :-
    read_header_data(current_input, Header),
    atom_codes(Atom, Header),
    atomic_list_concat([_,Data|_], '<app_data>', Atom),
    atomic_list_concat([Data1|_], '</app_data>', Data),
    atom_json_term(Data1, JsonTerm, []).
    
read_header_data(Stream, Header) :-
        read_line_to_codes(Stream, Header, Tail),
        read_header_data(Header, Stream, Tail).

read_header_data("\n", _, _) :- !.
read_header_data("", _, _) :- write('EOF'), !.

read_header_data([_|_], Stream, Tail) :-
        read_line_to_codes(Stream, Tail, NewTail),
        read_header_data(Tail, Stream, NewTail).
        
read_header_data([], _, _) :- write('EOF\n').
	



contains(Atom, Sub) :-
    sub_string(Atom, _, _, _, Sub), !.

handle_arguments(Args) :-
    member(arg('h',true), Args),
    format('usage: \n',[]),
    (
        argument(Arg, Param),
        intersection([default=Default,description=Desc],Param,_),
        (var(Default),Default='';nonvar(Default),format(atom(DefaultStr),'(default: ~w)',[Default])),
        format('~w value \t~w\n ~w\n',[Arg,Desc,DefaultStr]),
    fail;true),
    halt,
    !.
handle_arguments(_).

log_file(Message) :-
    open('log.txt', append, Str, []),
    format(Str, 'Log:~w\n', [Message]),
    close(Str).

    
%:- debug([graph_doc,graph_text1]).    
    
argparse :- argparse(_).
argparse(Arglist) :-    
    argparse1(Expected, Arglist1),
    format('expected ~w found ~w\n',[Expected, Arglist1]),
    handle_arguments(Arglist1),
    get_missing_args(Expected, Arglist1, Arglist),
    (
        member(arg(Name,Value), Arglist),
        assert(argument_value(Name,Value)),
    fail;true).
    


