 
 :- module(graph_doc, []).

:- use_module(library(xpath)).
 
:- use_module(library(sha)). %
 :- use_module(library(base64)).
 
:- use_module(document_dcg).
:- use_module(graph).
:- use_module(argparse).

:- use_module(library(xpath)).
 :- use_module(library('http/json')).

replace(In, From, To, Out) :-
    atomic_list_concat(L, From, In),
    atomic_list_concat(L, To, Out).
    
    
%%%%%%%%%%%%%%%%
    
    
 
 argument(X) :- argument(X,_).
 
argument('--input_graph',[default='*graph_output',description='filename to use for graph output.']). 
 
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
	
test_split(File) :-
	fm:document_extract(File,Text),
	(normalize_text(Text,Normal);Normal=Text), !,
	atom_codes(Normal,Codes1),
	trace,
	once(phrase(document_dcg:document(Lines), Codes1, _)),
	open('out.txt', write, F, []),
	atomic_list_concat(Lines, '\n', Str),
	format(F,'~w',[Str]),
	close(F).
	
	
:- debug(X).
	
graph_text(Args) :-
    format('graph tezt\n',[Args]),
    debug([graph_doc,graph_text]),
    debug([graph_doc,graph_text],'graphing file args ~w ',[Args]),
  	subset([id=Doc,text=Text],Args),
%	base64(Text,Text64),
	debug([graph_doc,graph_text1],'graphing file ~w type ~w proj ~w',[File,Type,Proj]),
	(normalize_text(Text,Normal),debug([graph_doc,graph_text1],'text normalized',[]);Normal=Text,debug([graph_doc,graph_text1],'normalization failed',[])), !,

	atom_codes(Normal,Codes1),
	length(Codes1,Len),
	debug([graph_doc,graph_text1],'splitting ~w bytes',[Len]),
	once(phrase(document_dcg:document(Lines), Codes1, Remain)),
	length(Lines,NLines),
    length(Remain,RLines),
    Show is min(RLines,5),
    length(ShowRemain, Show),
    prefix(ShowRemain, Remain),
    atom_codes(ShowAtom, ShowRemain),
	debug([graph_doc,graph_text1],'new document node ~w lines ~w type ~w proj ~w remain ~w',[Doc,NLines,Type,Proj,ShowAtom]),
	get_time(Now),
	flag(seq,_,0),
    format('top of loop',[]),
	(
		member(Line,Lines),
%        format('line: ~w\n',[Line]),
		Line \= '',
		flag(seq,Seq,Seq+1),
		debug([graph_doc,graph_text],'seq ~w sentence ~w ',[Seq,Line]),
		sha_hash(Line, Hash, []), hash_atom(Hash,Sha1),
		graph:new_node(Sent,'Sentence',[seq=Seq,text=Line,doc_id=Doc,req_type=unknown,category=sentence,sha1=Sha1]),
		graph:new_edge(Edge,Doc,Sent,has_sentence,[]),
	fail;true),
	flag(seq,Total,Total).

	
dump_docs :-
		open('docs.txt',write,F,[]),
		(
			fcypher_query('match (d:document) return d,id(d)',[],row([Doc,DocId])),
			findall(Sid, fcypher_query('match (d:document)-[]-(s:sentence) return id(s)',[],row([Sid])), Sids),
			format(F,'~w:~w ~w\n\n\n',[DocId,Doc,Sids]),
		fail;true),
		close(F).
	

	
normalize_text(TextIn,TextOut) :-
	atomic_list_concat(List, '\n', TextIn),
	normalize_text1(List,List1),
	atomic_list_concat(List1, '\n', TextOut).
normalize_text1([H|T],[N|T1]) :-
	debug([graph_doc,normalize],'r0 <~w>',[H]),
	once(normalize_space(atom(N),H);N=H),
	N \= '',
	debug([graph_doc,normalize],'r1 <~w>',[N]),
	normalize_text1(T,T1).
normalize_text1([H|T],T1) :- 
	debug([graph_doc,normalize],'r0r2a <~w>',[H]),
	once(normalize_space(atom(N),H);N=H),
	N = '',
	debug([graph_doc,normalize],'r2 ',[]),
	normalize_text1(T,T1).
normalize_text1([H|T],T1) :-
	normalize_space(atom(N),H),
	N = ' ',
	debug([graph_doc,normalize],'r3 <~w>',[H]),
   normalize_text1(T,T1).
normalize_text1([],[]) :-
	debug([graph_doc,normalize],'r4 []',[]).
	
analyze :-
    format('start analyze\n',[]),
    graph:node(Id, 'DocumentRoot', Attr),
    format('doc a6ttr ~w\n',[Attr]),
    graph_text([id=Id|Attr]),
    graph:delete_node_property(Id,'DocumentRoot',text).        % text gets too big, slows db down etc. so delete.


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

stream_report :-
    findall(Prop, stream_property(user_input, Prop), Props),
    format('Properties:~w\n',[Props]).
    
%:- debug([graph_doc,graph_text1]).    
    
fail_error(G) :-
    catch(G, Error, format('Exception ~w\n',[Error])).
		


:- argparse:add_argument('--input_graph',[default='*graph_output',description='graph input filename']). 
:- argparse:add_argument('--graph_format',[default=graphml,description='graph output format']).

run :- 
    format('hello world\n',[]),
    argparse:argparse, 
    argparse:get_argument('input_graph',File),
    argparse:show_arguments,
    argparse:get_argument('graph_format',OutputFormat),
    format('format ~w\n',[OutputFormat]),
    flag(graph_format, _, OutputFormat),
    fail_error(graph:load_graphml(File)), 
    format('loaded ~w\n',[File]), 
    analyze, 
    format('after analyze\n',[]),
    graph:save_graphml,
    halt(0).
    

:- run.
