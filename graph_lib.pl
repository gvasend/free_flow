
/*

Graph tool

Integrates the following tools:
	- Neo4j
	- Gephi
	- Xmind

node
edge
graph_interface
	
*/

:- module(gephi,[]).
:- 
  use_module(library('http/http_client')),
  use_module(library('http/http_session')),
  use_module(library('http/html_write')),
  use_module(library('http/http_dispatch')),
  use_module(library('http/thread_httpd')),
  use_module(library(http/json_convert)),
  use_module(library(http/http_json)),
  use_module(library(http/json)).
  
  
:- use_module(library(sgml)).
:- use_module(library(sgml_write)).


/*


Prolog / Neo4j Fact interface

assert_n(fact(wordnet,loaded)).

gq(fact(wordnet,X)).
   [wordnet,X]
   
:- neo_assert(func([attr=value])).


*/

user:neo_assert(Term) :-
	Term =.. [Functor|Args],
	findall(Name=Value, (nth1(Index, Args, Value), format(atom(Name), 'arg~w', [Index])), Attributes),
	new_node(neo4j, _, Functor, Attributes).
	
user:neo_q(Term) :-
	Term =.. [Functor|Args],
	findall(Name, (nth1(Index, Args, Value), format(atom(Name), ',n.arg~w', [Index])), Attributes),
	atomic_list_concat(Attributes, AString),
	format(atom(X), 'id(n)~w', [AString]),
	fcypher_query('match (n:~w) return ~w',[Functor,X],row([F|List])),
	Args = List.
	
user:na(Term) :- na(_,Term).
user:na(Id, Term) :-
	Term =.. [Functor|Tail],
	(
		Tail=[Attributes],
		is_list(Attributes)
	;
		Tail=[H|T],
		\+ is_list(H),
		Attributes = [H|T]
	),
	new_node(neo4j, Id, Functor, Attributes).
user:nq(Term) :- nq(_Id, Term).
user:nq(Id,Term) :-
	Term =.. [Functor|Tail],
	(
		Tail=[Args],
		is_list(Args)
	;
		Tail=[H|T],
		\+ is_list(H),
		Args = [H|T]
	),
	findall(Name, (nth1(Index, Args, Name1=Value), format(atom(Name), ',n.~w', [Name1])), Attributes),
	atomic_list_concat(Attributes, AString),
	format(atom(X), 'id(n)~w', [AString]),
	fcypher_query('match (n:~w) return ~w',[Functor,X],row([Id|List])),
	unify_list(Args, List).
user:nr(Term) :-
	Term =.. [Functor|Tail],
	(
		Tail=[Args],
		is_list(Args)
	;
		Tail=[H|T],
		\+ is_list(H),
		Args = [H|T]
	),
	findall(Name, (nth1(Index, Args, Name1=Value), format(atom(Name), ',n.~w', [Name1])), Attributes),
	atomic_list_concat(Attributes, AString),
	format(atom(X), 'id(n)~w', [AString]),
	(
		fcypher_query('match (n:~w) return ~w',[Functor,X],row([Id|List])),
		unify_list(Args, List),
		once(del_node(Id)),
	fail;true).
	
unify_list([Name=Value|T],[Value|T1]) :-
	unify_list(T,T1).
unify_list([],[]).


	
user:neo_retractall(Term) :-
	Term =.. [Functor|Args],
	findall(Name, (nth1(Index, Args, Value), format(atom(Name), ',n.arg~w', [Index])), Attributes),
	atomic_list_concat(Attributes, AString),
	format(atom(X), 'id(n)~w', [AString]),
	(
		fcypher_query('match (n:~w) return ~w',[Functor,X],row([Id|List])),
		Args = List,
		debug(neopro, 'delete node ~w', [Id]),
		once(del_node(Id)),
	fail;true).
	

	
%:- debug(neopro).
 
  /*
  
  Generic graph interface
  
  
  
  */

:- dynamic(graph_dest/1).
  
:- dynamic(node/2).	% gephi_node(id, data)

:- dynamic(edge/4).	% gephi_node(id, from, to, data).
  
user:add_graph_dest(Dest) :-
	graph_dest(Dest).
user:add_graph_dest(Dest) :-
	\+graph_dest(Dest),
	assert(graph_dest(Dest)).
	
prep_attributes([H|T], [H1|T1]) :-
	prep_attribute(H,H1),
	prep_attributes(T,T1).
prep_attributes([], []).

prep_attribute(A=X, A=X) :-
	atomic(X).
prep_attribute(N=X, N=A) :-
	\+ atomic(X),
	term_to_atom(X,A).
	
user:health_status(List) :-
	findall(Status, (gephi:graph_dest(Dest), health_status(Dest, Status)), List).
	
% health(dest, ok, []).

user:healthy :-
	health_status(List),
	\+ member(health(_,down,_), List), !.
user:healthy :-
	user:sms_text('Simbolika database health alert'),
	fail.
	
user:del_node(Id1) :-
	increment(del_node),
	atomic_id(Id1, Id),
	must( findall(Dest1, gephi:graph_dest(Dest1), [First|Rest]) ),
	del_node(First, Id),
	(
		member(Dest, Rest),
		del_node(Dest, Id),
	fail;true).
	
user:new_node(Id1, Label, Attributes0) :-
	increment(node-Label),
	debug(new_node, 'Id ~w Label ~w Attributes ~w', [Id1, Label, Attributes]),
	prep_attributes(Attributes0, Attributes),
	atomic_id(Id1, Id),
	must( findall(Dest1, gephi:graph_dest(Dest1), [First|Rest]) ),
	new_node(First, Id, Label, Attributes),
	(
		member(Dest, Rest),
		new_node(Dest, Id, Label, Attributes),
	fail;true).

atomic_id(In, Out) :-
	nonvar(In),
	compound(In),
	term_to_atom(In, Out).
atomic_id(In, In) :-
	nonvar(In),
	\+ compound(In).
atomic_id(In, In) :-
	var(In).
	
user:new_edge(Name1, From1, To1, Label) :-
	user:new_edge(Name1, From1, To1, Label, []).
user:new_edge(Name1, From1, To1, Label, Props) :-
	increment(edge-Label),
	must(nonvar(From1),'From ~w',[new_edge(Name1, From1, To1, Label)]),
	must(nonvar(To1),'To ~w',[new_edge(Name1, From1, To1, Label)]),
	atomic_id(Name1, Name),
	atomic_id(From1, From),
	atomic_id(To1, To),
	findall(Dest1, graph_dest(Dest1), [First|Rest]),
	new_edge(First, Name, From, To, Label, Props),
	(
		member(Dest, Rest),
		new_edge(Dest, Name, From, To, Label, Props),
	fail;true).

	
 :- dynamic(neo_node/3).
 :- dynamic(relationship/4).
 :- dynamic(import_node/4).
 :- dynamic(import_edge/6).
 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  Neo4j %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- dynamic(neo4j_id/2).

