
:- module(greplite, []).

:- set_prolog_stack(global, limit(2*10**9)).


/* 

 
*/

test_grep :-
	walk_files([match_file(['*question*'])], ['*.*'], ['./Files'], Hits),
	write_list('Hits\n',Hits).


	/*

Local grep-like interface

*/

directory_name(Dir, Name) :-
	absolute_file_name(Dir, Abs),
	atomic_list_concat(List, '/', Abs),
	reverse(List, [Name|_]).

directory_file(StartDir, RelativeDir, Include, Exclude, BaseName, AbsName) :-
	directory_name(StartDir, DirName),
	directory_files(StartDir, Files),
	member(File, Files),
	File \= '.',
	File \= '..',
	(
		exists_directory(File),
		directory_file(File, RelativeDir1, Include, Exclude, BaseName, AbsName),
		RelativeDir = [DirName|RelativeDir1]
	;
		\+ exists_directory(File),
		match_file(File, Include, Exclude),
		absolute_file_name(File, AbsName),
		RelativeDir = [DirName],
		BaseName=File
	).
	
match_file(File, Include, Exclude) :-
	match_include(File, Include),
	match_exclude(File, Exclude).
	
match_include(File, [H|T]) :-
	wildcard_match(H, File),
	match_include(File, T).
match_include(_, []).
match_exclude(File, [H|T]) :-
	\+ wildcard_match(H, File),
	match_exclude(File, T).
match_exclude(_, []).
	
search(Search, FileSpec, Directory, Hits) :-
	find_files(Search, FileSpec, Directory, Hits).

walk_files(Pipeline, Files, Exclude, X, Y, Options) :-
	catch( walk_files1(1, Pipeline, Files, Exclude, X, Y, Options), Error, (Error=escape;throw(Error))).
	
walk_files1(N, Pipeline, Files, Exclude, ['.'|Tail], HitSet, Options) :-
	intersection([output=Output], Options, _),
	directory_files('.', FileList),
	debug(grep, 'Searching directory .',[]),
	findall(D, (member(D, FileList), exists_directory(D), filter_dir(D)), Directories),
	length(Directories, NDir),
	debug(grep,'Directories: ~w',[Directories]),
	length(Tail, NTail),
	Percent is 100 * (NTail / N),
	debug(grep_stats,'Percent remaining = ~w',[Percent]),
	flag(walk_files_progress, _, Percent),
	member(FileSearch, Files),
	findall(Out,
	(
		member(F,FileList), 
		exists_file(F), 
		wildcard_match(FileSearch,F), 
		\+ exclude_file(F, Exclude),
%%%%%%%%%%%%%
		debug(grep,'Piping: ~w ~w',[F,Pipeline]),
		pipeline(F, _, Pipeline, Out),
%		format('Piping output: ~w\n',[Out])
		true
%%%%%%%%%%%%%
	), Hits1),
	walk_files1(Level, Pipeline, Files, Exclude, Directories, Hits2, Options),
	(
		Output=set, nonvar(Output),
		append(Hits1, Hits2, Hits),
		list_to_set(Hits,HitSet)
	;
		Output=escape, nonvar(Output),
		throw(escape)
	;
		var(Output),
		HitSet=[null]
	;
		append(Hits1, Hits2, HitSet)
	),
	!.

walk_files1(N, Pipeline, Files, Exclude, [Dir|Tail], HitSet, Options) :-
	intersection([output=Output], Options, _),
	Dir \= '.',
	working_directory1(Old, Dir),
	working_directory(LongDir,LongDir),
	directory_files('.', FileList),
	debug(grep,'Searching directory ~w',[Dir]),
	findall(D, (member(D, FileList), exists_directory(D), filter_dir(D)), Directories),
	length(Directories, NDir),
	length(Tail, NTail),
	debug(grep,'Directories: ~w',[Directories]),
	Percent is 100 * (NTail / N),
    debug(grep_stats, 'Percent remaining = ~w',[Percent]),
	flag(walk_files_progress, _, Percent),
	member(FileSearch, Files),
	findall(Out,
	(
		member(F,FileList), 
		exists_file(F), 
		wildcard_match(FileSearch,F), 
		\+ exclude_file(F, Exclude),
%%%%%%%%%%%%%%%
		debug(grep, 'Piping: ~w ~w',[F,Pipeline]),
		pipeline(F, _, Pipeline, Out),
%		format('Piping output: ~w\n',[Out])
		true
%%%%%%%%%%%%%%%
	), Hits1),
	walk_files1(NDir, Pipeline, Files, Exclude, Directories, Hits2, Options),
	working_directory1(_,Old),
	walk_files1(N, Pipeline, Files, Exclude, Tail, Hits3, Options),
	(
		Output=set, nonvar(Output),
	    format('Set = ~w\n',[Percent]),
		append(Hits1, Hits2, Hits2a),
		append(Hits2a, Hits3, Hits),
		list_to_set(Hits,HitSet)
	;
		Output=escape, nonvar(Output),
		throw(escape)
	;
		Output=none, nonvar(Output),
		format('Null = ~w\n',[Percent]),
		HitSet=[null]
	;
		format('Append = ~w\n',[Percent]),
		append(Hits1, Hits2, Hits2a),
		append(Hits2a, Hits3, HitSet)
	), !,
	format('Percent after append = ~w\n',[Percent]),
	working_directory(_, Old).

walk_files1(_, _, _, _, [], [], _).

exclude_file(F, List) :-
	member(EF, List),
	wildcard_match(EF, F), !.

pipeline(File, Data, [H|T], Out) :-
	catch( call(H,File,Data,Out1), Error, (Out1 = Error,log_messageF(error(pipeline,File)))),
	pipeline(File, Out1, T, Out).
	
