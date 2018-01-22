 
 :- module(cat_doc, []).

:- use_module(library(xpath)).
 
:- use_module(library(sha)). %
 :- use_module(library(base64)).
 
:- use_module(graph).
:- use_module(argparse).

:- use_module(library(xpath)).
 :- use_module(library('http/json')).

replace(In, From, To, Out) :-
    atomic_list_concat(L, From, In),
    atomic_list_concat(L, To, Out).
    
    
%%%%%%%%%%%%%%%%
    
    
 
 argument(X) :- argument(X,_).
 
argument('--graph_output',[description='filename to use for graph output.']). 
 
 argparse(Exp,ArgList) :-
    findall(Ar, argument(Ar), Exp),
    current_prolog_flag(argv, AllArgs),
    findall(arg(AName,Sarg), (append([Farg, Sarg], Remain, AllArgs), atom_concat('--', AName, Farg)), ArgList1),
    findall(arg(AName,true), (append([Farg], Remain, AllArgs), \+atom_concat('--', AName, Farg), atom_concat('-',AName,Farg)), ArgList2),
    append(ArgList1, ArgList2, ArgList),
    writeln(ArgList).

tty_mode :-
    stream_property(user_input, tty(true)).
    
get_missing_args(Exp, Args, AllArgs) :-
    member(Arg, Exp),
    \+ member(arg(Arg, _), Args),
    \+ tty_mode,
    format('read missing arguments from stdin ~w\n',[arg(Arg)]),
    read_args(json(MoreArgs)),
    findall(arg(Ar1, Ar0a), (member(Ar0=Ar0a, MoreArgs), replace(Ar0, '--', '', Ar1)), MoreArgs1),
    append(Args, MoreArgs1, AllArgs),
    format('all ~w\n',[AllArgs]),
    !.
get_missing_args(_, Args, Args).

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
	



	
analyze :-
    (
      graph:node(Id, document, Attr),
      subset([filename=File],Attr),
      cat_doc(File, Type),
      graph:add_node_attributes(Id, [doc_type=Type]),
    fail;true).

cat_doc(Name, Cat) :-
    downcase_atom(Name, Lower),
    once(cat_doc1(Lower, Cat)).
    
cat_doc1(Name, rfp) :-
    contains(Name, 'rfp').
cat_doc1(Name, sow) :-
    contains(Name, 'sow').
cat_doc1(Name, past_performance) :-
    contains(Name, 'pp').
cat_doc1(Name, proposal) :-
    contains(Name, 'prop').
cat_doc1(Name, resume) :-
    contains(Name, 'resume').
cat_doc1(Name, pws) :-
    contains(Name, 'pws').
cat_doc1(Name, rfq) :-
    contains(Name, 'rfq').
cat_doc1(_, unknown).

contains(Atom, Sub) :-
    sub_string(Atom, _, _, _, Sub), !.

handle_arguments(Args) :-
    member(arg('h',true), Args),
    format('usage: \n',[]),
    (
        argument(Arg, Param),
        intersection([description=Desc],Param,_),
        format('~w value \t~w\n',[Arg,Desc]),
    fail;true),
    halt,
    !.
handle_arguments(_).

log_file(Message) :-
    open('log.txt', append, Str, []),
    format(Str, 'Log:~w\n', [Message]),
    close(Str).


fail_error(G) :-
    catch(G, Error, format('Exception ~w\n',[Error])).
		
:- argparse:add_argument('--input_graph',[default='*graph_output',description='graph output filename']). 

    
%:- debug([graph_doc,graph_text1]).    
    
run1 :- argparse(Expected, Arglist1),
    handle_arguments(Arglist1),
    get_missing_args(Expected, Arglist1, Arglist),
    log_file('after argparse'),
    Arglist = Arglist1,
    format('arglist ~w\n',[Arglist]),
    member(arg(graph_output,File), Arglist), 
    format('Filename ~w\n',[File]),
    graph:load_graphml(File), 
    analyze, 
    graph:save_graphml,
    halt.
    
run :- 
    argparse:argparse, 
    argparse:argument_value('input_graph',File),
    graph:load_graphml(File), 
    format('loaded ~w\n',[File]), 
    analyze, 
    graph:save_graphml,
    halt.
    
run :- halt(11).
    

:- run.