health_status(neo4j, health(neo4j, Status, [url=Base|Results])) :-
	url_base(neo4j, Base),
	catch( neo4j_rest_test(Results), Error, true),
	(
		var(Error),
		Status=ok
	;
		nonvar(Error),
		Status=down,
		Results=[error(Error)]
	).
	
neo4j_rest_test([count(Count)]) :-
	cypher_query('match (n:test) return count(n)',row([Count])),
	must(Count>0,'test nodes=0',[]).
 
shortest_path(A,B,Type,Props,Id) :-
	format(atom(URL), 'http://localhost:7474/db/data/node/~w/relationships', [A]),
	format(atom(To), 'http://localhost:7474/db/data/node/~w', [B]),
	Data1 = json([ to=To, type=Type, data=json(Props) ]),
	http_post(URL, json(Data1), Reply, []),
	Reply = json(List),
	intersection([metadata=json(Meta)], List, _),
	intersection([id=Id], Meta, _).

dijkstra(A,B,Type,Props,Id) :-
	format(atom(URL), 'http://localhost:7474/db/data/node/~w/relationships', [A]),
	format(atom(To), 'http://localhost:7474/db/data/node/~w', [B]),
	Data1 = json([ to=To, type=Type, data=json(Props) ]),
	http_post(URL, json(Data1), Reply, []),
	Reply = json(List),
	intersection([metadata=json(Meta)], List, _),
	intersection([id=Id], Meta, _).	
  
get_rel_id(Id, Data) :-
	format(atom(URL), 'http://localhost:7474/db/data/relationship/~w', [Id]),
	http_get(URL, Data, []).

get_rel_id(Id, Dir, Data) :-
	format(atom(URL), 'http://localhost:7474/db/data/node/~w/relationships/~w', [Id,Dir]),
	http_get(URL, Data, []).

%url_base(neo4j, 'http://simbolika.ddns.net:57605').
url_base(neo4j, 'http://localhost:7474').


format_url(Name, URL, Path, Arguments) :-
	url_base(Name, Base),
	atomic_concat(Base, Path, Format),
	format(atom(URL), Format, Arguments).
	
format_url1(Name, URL, Path, Arguments) :-
	neo_http_mode(instant),
	url_base(Name, Base1),
	atom_concat(Base1, '/db/data', Base),
	atomic_concat(Base, Path, Format),
	format(atom(URL), Format, Arguments).
format_url1(Name, URL, Path, Arguments) :-
	neo_http_mode(batch),
	format(atom(URL), Path, Arguments).
	
new_edge(neo4j, Name, From, To, Label) :- 
	new_edge(neo4j, Name, From, To, Label, []).
new_edge(neo4j, Name, From, To, Label, Props) :-
	nonvar(Name),
	\+ neo4j_id1(Name,_),
	neo4j_id1(From, Id1),
	neo4j_id1(To, Id2),
	create_rel(Id1, Id2, Label, Props, Id),
	assert(neo4j_id(Name,Id)), !.
new_edge(neo4j, Name, From, To, Label, Props) :-
	var(Name),
	neo4j_id1(From, Id1),
	neo4j_id1(To, Id2),
	create_rel(Id1, Id2, Label, Props, Id),
	Name=Id,
	assert(neo4j_id(Name,Id)), !.
new_edge(neo4j, _, _, _, _,_).


create_rel(A,B,Type,Props,Id) :-
	neo_http_mode(instant),
	format_url1(neo4j, URL, '/node/~w/relationships', [A]),
	format_url1(neo4j, To, '/node/~w', [B]),
	Data1 = json([ to=To, type=Type, data=json(Props) ]),
	http_post_neo(URL, json(Data1), Reply, [id(Id)]),
	assert(relationship(Id,A,B,Type)).
	
create_rel(A,B,Type,Props,Id) :-
	neo_http_mode(batch),
	format_url1(neo4j, URL, '{~w}/relationships', [A]),
	format_url1(neo4j, To, '{~w}', [B]),
	Data1 = json([ to=To, type=Type, data=json(Props) ]),
	http_post_neo(URL, json(Data1), Reply, [id(Id)]),
	assert(relationship(Id,A,B,Type)).
	
create_rel(A,B,Type,Props,Id1) :-
	neo_http_mode(import),
	flag(import_id, Id1, Id1+1),				%tflag   watch out for incorrect use of tflag
	cypher_import_file(Import),											%tflag
	assert(import_edge(Import,Id1,A,B,Type,Props)),
	assert(relationship(Id1,A,B,Type)).
	
delete_rel(ID) :-
	format_url(neo4j, URL, '/db/data/node/~w', [ID]),
	http_get(URL, _, []).

get_rel_properties(ID, Props) :-
	format_url(neo4j, URL, '/db/data/relationships/~w/properties', [ID]),
	http_get(URL, Props, []).

get_rel_properties(ID, Name, Value) :-
	format_url(neo4j, URL, '/db/data/relationships/~w/properties/~w', [ID,Name]),
	http_get(URL, Value, []).
	
set_rel_properties(ID, Name, Value) :-
	format_url(neo4j, URL, '/db/data/relationships/~w/properties/~w', [ID,Name]),
	http_put(URL, Value, []).

get_all_rel(ID, Rel).


get_rel_types(Types) :-
	format_url(neo4j, URL, '/db/data/relationships/types', []),
	http_get(URL, Types, []).


get_node(ID, Data) :-
	format_url(neo4j, URL, '/db/data/node/~w', [ID]),
	http_get(URL, Data, []).
	
del_node(neo4j, mark(Id)) :-
	neo4j_id1(Id, Id1),
	set_property(ne04j, Id1, status, delete), !.
del_node(neo4j, Id) :-
	neo4j_id1(Id, Id1),
	neo_delete_node(Id1), !.
	 
neo_delete_node(ID) :-
	format_url(neo4j, URL, '/db/data/node/~w', [ID]),
	neo_http_mode(Mode),
	http_neo(Mode, 'DELETE', URL, json([]), Reply, []),
%	http_delete(URL, Reply, []),
%	format('~w', [Reply]),
	retractall(node(ID,_,_)), !.