pipeline(_, Out, [], Out).


working_directory1(Old,New) :-
	working_directory(Old,New),
%	format('wd: old ~w new ~w\n',[Old,New]),
	true.

filter_dir(D) :-
	D \= '.',
	D \= '..'.

match_file1(File, List) :-
	upcase_atom(File, UpFile),
	(file_name_extension(Base1,_,UpFile);Base1=UpFile),
	member(F, List),
	upcase_atom(F, UpF),
	file_name_extension(Base2,_,UpF),
	(File=F;Base1=Base2;wildcard_match(Base2,Base1)), 
	!.

match_file(Tokens, File, _, Out) :-
	catch( read_file_to_codes(File, Codes, []), Err, (fail)),
	format('  Searching file ~w',[File]),
	atom_codes(Atom, Codes),
	atomic_list_concat(Lines, '\n', Atom),
	flag(nhits, _, 0),
	(
		member(Line, Lines),
		member(Token, Tokens),
		wildcard_match(Token, Line),
		flag(nhits, N, N+1),
	fail;true),
	flag(nhits, NHits, NHits),
	format(' ~w hits\n',[NHits]),
	NHits > 0,
	absolute_file_name(File, Abs),
	Out = file(Abs,File,NHits).
	

remove(Chr, X,Y) :-
	atomic_list_concat(List, Chr, X),
	atomic_list_concat(List, Y).


write_list(Text, List) :-
	format('~w:\n', [Text]),
	findall(_, (member(Elem, List), format('     ~w\n', [Elem])), _).


load_flags(File) :-
	load_xml_file(File, XML),
	(
	  xpath:xpath(XML, //(flag), element(_,Attr,_)),
	  findall(_, (member(Flag=Value, Attr), flag_value(Value,Val), flag(Flag, _, Val)), _),
	fail ; true).

flag_value(V,V1) :-
	catch(atom_to_term(V,V0,_), _, fail),
	arithmetic_expression_value(V0,V1),
	!.

flag_value(V,V).

if_flag(Flag, Goal) :-
	flag(Flag, 1, 1),
	call(Goal), !.
if_flag(Flag, Goal) :-
	flag(Flag, true, true),
	call(Goal), !.


lex(String, Rev) :-
	atom_codes(String, Codes),
	tokenize(Codes, null, [], [], Tokens),
	reverse(Tokens, Rev).

tokenize([Ch|T], null, [], In, Out) :-
	lex_table(Token, First, _),
	member(F, First),
	code_match(Ch, F),
	tokenize(T, Token, [Ch], In, Out), !.

tokenize([Ch|T], Token, TokIn, In, Out) :-
	Token \= null,
	lex_table(Token, _, Last),
	findall(Ch, (member(L, Last), \+ code_match(Ch, L)), []),
	reverse(TokIn, R),
	atom_codes(Atom, R),
	Tok =.. [Token,Atom],

	tokenize(T, null, [], [Tok|In], Out), !.

tokenize([Ch|T], Token, TokIn, In, Out) :-
	Token \= null,
	tokenize(T, Token, [Ch|TokIn], In, Out), !.

tokenize([_|T], null, [], In, Out) :-
	tokenize(T, null, [], In, Out).


tokenize([], Token, Current, In, [Tok|In]) :-
	reverse(Current, R),
	atom_codes(Atom, R),
	Tok =.. [Token,Atom].


code_match(Code, Type) :-
	atomic(Type),
	code_type(Code, Type).

code_match(Code, -Type) :-
	\+ code_type(Code, Type).


lex_table(number, [digit], [-digit, -period]).
lex_table(identifier, [csym], [-csym]).



eflag(Flag, Old) :- eflag(Flag, Old, Old).

eflag(Flag, Old, New) :-
	term_to_atom1(Flag, Flag1),
	term_to_atom1(New, New1),
	flag(Flag1, Old1, New1),
	term_to_atom1(Old, Old1).


term_to_atom1(Atom, Atom) :-
	(atomic(Atom),term_to_atom(T,Atom),atomic(T);var(Atom)).
term_to_atom1(Term, Atom) :-
	compound(Term),
	term_to_atom(Term, Atom).


process_source(R) :-
	R =.. [_,Owner,Name,Type,Line,Text|_],
	ebs(Owner,_),
	type_filter(Type),
	atom_number(Line, L),
	L = 1,
	flag(owner, Owner0, Owner0),
	flag(name, Name0, Name0),
	flag(type, Type0, Type0),
	(
	  is_stream(source),
	  findall(Text1, 
		(
		  row(Owner1,Name1,Type1,Line1,Text1)
% 		  format(source, '~w\n', [Text1])
		)
		, File),
	  retractall(row(_,_,_,_,_)),
	  atomic_list_concat(File, File1),
	  lex(File1, Tokens),
	  findall(reference(Owner0,Name0,Type0,OType,TokU), 
		(
		  member(identifier(Tok),Tokens), 
		  upcase_atom(Tok,TokU), 
		  object(TokU,OType)
		), AllTokens),
	  list_to_set(AllTokens, TokenSet),
	  (	
	    member(Ref, TokenSet),
	    term_to_atom(Ref, RefAtom),
	    format(ref, '~w.\n', [RefAtom]),
	    fail;true
	  ),
%	  maplist(assert, AllTokens),
	  close(source)
	;
	  true
	),
	flag(owner, _, Owner),
	flag(name, _, Name),
	flag(type, _, Type),
	sformat(FileName, './export/source/~w-~w-~w.plsql', [Owner,Name,Type]),
%	open(FileName, write, _, [alias(source)]),
	format(slist, '~w.\n', [source(Owner,Name,Type)]),
	open('temp.txt', write, _, [alias(source)]),
	assert(row(Owner,Name,Type,Line,Text)).