add_label(ID, Label) :-
	neo_http_mode(instant),
%	atomic_id(ID1, ID2),
%	neo4j_id(ID2, ID),
	format(atom(Atom), '"~w"', [Label]),
	atom_codes(Atom, Codes),
%	Data = [Label],
	label_list(Label, Data),
	format_url(neo4j, URL, '/db/data/node/~w/labels', [ID]),
%	catch( http_post(URL, codes(Codes), _, [timeout(0)]), _, true).		% Don't wait for a reply. Not sure how to do this without generating an error.
	catch( http_post(URL, json(Data), _, [timeout(0)]), _, true).		% Don't wait for a reply. Not sure how to do this without generating an error.
add_label(ID, Label) :-
	neo_http_mode(batch),	
%	atomic_id(ID1, ID2),
%	neo4j_id(ID2, ID),
%	Data = [Label],
	label_list(Label, Data),
	format_url1(neo4j, URL, '{~w}/labels', [ID]),
	catch( http_post_neo(URL, json(Data), _, [timeout(0)]), _, true).		% Don't wait for a reply. Not sure how to do this without generating an error.
add_label(ID, Label) :-
	neo_http_mode(import),	
	assert(import_label(ID,Label)).
list_all_labels(Reply) :-
	format_url(neo4j, URL, '/db/data/labels', []),
	 http_get(URL, Reply, []).
	 
user:label_list([H|T], [H|T]) :- !.
user:label_list(In, [In]) :-
	atom(In).
	
user:main_label(In, In) :-
	nonvar(In),
	\+ is_list(In).
user:main_label([In|_], In) :-
	nonvar(In).
user:generic_label(In, In) :-
	nonvar(In),
	\+ is_list(In).
user:generic_label([In|T], Out) :-
	nonvar(In),
	reverse([In|T],[Out|_]).

/*

Batch operations

*/

user:tflag(TFlag, Old, New) :-
	thread_self(Name),
	term_to_atom(Name-TFlag, Flag),
	flag(Flag,Old,New).
	
neo_http_mode(Mode) :-
	tflag(neo_mode, Mode, Mode).
neo_http_mode(Old,Mode) :-
	tflag(neo_mode, Old, Mode).
	
cypher_import_file(File) :-
	tflag(import_file, File,File).
cypher_import_file(Old,New) :-
	tflag(import_file, Old,New).

user:set_neo_mode(Old,Mode) :-
	neo_http_mode(Old, Mode).
user:set_neo_mode(Mode) :-
	neo_http_mode(_, Mode).

increment_cypher_file :-
	gensym('_imp', Import1),
	cypher_import_file(_,Import1).
	
:- dynamic(batch_operation/4).

test_json :-
	read_file_to_codes('json.txt', Codes, []),
	atom_codes(Atom, Codes),
	atom_json_term(Atom, Json, []),
	format('~w\n',[Json]).


:- set_neo_mode(instant).

user:flush(batch) :-
	neo_http_mode(batch),
	findall(batch(A,B,C,D), batch_operation(A,B,C,D), Commands),
	ignore(send_batch(Commands)),
	retractall(batch_operation(_,_,_,_)),
	retractall(neo4j_id(_,_)), !.
	
:- cypher_import_file(_,'_imp0').			%tflag

user:flush(import) :-
	neo_http_mode(import),
	cypher_import_file(Import),
	findall(Label, import_node(Import, Id,Label,Attributes), Labels),	%tflag
	list_to_set(Labels, LabelSet),
	(
		member(Label, LabelSet),
		retry(process_import(Import,Label)),
	fail;true
	),
	findall(Label, import_edge(Import, Id,From,To,Label,_), EdgeLabels),	%tflag
	list_to_set(EdgeLabels, EdgeLabelSet),
	(
		member(Label, EdgeLabelSet),
		retry(process_import_edge(Import, Label)),
	fail;true
	),
	retractall(import_node(Import,_,_,_)),		%tflag
	retractall(import_edge(Import,_,_,_,_,_)),	%tflag
	!.		%tflag
user:flush(execute) :-
	cypher_import_file(Import),
	home_dir(Home),
	atomic_list_concat([Home,'Import/', Import, '.csv'], File),
	ignore(execute_cypher_file(File)),
	increment(execute_cypher),
	increment_cypher_file,	%tflag
	!.
user:flush(execute) :-
	cypher_import_file(Import),
	home_dir(Home),
	atomic_list_concat([Home,'Import/', Import, '.csv'], File),
	\+ exists_file(File),
	increment(execute_cypher_error),
	format('cannot execute ~w, it does not exist.\n',[File]), !.
user:flush(_).
	
user:reset_import :-
%	File = 'neo4j.cyp',
%	exists_file(File),
%	delete_file(File), 
	!.
user:reset_import.
	
execute_cypher_file(File) :-
error_log_message((
	exists_file(File),
	read_file_to_codes(File, Codes, []),
	atom_codes(Atom, Codes),
	atomic_list_concat(Commands, ';', Atom),
	(
		member(Command, Commands),
%		format('Execute ~w\n',[Command]),
		cypher_query(Command, Result),
%		format('Results ~w\n',[Result]),
		\+ member(errors=[], Result),
		log_messageF(error(execute_cypher_file(Command,Result))),
	fail;true)
	)).

	
user:flush(_).

user:error_log_message(Goal) :-
	catch(Goal, Error, (log_messageF(error(Error,Goal)),fail)).

retry(Goal) :- retry(Goal,5).
retry(Goal, Count) :-
	Count = 1,
	Next is Count-1,
	trace,
	catch(Goal, Error, (format('Goal ~w failed, error: ~w retry ~w\n',[Goal,Error,Next]),retry(Goal, Next))).
retry(Goal, Count) :-
	Count > 1,
	Next is Count-1,
	catch(Goal, Error, (format('Goal ~w failed, error: ~w retry ~w\n',[Goal,Error,Next]),retry(Goal, Next))).
retry(Goal, Count) :-
	Count = 0,
	throw(error('max retries')).
	
process_import(Import,Label) :-
% find universe of attributes
	flag(import_id,Curr,Curr),
	log_messageF(info(import_nodes,Curr)),
	findall(Attribute, (import_node(Import, _, Label, Attributes), member(Attribute=_Value, Attributes)), AttributeList), %tflag
	list_to_set(AttributeList, AttributeSet),
	findall(Name=Value, member(Name, AttributeSet), RowMatcher),
	findall(Name, member(Name, AttributeSet), Line1),
	findall(Row,
	(
		import_node(Import, Id, Label, Attributes),	%tflag
		intersection(RowMatcher, Attributes, _),
		findall(V, member(_=V, RowMatcher), Attributes1),
		nullify(Attributes1, Attributes2),
		Row =.. [row|Attributes2]
	), Data1),
	Row1 =.. [row|Line1],
	Data = [Row1|Data1],
	gensym(node, Mod),
	home_dir(Home),
	flatten([Home,'Import/',Label,Mod,Import|['.csv']], List2),
	atomic_list_concat(List2, FileName),
	term_to_atom(Data, AData),
	replace(AData, '\n', '', AData2),
	term_to_atom(Data2, AData2),
	length(Data2,NDx),
	ND is NDx - 1,
	log_messageF(info('Importing ~w nodes for ~w\n',[ND,Label])),
	csv_write_file(FileName,Data2,[encoding(utf8)]),
	increment(csv_write_node),
	AttributeSet = [_|ASet],
	findall(Field, 
	(
		member(Name, ASet),
		format(atom(Field), ', ~w: csvLine.~w ', [Name,Name])
	), CSVFields),
	atomic_list_concat(CSVFields, CSVFields1),
	absolute_file_name(FileName, Abs),
	flatten([Label], Label1),
	atomic_list_concat(Label1, ':', Labelx),
	
	format(atom(A), 'USING PERIODIC COMMIT\nLOAD CSV WITH HEADERS FROM "file:///~w" AS csvLine\n MERGE (p:~w { id: toInt(csvLine.id) ~w }) ', [Abs,Labelx,CSVFields1]),
%	format('import ~w\n',[A]),
	log_messageF(info(import,Import,A,ND)),
	cypher_queryF(Import, A, R),
%	delete_file(Abs),
	generic_label(Label, L1),
	ignore(fcypher_queryF(Import,'CREATE CONSTRAINT ON (n:~w) ASSERT n.id is UNIQUE', [L1], _)),
	true.
	
user:fcypher_queryF(Format, Arguments) :-
	cypher_import_file(Import),
	fcypher_queryF(Import, Format, Arguments, _).
user:cypher_queryF(Text) :-
	cypher_import_file(Import),
	cypher_queryF(Import, Text, _).
	
fcypher_queryF(Import, Format, Arguments, _) :-
	home_dir(Home),
	atomic_list_concat([Home,'Import/',Import,'.csv'], FileName),
	open(FileName, append, Wr, [encoding(utf8)]),
	format(Wr, Format, Arguments),
	format(Wr, ';\n',[]),
	close(Wr).
cypher_queryF(Import, Text, _) :-
	home_dir(Home),
	atomic_list_concat([Home,'Import/',Import,'.csv'], FileName),
	open(FileName, append, Wr, [encoding(utf8)]),
	format(Wr, Text, []),
	format(Wr,';\n',[]),
	close(Wr).
	
% USING PERIODIC COMMIT
% LOAD CSV WITH HEADERS FROM "http://docs.neo4j.org/chunked/2.1.6/csv/import/roles.csv" AS csvLine
% MATCH (person:Person { id: toInt(csvLine.personId)}),(movie:Movie { id: toInt(csvLine.movieId)})
% CREATE (person)-[:PLAYED]->(movie)	

lookup_import_id_type(Import, Lookup, Lookup, Type) :-
	once(gephi:import_node(Import,Lookup,Type,_)), !.
lookup_import_id_type(_Import, Lookup, Id, Type) :-
	number(Lookup),
	get_node_data(Lookup, Node),
	neo_data(labels, Node, [Type|_]),
	neo_data(props, Node, property(id,Id)).
	
process_import_edge(Import,Label) :-
	flag(import_id,Curr,Curr),
	log_messageF(info(import_edges,Curr)),
	
	once(import_edge(Import,I,F0,T0,Label,PropsLabel)),	%tflag
% PropsLabel = [a=v,a1=v1...]
% Note: we are trying to link to existing nodes in some case so the following code won't always workbook

%	must(once(gephi:import_node(Import,F,FL,_)), 'import edge unable to find from node ~w', [F]),	%tflag
%	must(once(gephi:import_node(Import,T,TL,_)), 'import edge unable to find to node ~w', [T]),	%tflag


% The devil is always in the details... Attempting to mix nodes being currently imported with nodes that have been imported in the past or instantly created
% The problem is that those nodes won't be present in the import table and will only have the id property if created via import. For now, if the node is not
% present in the import table we attempt to treat the lookup number as an internal neo4j id and look for an id property. if found all is ok. It may be possible
% to create an Id property and assign it an id to use in the import process. May do later.
	
	lookup_import_id_type(Import, F0, F, FL),
	lookup_import_id_type(Import, T0, T, TL),
	
	generic_label(FL, FL1),
	generic_label(TL, TL1),
	findall(RowData,
	(
		import_edge(Import, Id,From,To,Label,Props),		%tflag
		findall(PrVal, member(_=PrVal, Props), PropList),
		RowData =.. [row,Id,From,To|PropList]
	), Rows),
	length(Rows,NRx),
	NR is NRx - 1,
	gensym(edge, Edge),
	log_messageF(info('Importing ~w relationships for ~w -> ~w -> ~w\n',[NR,FL1,Label,TL1])),
	home_dir(Home),
	atomic_list_concat([Home, 'Import/',Label, Edge, Import,'.csv'], FileName),
	findall(RA, member(RA=_, PropsLabel), PropAttr),
	RowOne =.. [row,id,from,to|PropAttr],
	csv_write_file(FileName,[RowOne|Rows],[encoding(utf8)]),
	increment(csv_write_edge),
	absolute_file_name(FileName, Abs),
	LabelX = FL1,
	FIX = from,
	LabelY=TL1,
	FIY = to,
	RelLabel=Label,
	format_rel_props(PropsLabel, RelProps),
	format(atom(A1), 
	'USING PERIODIC COMMIT\nLOAD CSV WITH HEADERS FROM "file:///~w" AS csvLine\nMATCH (x:~w { id: toInt(csvLine.~w)}),(y:~w { id: toInt(csvLine.~w)})\nMERGE (x)-[:~w ~w]->(y)', 
		[Abs,LabelX,FIX,LabelY,FIY,RelLabel,RelProps]),
%	format('import ~w\n',[A1]),
	log_messageF(info(import,Import,A1,NR)),
	cypher_queryF(Import,A1, R),
%	ignore(delete_file(Abs)),
	true.
	
format_rel_props([], '').
format_rel_props([Attr=Val|_], Props) :-
	format(atom(Props), '{ ~w: csvLine.~w }', [Attr,Attr]).
% *****WARN*******
% Handles only a single property per relationship label
	
% CREATE (person)-[:PLAYED { role: csvLine.role }]->(movie)	
%LOAD CSV WITH HEADERS FROM "http://docs.neo4j.org/chunked/2.1.6/csv/import/persons.csv" AS csvLine
%CREATE (p:Person { id: toInt(csvLine.id), name: csvLine.name })
	
csv_write_file1(File, Data, _) :-
	trace,
	open(File, write, Wr, []),
	(
		member(Row, Data),
		Row =.. [_|Data1],
		term_to_atom(Data1, Atom),
		atom_codes(Atom, [_|List]),
		reverse(List, [_|RList]),
		reverse(RList, List1),
		atom_codes(Atom1, List1),
		replace(Atom1, '\n', '', Atom2),
		format(Wr, '~w\n', [Atom2]),
	fail;true
	),
	close(Wr).
	
nullify([H|T], [H|Out]) :-
	nonvar(H),
%	atomic_list_concat(['\'',H,'\''], H1),
	nullify(T, Out).
nullify([H|T], [null|Out]) :-
	var(H),
	nullify(T, Out).
nullify([], []).
	
send_batch(Commands) :-
	findall(json([method=Method, to=To, id=Id,body=Data]),
	(
		( member(batch(To,json(Data),Id,Options), Commands), intersection([method=Method], Options, _) )
	), AllData),
%	numlist(1, 5, List),
	url_base(neo4j, Base),
	format(atom(URL), '~w/db/data/batch', [Base]),
%	member(_, List),
	format('sending to ~w\n',[URL]),
	catch( http_post(URL, json(AllData), Reply, []), Error, (log_messageF(error(batch_send_error,Error)),fail)).

http_neo(instant, 'DELETE', URL, Data, Reply, _Options) :-
	http_delete(URL, Reply, []).

	
http_post_neo(URL, Data, Reply, Options) :-
	neo_http_mode(Mode),
	http_neo(Mode, 'POST', URL, Data, Reply, Options).

http_neo(batch, Method, URL, Data, Reply, Options) :-
	intersection([id(Id)], Options, _),
	flag(neo_batch_id, Id, Id+1),
	assert(batch_operation(URL, Data, Id, [method=Method])).
	
http_neo(instant, 'POST', URL, Data, Reply, Options) :-
	intersection([id(ID)], Options, _),
	http_post(URL, Data, Reply, Options),
	Reply = json(List),
	intersection([metadata=json(Meta)], List, _),
	intersection([id=ID], Meta, _),
	intersection([data=json(Data)], List, _).
	
create_rel11(A,B,Type,Props,Id) :-
	format_url(neo4j, URL, '/db/data/node/~w/relationships', [A]),
	format_url(neo4j, To, '/db/data/node/~w', [B]),
	Data1 = json([ to=To, type=Type, data=json(Props) ]),
	http_post(URL, json(Data1), Reply, []),
	Reply = json(List),
	intersection([metadata=json(Meta)], List, _),
	intersection([id=Id], Meta, _),
	assert(relationship(Id,A,B,Type)).
	

get_node_data(Id, Results) :-
	fcypher_query('match (n) where id(n)=~w return n',[Id],R),
	must(member(errors=[], R) ,'Error trying to lookup node data on ~w', [Id]),
	member(results=[Results|_], R).
	
neo_data(node,json(List), Node) :-
	member(data=Data, List),
	member(json(Item), Data),
	member(graph=json(Graph), Item),
	member(nodes=[json(Node)|_], Graph).
neo_data(labels,json(List), Labels) :-
	member(data=Data, List),
	member(json(Item), Data),
	member(graph=json(Graph), Item),
	member(nodes=[json(Node)|_], Graph),
	member(labels=Labels, Node).
neo_data(props,json(List), property(Prop, Value)) :-
	member(data=Data, List),
	member(json(Item), Data),
	member(graph=json(Graph), Item),
	member(nodes=[json(Node)|_], Graph),
	member(properties=json(Props), Node),
	member(Prop=Value, Props).
neo_data(rel,json(List), Rel) :-
	member(data=Data, List),
	member(json(Item), Data),
	member(graph=json(Graph), Item),
	member(nodes=[json(Node)|_], Graph),
	member(relationships=Rel, Node).
	
set_property(neo4j, Id, Property, Value) :-
	fcypher_query('MATCH (x) where id(x)=~w SET x.~w = "~w" RETURN x', [Id,Property,Value], _).

del_property(neo4j, Id, Property) :-
	fcypher_query('MATCH (x) where id(x)=~w REMOVE x.~w RETURN x', [Id,Property], _).

/*

{
  "statements" : [ {
    "statement" : "CREATE (n) RETURN id(n)"
  } ]
}

MATCH (n { name: 'Andres' })
SET n.name = NULL RETURN n

*/


user:fcypher_query(Format, Arguments, List) :-
	user:fcypher_query(Format, Arguments, List, []).

user:fcypher_query(Format, Arguments, List, Options) :-
	\+ member(background, Options),
	format(atom(Atom), Format, Arguments),
	cypher_query(Atom, List).
user:fcypher_query(Format, Arguments, List, Options) :-
	member(background, Options),
	format(atom(Atom), Format, Arguments),
	thread(cypher_query(Atom, List)).
	
user:thread(Goal) :-
	thread_create(Goal, _, []).
	
user:cypher_query(Query, List) :-
	once((var(List);is_list(List))),
	Data1 = json([statements=[json([statement=Query,resultDataContents=[graph,row]]) ]]),
	format_url(neo4j, URL, '/db/data/transaction/commit', []),
	http_post(URL, json(Data1), Reply, []),						% need to add timeout
	Reply = json(List).
user:cypher_query(Query, Rep) :-
	nonvar(Rep),
	Rep = row(Row),
	Data1 = json([statements=[json([statement=Query,resultDataContents=[graph,row]]) ]]),
	format_url(neo4j, URL, '/db/data/transaction/commit', []),
	http_post(URL, json(Data1), Reply, []),
	Reply = json(List),
	member(results=[json(Results)|_], List), 
	member(data=Data, Results), 
	member(json(Record), Data),
	member(row=Row, Record).
	
user:find_node_id(Type, Attribute, Value, Id) :-	
	fcypher_query('match (n:~w { ~w: ~w }) return n', [Type, Attribute, Value], [results=[json(List)],_]), 
	member(data=Data, List), 
	member(json(Data1), Data), 
	member(graph=json(Data2), Data1), 
	member(nodes=Node, Data2), 
	member(json(Attributes), Node), 
	intersection([id=Id], Attributes, _), !.
user:find_node_id(Attribute, Value, Id) :-	
	fcypher_query('match (n { ~w: ~w }) return n', [Attribute, Value], [results=[json(List)],_]), 
	member(data=Data, List),
	member(json(Data1), Data), 
	member(graph=json(Data2), Data1), 
	member(nodes=Node, Data2), 
	member(json(Attributes), Node), 
	intersection([id=Id], Attributes, _), !.
user:find_node_id1(Format, Arguments, Id) :-	
	fcypher_query(Format, Arguments, [results=[json(List)],_]), 
	member(data=Data, List),
	member(json(Data1), Data), 
	member(graph=json(Data2), Data1), 
	member(nodes=Node, Data2), 
	member(json(Attributes), Node), 
	intersection([id=Id], Attributes, _), !.
	
new_node(neo4j, Id, Label, Attributes) :-
	neo_http_mode(Mode),
	member(Mode, [instant,batch]),
	nonvar(Id),
	debug(new_node, 'new_node instant nonvar', []),
	\+ neo4j_id1(Id,_),
	create_node(Id1, json([iname=Id|Attributes]), _Data),
	add_label(Id1, Label),
	assert(neo4j_id(Id, Id1)), !.
new_node(neo4j, Id, Label, Attributes) :-
	neo_http_mode(Mode),
	member(Mode, [instant,batch]),
	var(Id),
	debug(new_node, 'new_node instant var', []),
	create_node(Id1, json(Attributes), _Data),
	add_label(Id1, Label),
	Id=Id1,
	assert(neo4j_id(Id, Id1)), !.
new_node(neo4j, Id1, Label, Attributes) :-
	neo_http_mode(import),
	var(Id1),
	debug(new_node, 'new_node import var', []),
	flag(import_id, Id1, Id1+1),		%tflag  tflag->flag
	cypher_import_file(Import),											%tflag
	assert(import_node(Import, Id1, Label, [id=Id1|Attributes])),		%tflag
	optional(Id=Id1),
	assert(neo4j_id(Id, Id1)), !.
new_node(neo4j, Id, Label, Attributes) :-
	neo_http_mode(import),
	nonvar(Id),
	debug(new_node, 'new_node import nonvar', []),
	\+ neo4j_id(Id,_),
	flag(import_id, Id1, Id1+1),		%tflag  tflag->flag
	cypher_import_file(Import),											%tflag
	assert(import_node(Import, Id1, Label, [id=Id1|Attributes])),
	optional(Id=Id1),
	assert(neo4j_id(Id, Id1)), !.
new_node(neo4j, _, _, _).

optional(Goal) :-
	call(Goal), !.
optional(_).
user:cflag(Flag, Old, New) :-
	term_to_atom(Flag, TFlag),
	flag(TFlag, Old, New).
	
create_node(ID, Data1, Data) :-
	format_url1(neo4j, URL, '/node', []),
	http_post_neo(URL, json(Data1), Reply, [id(ID)]),
	assert(neo_node(ID,Data,[])).

	
	
neo4j_id1(Id1, Id2) :-
	neo4j_id(Id1, Id2).
neo4j_id1(Id1, Id1) :-
	number(Id1).
neo4j_id1(Id1, Id2) :-
	\+ neo4j_id(Id1, Id2),
	find_node_id(iname, Id1, Id2),
	assert(neo4j_id(Id1, Id2)).
	
/*

Gephi interface

van: Add node 
## cn: Change node 
## dn: Delete node 
## ae: Add edge 
## ce: Change edge 
## de: Delete edge 

{"an":{"A":{"label":"Streaming Node A","size":2}}} // add node A
{"an":{"B":{"label":"Streaming Node B","size":1}}} // add node B
{"an":{"C":{"label":"Streaming Node C","size":1}}} // add node C
{"ae":{"AB":{"source":"A","target":"B","directed":false,"weight":2}}} // add edge A->B
{"ae":{"BC":{"source":"B","target":"C","directed":false,"weight":1}}} // add edge B->C
{"ae":{"CA":{"source":"C","target":"A","directed":false,"weight":2}}} // add edge C->A
{"cn":{"C":{"size":2}}}  // changes the size attribute to 2
{"cn":{"B":{"label":null}}}  // removes the label attribute
{"ce":{"AB":{"label":"From A to B"}}} // add the label attribute
{"de":{"BC":{}}} // delete edge BC
{"de":{"CA":{}}} // delete edge CA
{"dn":{"C":{}}}  // delete node C

{"an":{
    "A":{"label":"Streaming Node A","size":2}
    "B":{"label":"Streaming Node B","size":1}
    "C":{"label":"Streaming Node C","size":1}
  }
}


*/

:- dynamic(gephi_node/2).	% gephi_node(id, data)

:- dynamic(gephi_edge/4).	% gephi_node(id, from, to, data).

post_update(Atom) :-
	atom_codes(Atom, Codes),
	http_post('http://localhost:8888/workspace0?operation=updateGraph', codes(Codes), Reply, []).

delete_node(Node) :-
	format(atom(Atom), '{"dn":{"~w":{}}}', [Node]),
	retractall(gephi_node(Node,_)),
	post_update(Atom).
delete_nodes([]).
delete_nodes([H|T]) :-
	delete_node(H),
	delete_nodes(T).

change_node(Node, Attribute, Value) :-
	format(atom(Atom), '{"cn":{"~w":{"~w":~w}}}', [Node, Attribute, Value]),
	post_update(Atom).

new_edge(gephi, Name, From, To, Label) :-
	add_edge(Name, From, To, [label=Label]).

add_edge(From, To, Attributes) :-
	atomic_concat(From, To, Name),
	add_edge(Name, From, To, Attributes).
add_edge(Name, From, To, Attributes) :-
	add_edge(Name, From, To, false, 2, Attributes).
add_edge(Name1, From, To, Directed, Weight, _Attributes) :-
	compute_name(Name1, Name),
	format(atom(Atom), '{"ae":{"~w":{"source":"~w","target":"~w","directed":~w,"weight":~w}}}', [Name,From,To,Directed,Weight]),
	post_update(Atom),
	assert(gephi_edge(Name, From, To, [])).

change_edge(Name, Attribute, Value) :-
	format(atom(Atom), '{"ce":{"~w":{"~w":"~w"}}}', [Name, Attribute, Value]),
	post_update(Atom).
	
compute_name1(X+Y,Z) :-
	atomic_concat(X, Y, Z), !.
compute_name(X,X).


delete_edges([]).
delete_edges([H|T]) :-
	delete_edge(H),
	delete_edges(T).
	
delete_edge(Name) :-
	format(atom(Atom), '{"de":{"~w":{}}}', [Name]),
	post_update(Atom),
	retractall(gephi_edge(Name,_,_,_)).

add_nodes([]).
add_nodes([H|T]) :-
	add_node(H),
	add_nodes(T).

new_node(gephi, Id, Label, Attributes) :-
	add_node(Id, Label, Attributes).
	
add_node(Name) :- add_node(Name, Name).
add_node(Name, Label) :- add_node(Name, Label, [size=2]).	
add_node(Name, Label, Attributes) :-
	format_attributes(Attributes, AAtom),
	format(atom(Atom), '{"an":{"~w":{"label":"~w" ~w}}}', [Name,Label,AAtom]),
%	format(atom(Atom), '{"an":{"~w":{"label":"~w"}}}', [Name,Label]),
	post_update(Atom),
	assert(gephi_node(Name, [])).
	
format_attributes([], '').
format_attributes([N=V|T], Atom) :-
	format_attributes(T, A1),
	format(atom(Atom), ',"~w":"~w" ~w', [N,V,A1]).

test(ID, Data) :-
	create_node(ID, [foo=bar], Data).
	

test_neo4j :-
	create_node(Id1, json([name=jerry]), Data),
	create_node(Id2, json([name=cat]), Data1),
	create_rel(Id1, Id2, connected, [], Id),
	add_label(Id1, ['"test"']).
	
test_gephi :-
	List = [a,b,c,d,e,f,g,h,i,j,k],
	add_nodes(List),
	(
		select(A, List, Remain),
		member(B, Remain),
		add_edge(A, B),
		sleep(0.3),
	fail;true
	).
	
	
erase_all :-
	findall(Edge, gephi_edge(Edge, _, _, _), Edges),
	delete_edges(Edges),
	findall(Node, gephi_node(Node, _), Nodes),
	delete_nodes(Nodes).


/*

Traversal

*/

traverse_rel.

traverse_path.

traverse_nodes.

/*

traverse([NodeText,RelText|Out1]) :-
	start_node(Node),
	write_node(Node,NodeText),
	rel(Node,Rel,Node1),
	write_rel(Rel,RelText),
	write_node(Node1,NodeText1),
	traverse(Node1,[Node],Out1).
	
traverse(Node,Blocked,[RelText,NodeText|Out1]) :-
	rel(Node,Rel,Node1),
	\+ member(Node1, Blocked),
	write_rel(Rel,RelText),
	write_node(Node1,NodeText),
	traverse(Node1,[Node|Blocked],Out1).
	
traverse(Node,Blocked,['']) :-
	rel(Node,Rel,Node1),
	\+ member(Node1, Blocked).

Xmind Interface

#-*- coding: utf-8 -*-
import xmind
from xmind.core import workbook,saver
from xmind.core.topic import TopicElement

w = xmind.load("test.xmind") # load an existing file or create a new workbook if nothing is found

s1=w.getPrimarySheet() # get the first sheet
s1.setTitle("first sheet") # set its title
r1=s1.getRootTopic() # get the root topic of this sheet
r1.setTitle("we don't care of this sheet") # set its title

s2=w.createSheet() # create a new sheet
s2.setTitle("second sheet")
r2=s2.getRootTopic()
r2.setTitle("root node")


t1=TopicElement() # create a new element
t1.setTopicHyperlink(s1.getID()) # set a link from this topic to the first sheet given by s1.getID()
t1.setTitle("redirection to the first sheet") # set its title

t2=TopicElement()
t2.setTitle("second node v2")
t2.setURLHyperlink("https://xmind.net") # set an hyperlink

t3=TopicElement()
t3.setTitle("third node")
t3.setPlainNotes("notes for this topic") # set notes (F4 in XMind)
t3.setTitle("topic with \n notes")

t4=TopicElement()
t4.setFileHyperlink("logo.jpeg") # set a file hyperlink
t4.setTitle("topic with a file")


# then the topics must be added to the root element

r2.addSubTopic(t1)
r2.addSubTopic(t2)
r2.addSubTopic(t3)
r2.addSubTopic(t4)

topics=r2.getSubTopics() # to loop on the subTopics
for topic in topics:
    topic.addMarker("symbol-plus")

w.addSheet(s2) # the second sheet is now added to the workbook
rel=s2.createRelationship(t1.getID(),t2.getID(),"test") # create a relationship
s2.addRelationship(rel) # and add to the sheet

xmind.save(w,"test2.xmind") # and we save

*/
:- dynamic(xmind_id/2).


clean_attributes(OpIn, OpOut) :-
	findall(Attr=Value, 
	(
		member(Attr=OldVal, OpIn), 
		filter_text(OldVal, Value1, [include=ascii]),
		norm_space(Value1,Value2),
		replace(Value2,'"','\'',Value)
	), OpOut).

user:new_node(xmind, Id, Label, Options0) :-
%	trace,
	\+ xmind_id1(Id, _),
%	Id \= topic0,
%	ignore(user:new_node(xmind, Label, topic0, [title=Label])),
	createTopic(Topic),
	clean_attributes(Options0, Options),
%	debug(xmind_node, 'cleaned attributes ~w ~w', [Options0,Options]),
	debug(xmind_node, 'new node ~w ~w ~w',[Id, Label, Options]),
	set_title(Topic, Options),
	set_marker(Topic, Options),
	set_url(Topic, Options),
	set_file(Topic, Options),
	set_topic_link(Topic, Options),
	set_notes(Topic, Options),
%	xmind_id(Label,LabelTopic),
%	addSubTopic(LabelTopic, Topic),
	addSubTopic(topic0,Topic),				% Link to root temporarily
	assert(xmind_id(Id, Topic)), !.							%fix


set_marker(Id, Options) :-
	(
		member(marker=Marker, Options),
		addMarker(Id, Marker),
	fail;true).
set_url(Id, Options) :-
	member(url=URL, Options),
	setURLHyperlink(Id, URL), !.
set_url(Id, Options) :-
	member(link=URL, Options),
	setURLHyperlink(Id, URL), !.
set_url(_, _).

set_file(Id, Options) :-
	member(file=Value, Options),
	setFileHyperlink(Id, Value), !.
set_file(_, _).

set_topic_link(Id, Options) :-
	member(topic_link=Value, Options),
	setTopicHyperlink(Id, Value), !.
set_topic_link(_, _).

set_notes(Id, Options) :-
	member(notes=Value, Options),
	setPlainNotes(Id, Value), !.
set_notes(Id, Options) :-
	findall(Line,
	(
		member(Name=Value1, Options),
		replace(Value1, '"', '', Value),
		format(atom(Line), '~w: \\t~w \\n', [Name,Value])
	), Lines),
	atomic_list_concat(Lines, Text),
	setPlainNotes(Id, Text), !.
	

set_title(Id, Options) :-
	member(title=Value, Options),
	setTitle(Id, Value), !.
set_title(_, _).

user:new_node1(xmind, Id, Label, Attributes) :-
	\+ xmind_id(Id, _),
	Id \= topic0,
	ignore(user:new_node(xmind, Label, topic0, [Label])),
	createTopic(Topic),
	once(titleAttribute(Attributes, Title0)),	%fix
	once(textAttribute(Attributes, Notes0)),		%fix
	filter_text(Title0, Title1, [include=ascii]),
	filter_text(Notes0, Notes1, [include=ascii]),
	norm_space(Title1,Title),
	norm_space(Notes1,Notes),
%	intersection(['Title'=Title,'Text'=Notes], Attributes, _),
	format(atom(Text), '~w:~w', [Title,Label]),		%fix
	setTitle(Topic, Text),
	setPlainNotes(Topic, Notes),
%	set_attributes(Topic, Attributes),
	xmind_id(Label,LabelTopic),
	addSubTopic(LabelTopic, Topic),
	assert(xmind_id(Id, Topic)), !.							%fix
user:new_node(xmind, topic0, topic0, Attributes) :-
	assert(xmind_id(topic0,topic0)).
	
titleAttribute(Attr, Title) :-
	member('Title'=Title, Attr).
titleAttribute(Attr, tbd).
textAttribute(Attr, Title) :-
	member('Text'=Title, Attr).
textAttribute(Attr, none).
	
xmind_id1(X, Y) :- xmind_id(X,Y).
xmind_id1(root,topic0).
	
user:new_edge(xmind, Name, From, To, Label, Props) :-
	member(relationship=non_pc, Props),
	xmind_id1(From,Fid),
	xmind_id1(To,Tid),
%	non_parent_child(Label,From,To),
	createRelationship(Rel,sheet0,Fid,Tid,Label),
	assert(xmind_id(Name,Rel)), !.						%fix
user:new_edge(xmind, Name, From, To, Label, Props) :-
	\+ member(relationship=non_pc, Props),						% default is pc relationship
	xmind_id1(From,Fid),
	xmind_id1(To,Tid),
	\+ non_parent_child(Label,From,To),
	addSubTopic(Fid,Tid).
	
:- dynamic(parent_child/3).
:- dynamic(non_parent_child/3).

user:add_pc(Label) :-
	\+ non_parent_child(Rel,_,_),
	assert(parent_child(Label,_From,_To)), !.
user:add_non_pc(Label,From,To) :-
	\+ non_parent_child(Label,_,_),
	assert(non_parent_child(Label,_From,_To)), !.
	
addSubTopic(Topic1, Topic2) :-
	format(xmind, '\n~w.addSubTopic(~w)\n', [Topic1,Topic2]).


	
	
set_property(Id, Property, Value) :-	
	format(xmind, '\n~w.set~w("~w")\n', [Id,Property,Value]).
setURLHyperlink(Id, Link) :-
	format(xmind, '\n~w.setURLHyperlink("~w")\n', [Id,Link]).
setTitle(Id, Title) :-
	format(xmind, '\n~w.setTitle("~w")\n', [Id,Title]).
setPlainNotes(Id, Notes) :-
	format(xmind, '\n~w.setPlainNotes("~w")\n', [Id,Notes]).
addMarker(Id, Marker) :-
	format(xmind, '\n~w.addMarker("~w")\n', [Id,Marker]).
create_sheet(Workbook,Sheet) :-
	xvar(sheet, Sheet),
	format(xmind, '\n~w=~w.createSheet()\n', [Sheet,Workbook]).
add_sheet(Workbook,Sheet) :-
	format(xmind, '\n~w.addSheet(~w)\n', [Workbook,Sheet]).
createRelationship(Rel,Sheet,From,To,Label) :-
	xvar(rel, Rel),
	format(xmind, '\n~w=~w.createRelationship(~w.getID(),~w.getID(),"~w")\n', [Rel,Sheet,From,To,Label]),
	format(xmind, '\n~w.addRelationship(~w)\n', [Sheet,Rel]).
setFileHyperlink(Id, Hyper) :-
	format(xmind, '\n~w.setFileHyperlink("~w")\n', [Id,Hyper]).
	
createTopic(Topic) :-
	xvar(topic, Topic),
	format(xmind, '\n~w=TopicElement()\n', [Topic]).

load(Workbook,File) :-
	xvar(workbook, Workbook),
	format(xmind, '\n~w=xmind.load("~w")\n', [Workbook,File]).
	
save(Workbook, File) :-
	format(xmind, '\nxmind.save(~w,"~w")\n', [Workbook,File]).
	
xvar(Root, Sym) :-
	nonvar(Sym).
xvar(Root, Sym) :-
	var(Sym),
	gensym(Root, Sym).
	
get_primary_sheet(Workbook, Sheet) :-
	xvar(sheet, Sheet),
	format(xmind, '\n~w=~w.getPrimarySheet()\n\n', [Sheet, Workbook]).
	
get_root_topic(Sheet,Topic) :-
	xvar(topic, Topic),
	format(xmind, '\n~w=~w.getRootTopic()\n', [Topic,Sheet]).
	
create_mm :-
	open('create_mm.py', write, MM, [alias(xmind),encoding(utf8)]),
	retractall(xmind_id(_,_)),
	format(xmind, 'import xmind\nfrom xmind.core import workbook,saver\nfrom xmind.core.topic import TopicElement\n\n',[]).
	
save_exec(Workbook,File) :-
	save(Workbook, File),
	close(xmind),
%	win_exec('python create_mm.py', hide),
	shell('python create_mm.py', Status),
	must(Status=0, 'python error ~w', [Status]),
	sleep(2),
%	win_shell(open, File, show),
	true.


user:filter_text(TextIn, TextOut, Options) :-
	intersection([include=Type], Options, _),
	atom_chars(TextIn, Chars1),
	findall(C, (member(C, Chars1), once(char_type(C,Type))), Chars2),
	atom_chars(TextOut, Chars2).
