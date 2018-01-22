/*


*/

:- module(xmind,[]).

:- use_module(graph_lib).
:- use_module(fbo_update).
:- use_module(watch).
:- use_module(greplite).
:- use_module(xquery).
:- use_module(library(http/http_ssl_plugin)).
:- use_module(library(http/http_open)).
:- use_module(library(sgml)).
:- use_module(library(sgml_write)).

:- add_graph_dest(neo4j).
:- use_module(library(xpath)).
%:- debug(xmind_node).
%:- debug(xmind_render).
%:- debug(xmind_query).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   Process xmind search files %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

user:fshell(Format, Args, Status) :-
	format(atom(Cmd), Format, Args),
	shell(Cmd, Status).
	
:- debug(xmind_search).
	
incoming_search_folder('f:/XmindQuery/incoming').
processing_search_folder('f:/XmindQuery/processing').
outgoing_search_folder('f:/XmindQuery/outgoing').

max_age(days(1)).

delete_old_searches :-
	max_age(Max),
	get_time(T0),
	outgoing_search_folder(Outgoing),
	expand_file_name(Outgoing, Files),
	(
		member(File, Files),
		time_file(File, T),
		Dt is T0-T,
%		norm_time(Delta, Dt),
		norm_time(Max, Maxt),
		Dt > Maxt,
		delete_file(File),
	fail;true
	).
	
ignore_error(G) :-
		catch( call(G), _, true).
	
process_xmind_files :-
	ignore_error(delete_old_searches),
	incoming_search_folder(Incoming0),
	atom_concat(Incoming0, '/*.xmind', Incoming),
	processing_search_folder(Processing),
	outgoing_search_folder(Outgoing),
	replace(Processing,'/','\\',ProcessingW),
	replace(Outgoing,'/','\\',OutgoingW),
	expand_file_name(Incoming, Files),
	(
		member(File, Files),
		increment(incoming_xmind),
		absolute_file_name(File, Abs),
		file_base_name(File, Base1),
		rewrite_base_filename(Base1, Base),					% change filename based on user and node id
		atomic_list_concat([Processing, '/', Base], New),
		atomic_list_concat([Outgoing, '/', Base], NewOut),
		replace(Abs,'/','\\',AbsW),
		replace(New,'/','\\',NewW),
		fshell('cmd.exe /C copy ~w ~w',[AbsW,NewW],CopyStatus),
		must(CopyStatus=0),
		delete_file(Abs),
		increment(process_xmind_search),
		fshell('C:\\Program Files\\swipl\\bin\\swipl-win xmind.pl xmind_search ~w',[New],Status),
%		working_directory(Old,Processing),
%		ignore(fshell('curl --user test:N7287W06 -T ~w ftp://simbolika.com/httpdocs/simbolika/xmind/xmind/', [Base,Base],CurlStatus)),
%		debug(xmind_search, 'Process xmind search file ~w ftp status ~w', [File,CurlStatus]),
%		working_directory(_,Old),
%		delete_file(New),
%		fshell('cmd.exe /C del ~w\\*.*',[OutgoingW],_DelStatus),
		rename_file(New,NewOut),
		increment(process_xmind_search_complete),
	fail;true
	).

rewrite_base_filename(Base, Base1) :-
	incoming_search(Search),
	member(filename=Base, Search),
	intersection([user=User,nodeid=Id],Search,_),
	format(atom(Base1), 'search_~w_~w_~w', [User,Id,Base]), 
	debug(xmind, 'base ~w user ~w id ~w Base1 ~w', [Base,User,Id,Base1]),
	retractall(incoming_search(Search)),
	!.
rewrite_base_filename(Base,Base).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  Xmind Search Server %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_client)).
:- use_module(library(http/http_cors)).
%:- use_module(library(http/http_log)).
%:- set_setting(http:logfile, 'httplog.txt').
 

:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_mime_plugin)).
:- use_module(library(http/html_write)).

:- set_setting(http:cors, [*]).
:- multifile(get_reply/2).
:- multifile(put_reply/2).
:- multifile(post_reply/2).
:- multifile(options_reply/2).


:- dynamic(request/2).

replay(Req) :-
	request(Req, Request),
	reply1(Request).

reply(Request) :-
	\+ record_requests(true),
	http_cors:cors_enable,
	member(path(Path), Request),
	member(method(Method), Request),
	(member(search(Search), Request);Search=[]), !,
	debug([http_server], '~w ~w ~w', [Method,Path,Search]),
	once(call(request_reply, Method, Request, Path)).
	
reply(Request1) :-
	record_requests(true),
	http_cors:cors_enable,
	gensym(req, Req),
	request_data(Request1, Request),
	assert(request(Req,Request)),
	member(path(Path), Request),
	member(method(Method), Request),
	(member(search(Search), Request);Search=[]), !,
	debug([http_server], '~w:~w ~w ~w', [Req,Method,Path,Search]),
	once(call(request_reply, Method, Request, Path)).
	
reply1(Request) :-
	gensym(req, Req),
	cors_enable,
	member(path(Path), Request),
	member(method(Method), Request),
	once(call(request_reply, Method, Request, Path)).
	
server(Port,Record) :-
	assert(record_requests(Record)),
	http_server(reply, [port(Port)]).

	

:- dynamic(record_requests/1).

request_reply(Method, Request, Path) :-
	(
	    Goal =.. [Method,Request,Path],
	    Goal
	  ;
		atomic_list_concat([_|List], '/', Path),
	    Goal =.. [Method,Request,List],
	    Goal
	), !.

request_data(RequestIn, [form_data=Parts|RequestIn]) :-
	(member(method(post), RequestIn); member(method(put), RequestIn)), !,
	http_read_data(RequestIn, Parts, [form_data(mime)]), !.
request_data(RequestIn, RequestIn).

get(Request, Path) :- get_reply(Request, Path).
options(Request, Path) :- options_reply(Request, Path).

post(Request, Path) :- post_reply(Request, Path).
put(Request, Path) :- put_reply(Request, Path).

options_reply(Request, _) :-
	cors_enable_headers(Request),
	format('Access-Control-Max-Age: 3628800~n', []),
	format('Content-type: text/plain~n~n', []).
	
cors_enable_headers(Request) :-
	member(access_control_request_headers(Headers), Request),
	member(access_control_request_method(Method), Request),
	format('Access-Control-Allow-Headers: ~w~n',[Headers]), 
	format('Access-Control-Allow-Methods: ~w~n',[Method]), 
	!.
cors_enable_headers(_).


get_reply(Request, [ping|_]) :-
	debug(serv, 'serv ping ~w', [Request]),
	format('Content-type: text/html~n~nxmind ping reply~n').

get_reply(Request, [File|_]) :-
	string_to_atom(File, File1),
	exists_file(files(File1),File2),
	debug(serv, 'serve file ~w', [File2]),
	http_reply_file(File2, [cache(false),unsafe(true)], Request).

get_reply(Request, [xmind_search|_]) :-
	debug(grid, 'rest grid_data 1', []),
	(member(search(Search), Request); \+member(search(Search), Request), Search=[]),
	intersection([user=User,userid=Id,page=Page], Search, _),
	format(atom(File), 'f:/XmindQuery/outgoing/search_~w_~w_~w.xmind', [Id,User,Page]),
	(
		exists_file(File,File2),
		debug(serv, 'serve file ~w', [File2]),
		http_reply_file(File2, [cache(false),unsafe(true)], Request)
	;
		\+ exists_file(File,File2),
		format('Content-type: text/plain~n~n'),
		format('Search results pending~n', [])
	).

mime:mime_extension(xmind, application/xmind).

% double parse a mixed string/term

reparse([H|T], [H1|T1]):-
	format(atom(H0), '~w', [H]),
	catch( term_to_atom(H1,H0), _, H1=H0),
	reparse(T,T1).
reparse([],[]).
	
get_reply(Request, [XmindFile|_]) :-
	wildcard_match('*.xmind',XmindFile),
	debug(search, 'xmind cypher search 1 ~w', [Request]),
	(member(search(Search1), Request); \+member(search(Search1), Request), Search1=[]),
	Search=Search1,
	intersection([cypher=Cypher,file=Filename,styles=Styles1], Search, _),
	(var(Styles),Styles=[];nonvar(Styles)),
	term_to_atom(Styles, Styles1),		% if styles has something that won't compile the effect will be no styling
	debug(search, 'before search ~w', [cypher_xmind_search(Cypher,Styles,ResultFile1)]),
	cypher_xmind_search(Cypher,Search,Styles,ResultFile1),
	absolute_file_name(ResultFile1,ResultFile),
	debug(search, 'xmind file produced ~w', [ResultFile]),
	(
		exists_file(ResultFile),
		debug(search, 'serve file ~w', [ResultFile]),
		http_reply_file(ResultFile, [cache(false),unsafe(true)], Request),
		delete_file(ResultFile)
	;
		\+ exists_file(ResultFile),
		debug(search, 'xmind file does not exist ~w', [ResultFile]),
		format('Content-type: text/plain~n~n'),
		format('Search results pending~n', [])
	), !.
	
%% util:delete_if_exists ( filename )
%  
% delete the file if it exists, otherwise do nothing
%

delete_if_exists(File) :-
	exists_file(File),
	delete_file(File), !.
delete_if_exists(_).
	
get_reply(Request, [incoming_search|_]) :-
	debug(serv, 'incoming search ~w', [Request]),
	(member(search(Search), Request); \+member(search(Search), Request), Search=[]),
	intersection([user=User,nodeid=Nodeid,filename=File], Search, _),
	debug(serv, 'incoming search user ~w node ~w file ~w ', [User,Nodeid,File]),
	assert(incoming_search(Search)),
	
    http_read_data(Request, Parts, [form_data(mime)]),
    debug(serv, 'Parts: ~w', [Parts]),
    member(mime(Attributes, Data, []), Parts),
    debug(serv, 'Attributes: ~w', [Attributes]),
	
	format('Content-type: text/plain~n~n'),
	format('Incoming received~n', []).
	

get_reply(Request, [File1|_]) :-
	debug(serv, 'search file request ~w', [Request]),
	debug(serv, 'search file request ~w', [File1]),
	(member(search(Search), Request); \+member(search(Search), Request), Search=[]),
	format(atom(File), 'f:/XmindQuery/outgoing/~w', [File1]),
	debug(serv, 'search file ~w ~w', [File1,File]),
	(
		exists_file(File,File2),
		debug(serv, 'serve file ~w', [File2]),
		http_reply_file(File2, [cache(false),unsafe(true)], Request)
	;
		\+ exists_file(File,File2),
		format('Content-type: text/plain~n~n'),
		format('Search results pending~n', [])
	).
	

	
exists_file(A, B) :-
    absolute_file_name(A, B),
    exists_file(B).	

xmind_server :- server(57604,false).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        
user:add_document :-
               load(File),
               fedbizopps:mine_file(absolute(File), _, _).

user:add_document(Owner) :-
               load(File),
               fedbizopps:mine_file(absolute(File), element(owner,[name=Owner],[]), _).              
              

			  
user:q_document :- q_document(none), !.
user:q_document(Owner) :-
     load(File),
     add_graph_dest(neo4j),
     anal_file_type(File, Type),
     get_time(T0),
     new_node(Doc, check, [type=mine_file,filename=File,owner=Owner,file_type=Type,created=T0]),
     format('Created request to mine file ~w\n',[File]), !.
    
anal_file_type(File, unknown).
	
:- pce_global(@finder, new(finder)).

user:mine_exec :- start_exec(mine_exec), thread_send_message(mine_exec, periodic(doctool:mine_exec_main,minutes(1))).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Search Manager %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

/*

Process:


	1. Download template e
	2. Edit template e
	3. Upload template m
	
	4. Detect uploaded template m
	5. Unzip template m	
	6. load contents e
	7. convert template to search h
	8. Execute search h
	9. Format output into MM m
	10. zip results m
	11. Return MM file m

	
MATCH (:Movie { title: "The Matrix" })<-[:ACTS_IN]-(actor)-[:ACTS_IN]->(movie)
RETURN movie.title, collect(actor.name), count(*) AS count
ORDER BY count DESC 

MATCH p=((:solicitation)-[5]->(:solicitation)) RETURN p

*/
:- dynamic(styles/1).
:- dynamic(map/1).

user:qx(X) :-
	load_xml_file('./xmind/content.xml', X).
	
:- listen(file_event(_,Data), handle_file(Data)).

user:replace(In, From, To, Out) :-
	atomic_list_concat(List, From, In),
	atomic_list_concat(List, To, Out).

:- dynamic(processed_xmind/1).
	
search_fbo :-
%	debug(create_xmind),
%	debug(xmind),
%	debug(xmind_out),
		load(File),
		add_pc('Annotation'),
		add_pc('section'),
		add_pc('file'),
		handle_file(File).
		
member_def(Elem, List, Def) :-
	member(Elem, List).
member_def(Name=Def, List, Def) :-
	\+ member(Name=_, List).

lookup([Name=(Set,Def)|T], List) :-
	member_def(Name=Set, List, Def),
	lookup(T, List).
lookup([],_).

/*
Use cases
	- Research related solicitations (to each other)
2		kw(or other entry point)->sol->sol
	- Research solicitations related to keywords (solr or neo)
		kw->sol
	- Find team mates
		sol->interested_parties
		sol->kw->corporate_kw
	- Find resumes (indeed?)
		sol->kw->resume->person
	- Find solicitations based on corpex
3			corpex->kw->doc->sol
	- Competition research
2		corporations->kw->sol
2		kw->sol->award->company
3	- Budget research
	- Document analysis
1		sol->documents->sections->sentences->words

starting points:
	- keywords (profile, etc)
	- solicitation (solr, manual)
	- file (solr, manual)
	- company (solr, manual)
	
*/


test(xmind_search(1)) :-
	cypher_xmind_search('MATCH (a)-[r:`sentence`]->(b) RETURN a,r,b LIMIT 25',[],[],'test_01a.xmind').
test(xmind_search(2)) :-
	cypher_xmind_search('MATCH (a)-[r:`sentence`]->(b) RETURN a,r,b LIMIT 25',[],[],'test_01b.xmind').
test(xmind_search(3)) :-
	cypher_xmind_search('match (s:solicitation{SOLNBR:"N6274213R1303"})-[r_pc]->(n)return s,r_pc,n limit 50',[],[],'test_01c.xmind').

	
test(xmind_search(4)) :-
	cypher_xmind_search('MATCH (a)-[:`has_word`]->(b) RETURN a,b LIMIT 25',[],[],'test_02.xmind').
	
	
test(xmind_search(5)) :-
	cypher_xmind_search('MATCH (a:fbo_files)-[r:`file`]->(b:file) RETURN a,r,b LIMIT 25',[],[],'test_03.xmind').
test(xmind_search(6)) :-
	cypher_xmind_search('MATCH (a:fbo_files)-[r:`file`]->(b:file) RETURN a,r,b LIMIT 25',[],[a=[title=label],b=[title=label,notes=absolute_filename,file=absolute_filename]],'test_03a.xmind').
test(xmind_search(7)) :-
	cypher_xmind_search('MATCH (a:fbo_files)-[r_pc:`file`]->(b:file) RETURN a,r_pc,b LIMIT 25',[],[a=[title=label],b=[title=label,notes=absolute_filename,file=absolute_filename]],'test_03b.xmind').
	
% Single node
%	cypher_xmind_search('MATCH (a:file) return a LIMIT 25',[],[styles=[a=[title=label,notes=absolute_filename]]],'test_05.xmind'),
% More styling
%	cypher_xmind_search('MATCH (a:file) return a LIMIT 25',[],[styles=[a=[title='fixed title',notes=title+absolute_filename+f(x),marker=f(f(y),[a,b,c])]]],'test_05.xmind'),
%  multiple unnamed relationships?
%
	
		
cypher_xmind_search(Cypher,Search,Styles,File):-
	retractall(node_map(_,_,_,_)),
	retractall(rel_map(_,_,_,_,_)),
	lookup([title=(Title,'Search Results')],Search),
	cypher_query(Cypher, Results),
	must(member(errors=[],Results), 'Cypher error ~w', [Results]),
	neo_result_columns(Results, [First|_]),
	(
		var(File),
		gensym(axmind_, Pre),
		atom_concat(Pre,'.xmind',File)
	;
		nonvar(File)
	),
	delete_if_exists(File),										% If the file already exists, the results will be additive. May want this in some cases but not here.
	create_xmind(1, xxx, Cypher, File, Results, Styles),
	true.
	
handle_file(Data0):-
% Extracts data from an xmind mind map
	file_base_name(Data0, Data),
	format('extract: ~w\n',[Data]),
	replace(Data0, '\\', '/', Data1),
	format(atom(T1), '7z x "~w" content.xml -y >>log.txt', [Data1]),
	format(atom(T2), '7z x "~w" styles.xml -y >>log.txt', [Data1]),
	shell(T1, Status),
	shell(T2, Status2),
	create_cypher(Data1), !.
handle_file1(Data):-
	processed_xmind(Data),
	retract(processed_xmind(Data)).

create_cypher(File) :-
	retractall(temp_rel_map(_,_,_,_,_)),
	retractall(node_map(_,_,_,_)),
	retractall(rel_map(_,_,_,_,_)),
	load_xml_file('content.xml', XML),
	(
		exists_file('styles.xml'),
		load_xml_file('styles.xml', Styles),
		retractall(styles(_)),
		assert(styles(Styles))
	;
		\+ exists_file('styles.xml'),
		retractall(styles(_)),
		assert(styles(element(styles,[],[])))
	),
	retractall(map(_)),
	assert(map(XML)),
	findall(Query,
	(
		create_query(Qid, XML, query(Qtitle, String, Postfix)),
		format('Processing search ~w\n',[Qtitle]),
		format(atom(Query), 'MATCH p=(~w) RETURN p ~w;', [String,Postfix]),
		format('Query = ~w',[Query]),
		cypher_query(Query, Results),
		create_xmind(Qid, Qtitle, File, Results)
	), _),
	true.
	
:- dynamic(temp_rel_map/5).
:- dynamic(node_map/4).
:- dynamic(rel_map/5).
	
create_xmind(Qid, RootVariable, QTitle, File, List, Styles) :-
	gephi:create_mm,
	gephi:load(Workbook,File),
	gephi:get_primary_sheet(Workbook,sheet0),
%	gephi:create_sheet(Workbook, sheet0),
	gephi:add_sheet(Workbook, sheet0),
	gephi:get_root_topic(sheet0, topic0),
	replace(QTitle, '"', '\'', QTitle1),
	gephi:setTitle(topic0, QTitle1),
	findall(node_map(Qid, Id, Variable, Label,Attributes),
	(
		cypher_nodes(List, Id, Variable, Label, Attributes)
	), NodeList),
	list_to_set(NodeList, NodeSet),
	maplist(assert, NodeSet),
	length(NodeSet, Nlen),
	findall(rel_map(Qid, Name, Variable, From, To, Label),
	(
		cypher_rel(List, Name, Variable, Label, From, To, Attributes)
	), EdgeList),
	list_to_set(EdgeList, EdgeSet),
	maplist(assert, EdgeSet),
	(
		member(node_map(_, Id, Variable, Label, Attributes), NodeSet),
		debug(xmind_out,'nodes Id ~w Label ~w',[Id, Label]),
		render_node(Qid, Id, Variable, Label, [label=Label|Attributes], [styles=Styles], Result),
		call(Result),
	fail;true
	),
	length(EdgeSet, Elen),
	(
		member(rel_map(_, Name, Variable, From, To, Label), EdgeSet),
		debug(xmind_out,'relations Id ~w Label ~w From ~w To ~w',[Name, Label, From, To]),
		rel_type(Variable, RType),
		new_edge(xmind, Name, From, To, Label, [relationship=RType]),
	fail;true
	),
	% Big question is which nodes should be linked to the root
	(
		member(node_map(_, Id, RootVariable, _, _), NodeSet),		
		new_edge(xmind, _Name, topic0, Id, file),
	fail;true
	),
	debug(create_xmind,'create xmind save ~w',[File]),
	gephi:save_exec(Workbook,File).
	
rel_type(Name, 'non_pc') :-
	\+ wildcard_match('*_pc', Name).
rel_type(Name, 'pc') :-
	wildcard_match('*_pc', Name).
	
create_xmind1(List, element(sheet,[theme='xminddefaultthemeid2014'],[element(title,[],[]),element(topics,[],Nodes)])) :-
%	findall(element(topic,[id=Id,label=Label|Attributes],[element(title,[],[Label])]),
	findall(element(topic,[],[element(title,[],[Label]),element(labels,[],[element(label,[],[Label])])]),
	(
		cypher_nodes(List, Id, Label, Attributes)
	), Nodes),
	findall(element(relationship,[id=Id,label=Label,from=From,to=To|Attributes],[]),
	(
		cypher_rel(List, Id, Label, From, To, Attributes)
	), Rels),
	append(Nodes, Rels, All).
	
neo_result_columns(Results, Columns) :-
	intersection([results=[json([columns=Columns,data=_])]],Results, _).

cypher_nodes(List, Id, VariableName, Label, Attributes) :-
	intersection([results=[json([columns=Columns,data=AllData])]],List, _),
	member(json(Results1), AllData),
	nonvar(Results1),
	intersection([graph=json(Graph),row=Row], Results1, _),
	nonvar(Graph),
	intersection([nodes=Nodes,relationships=Rel],Graph, _),
	nonvar(Nodes),
	length(Nodes, NLen),
	debug(xmind_out, 'Total nodes=~w\n',[NLen]),
	member(json(NodeData), Nodes),
	intersection([id=Id,labels=[Label|_],properties=json(Attributes)],NodeData, _),
	ignore(nth1(Index, Row, json(Attributes))),				% only issue here is the only way I see is to match on properties which may not be unique
	ignore(nth1(Index, Columns, VariableName)).				% is there another way to determine which variable name matches the node
	
cypher_rel(List, Id, VariableName, Label, Start, End, Attributes) :-
	intersection([results=[json([columns=Columns,data=AllData])]],List, _),
	member(json(Results1), AllData),
	nonvar(Results1),
	intersection([graph=json(Graph),row=Row], Results1, _),
	intersection([nodes=Nodes,relationships=Rel],Graph, _),
	nonvar(Rel),
	length(Rel, NLen),
	debug(xmind_out, 'Total edges=~w\n',[NLen]),
	member(json(NodeData), Rel),
	intersection([id=Id,startNode=Start,endNode=End,type=Label,properties=json(Attributes)],NodeData, _),
	ignore(nth1(Index, Row, json(Attributes))),				% only issue here is the only way I see is to match on properties which may not be unique
	ignore(nth1(Index, Columns, VariableName)).				% is there another way to determine which variable name matches the node
	
:- use_module(default_xmind_styles).

render_node(Qid, Id, Label, Attributes, new_node(xmind, Id, Label, AASet)) :-
% find right template
	(
		rel_map(Qid, _Name, Id, _Id, Rel),
		temp_rel_map(Qid, Topic, Rel, _)
	;
		rel_map(Qid, _Name, _Id, Id, Rel),
		temp_rel_map(Qid, _Topic, Rel, Topic)
	),
	xmind_name_class(Topic, _, Label),
	xmind_notes(Topic, Notes),
	term_to_atom(Term, Notes),
	debug(xmind_render, 'render ~w ~w ~w ~w ~w', [Id,Label,Notes,Attributes,Topic]),
	findall(A1=B1,
	(
		member(A=B, Term),
		render_attribute(A,B,Attributes,A1,B1)
	), NewAttributes), 
	debug(xmind_render, 'render new attributes  ~w', [NewAttributes]),
	append(NewAttributes, Attributes, AllAttributes),
	list_to_set(AllAttributes, AASet),
	!.
render_node(Id, Label, Attributes, new_node(xmind, Id, Label, AASet)) :-
	temp_node_map(Name, Label, Topic),
	xmind_name_class(Topic, _, Label),
	xmind_notes(Topic, Notes),
	term_to_atom(Term, Notes),
	findall(A1=B1,
	(
		member(A=B, Term),
		render_attribute(A,B,Attributes,A1,B1)
	), NewAttributes), 
	debug(render,'Label ~w Term ~w Attributes ~w New ~w',[Label,Term,Attributes,NewAttributes]),
	append(NewAttributes, Attributes, AllAttributes),
	list_to_set(AllAttributes, AASet),
	!.
render_node(Qid, Id, Variable, Label, Attributes, Options, new_node(xmind, Id, Label, AASet)) :-
	debug(xmind_render, 'render node styles ~w', [Options]),
	intersection([styles=Styles],Options,_),
	intersection([Variable=Style], Styles, _),
	debug(xmind_render, 'render node found style info ~w ', [Style]),
	nonvar(Style),
	findall(A1=B1,
	(
		member(A=B, Style),
		render_attribute(A,B,Attributes,A1,B1)
	), NewAttributes), 
	debug(xmind_render, 'render new attributes  ~w', [NewAttributes]),
	append(NewAttributes, Attributes, AllAttributes),
	list_to_set(AllAttributes, AASet),
	!.
render_node(Qid, Id, _, Label, Attributes, Options, new_node(xmind, Id, Label, AASet)) :-
	debug(xmind_render, 'default render node styles ~w', [Options]),
	debug(xmind_render, 'default render ~w ~w ~w', [Id,Label,Attributes]),
	once(default_xmind_styles:default_xmind_style(Attributes, Label, InterimAttr)),
	debug(xmind_render, 'default interim attributes  ~w', [InterimAttr]),
	findall(A1=B1,
	(
		member(A=B, InterimAttr),
		render_attribute(A,B,Attributes,A1,B1)
	), NewAttributes), 
	debug(xmind_render, 'default render new attributes  ~w', [NewAttributes]),
	append(NewAttributes, Attributes, AllAttributes),
	list_to_set(AllAttributes, AASet),
	!.

	
% marker = func(text,1)
	
lookup_attr(A=V, List) :-
	downcase_atom(A,A0),
	member(A1=V, List),
	downcase_atom(A1,A0).
	
render_attribute(To,From,Attributes,To,Value) :-
	\+ compound(From),
	lookup_attr(From=Value, Attributes).
render_attribute(To,From,Attributes,To,Value) :-
	compound(From),
	From =.. [Func|Args],
	findall(Item,
	(
		member(Arg, Args),
		render_argument(Arg, Attributes, Item)
	), Items),
	X =.. [Func|Items],
	catch( call(X,Value), Error, term_to_atom(Error, Value)).
	
render_argument([H|T], Attributes, [H1|T1]) :-
	render_argument(H,Attributes,H1),
	render_argument(T,Attributes,T1).
	
render_argument([], _, []).

render_argument(Arg, Attributes, Item) :-
	compound(Arg),
	\+ is_list(Arg),
	once(render_attribute(_, Arg, Attributes, _, Item)).
	
render_argument(Arg, Attributes, Item) :-
		atomic(Arg),
		\+ is_list(Arg),
		once((
			member(Arg=Item, Attributes)
		;
			\+ member(Arg=Item, Attributes),
			Item=Arg
		)).


	
	
%default_xmind_style(_Attribs, notice, [title=format_text('~w: ~w',[label,first([subject,desc])]),link=serve_file(absolute_filename),notes=concat([subject,notes])]).	
	
create_query(Id, XML, query(SearchTitle,String,Postfix)) :-
	(
		xpath:xpath(XML, //(topic(@id=Root))/children/topics/topic(@id=QueryRoot)/children/topics/(topic(@id=Start))/'marker-refs'/'marker-ref'(@'marker-id'='symbol-question'), _),
		xpath:xpath(XML, //(topic(@id=QueryRoot)), QNode),
		xmind_title(QNode, SearchTitle)
	;
		xpath:xpath(XML, //(topic(@id=Root))/children/topics/(topic(@id=Start))/'marker-refs'/'marker-ref'(@'marker-id'='symbol-question'), _),
		SearchTitle = 'Query Results'
	),
	xpath:xpath(XML, //(topic(@id=Root)), RootTopic),
	xpath:xpath(XML, //(topic(@id=Start)), X),
	
	xmind_notes(RootTopic, Postfix),
	gensym(query, Id),
	assert(temp_rel_map(Id,RootTopic,root,X)),
	debug(xmind, 'Starting point = ~w', [X]),
	cypher_follow(Id, X, String, []).
	
find_attributes(element(topic,Attr,Sub), Attrs) :-
	Left = 'arrow-left',
	Right = 'arrow-right',
	findall(attr(ALabel,Attribute), 
	(
		xpath:xpath(element(topic,Attr,Sub), /(topic)/children/topics/topic, Top),
		xpath:xpath(Top, /(topic)/title(text), Attribute),
		xpath:xpath(Top, /(topic)/labels/label(text), ALabel),
		ignore(xpath:xpath(Top, /(topic)/'marker-refs'/'marker-ref'(@'marker-id'), Marker)),
		(
			var(Marker)
		;
			\+ var(Marker),
			Marker \= Left,
			Marker \= Right
		)
	), Attrs).
	
format_link1(Node, Topic, LinkText, _) :-
	Left = 'arrow-left',
	Right = 'arrow-right',
	xpath:xpath(Node, /(topic)/children/topics/topic, Topic),
	xpath:xpath(Topic, /(topic)/labels/label(text), Label),
	xpath:xpath(Topic, /(topic)/'marker-refs'/'marker-ref'(@'marker-id'), Marker),
	once(Marker=Left;Marker=Right),
	format_link2(Marker, _, Label, LinkText),
	debug(xmind, 'format 1 Node ~w Topic ~w LinkText ~w', [Node,Topic, LinkText]).

format_link(Qid, Node, Topic, LinkText, Blocked) :-
	Left = 'arrow-left',
	Right = 'arrow-right',
	map(Map),
	styles(Styles),
	xpath:xpath(Node, /(topic(@id)), Id),
	(
		xpath:xpath(Map, //(relationships)/relationship(@end1=Id,@end2=OtherEnd), Rel),
		xpath:xpath(Rel, /(relationship)/title(text), Label),
		ignore(xpath:xpath(Rel, /(relationship(@'style-id'=Sid)), _)),
		Dir = right,
		format_link2(Dir, Sid, Label, LinkText),
		add_non_pc(Label,Id,OtherEnd)
	;
		xpath:xpath(Map, //(relationships)/relationship(@end2=Id,@end1=OtherEnd), Rel),
		xpath:xpath(Rel, /(relationship)/title(text), Label),
		ignore(xpath:xpath(Rel, /(relationship(@'style-id'=Sid)), _)),
		Dir = left,
		format_link2(Dir, Sid, Label, LinkText),
		add_non_pc(Label,Id,OtherEnd)
	;
		xpath:xpath(Node, /(topic)/children/topics/topic(@id=OtherEnd), SubTopic),
		xpath:xpath(SubTopic, /(topic)/labels/label(text), Rel),
		xpath:xpath(SubTopic, /(topic)/'marker-refs'/'marker-ref'(@'marker-id'), Marker),
		once((Marker = Left;Marker = Right)),
		format(atom(LinkText), '-[:~w]->', [Rel])
	),
	xpath:xpath(Map, //(topic(@id=OtherEnd)), Topic),
	\+ member(OtherEnd, Blocked),
	assert(temp_rel_map(Qid, Node,Rel,Topic)),
	true.
	
	
topic_relations(Topic, From, To, Relation) :-
	true.

id_topic(Id, Topic) :-
	map(Map),
	xpath:xpath(Map, //(topic(@id=Id)), Topic).
	
	
topic_id(Topic, Id) :-
	xpath:xpath(Topic, /(topic(@id=Id)), _).
	

xmind_name_class(Topic, Name, Class) :-
	xmind_title(Topic, Title),
	atomic_list_concat([Name,Class|_], ':', Title).
	
xmind_notes(Topic, Notes) :-
		xpath:xpath(Topic, /(topic)/notes/plain(text), Notes).

xmind_title(Topic, Title) :-
		xpath:xpath(Topic, /(topic)/title(text), Title).
		

		
xmind_label(Topic, Label) :-
		xpath:xpath(Topic, /(topic)/labels/label(text), Label).

xmind_marker(Topic, Marker) :-
		xpath:xpath(Topic, /(topic)/'marker-refs'/'marker-ref'(@'marker-id'), Marker).

	
cypher_follow(Qid, element(topic,Attr,Sub), Out, Blocked1) :-
	xmind_name_class(element(topic,Attr,Sub), TName, TClass),
	assert(temp_node_map(TName,TClass,element(topic,Attr,Sub))),
	once(xpath:xpath(element(topic,Attr,Sub), //(title(text)), Name)),
	intersection([id=Id], Attr, _),
	debug(xmind, 'Follow.... = ~w ~w ', [Id,Attr,Blocked1]),
	append([Id], Blocked1, Blocked),
	find_attributes(element(topic,Attr,Sub), Attrs),
	(
		format_link(Qid, element(topic,Attr,Sub), Topic, LinkText, Blocked),
		once((cypher_follow(Qid, Topic, Out2, Blocked),format(atom(Out1),'~w ~w',[LinkText,Out2]);Out1=''))
	;
		Out1 = ''
	), 
	!,
	(
		Attrs \= [],
		format_a_list(Attrs, AttrsStr),
		format(atom(Out), '(~w { ~w }) ~w', [Name,AttrsStr,Out1])
	;
		Attrs = [],
		format(atom(Out), '(~w) ~w', [Name,Out1])
	).
	
format_link2(left, Sid, Label, LinkText) :-
		var(Sid),
		format(atom(LinkText), '<-[:~w]-', [Label]).
format_link2(right, Sid, Label, LinkText) :-
		var(Sid),
		format(atom(LinkText), '-[:~w]->', [Label]).
format_link2(_, Sid, Label, LinkText) :-
		left_arrow(Sid), \+ right_arrow(Sid),
		format(atom(LinkText), '<-[:~w]-', [Label]).
format_link2(_, Sid, Label, LinkText) :-
		right_arrow(Sid), \+ left_arrow(Sid),
		format(atom(LinkText), '-[:~w]->', [Label]).
format_link2(_, Sid, Label, LinkText) :-
		\+ right_arrow(Sid), \+ left_arrow(Sid),
		format(atom(LinkText), '-[:~w]-', [Label]).
format_link2(_, Sid, Label, LinkText) :-
		right_arrow(Sid), left_arrow(Sid),
		format(atom(LinkText), '<-[:~w]->', [Label]).
		
right_arrow(Sid) :-
	styles(S),
	xpath:xpath(S, //(style(@id=Sid)), Style),
	xpath:xpath(Style, /(style)/'relationship-properties'(@'arrow-end-class'=St), _),
	is_arrow(St).
left_arrow(Sid) :-
	styles(S),
	xpath:xpath(S, //(style(@id=Sid)), Style),
	xpath:xpath(Style, /(style)/'relationship-properties'(@'arrow-begin-class'=St), _),
	is_arrow(St).
	
	
is_arrow(Style) :-
	member(Style, ['org.xmind.arrowShape.triangle','org.xmind.arrowShape.spearhead','org.xmind.arrowShape.normal']).
	
format_a_list([attr(A,V)|T],Str) :-
	format(atom(A1), '~w: "~w"', [A,V]),
	format_a_list1(T, Str1),
	atomic_concat(A1, Str1, Str).
	
format_a_list1([attr(A,V)|T],Str) :-
	format(atom(A1), ', ~w: "~w"', [A,V]),
	format_a_list1(T, Str1),
	atomic_concat(A1, Str1, Str).

format_a_list([],'').
format_a_list1([],'').

user:norm_space(In, Out) :-
	\+ is_list(In),
	atom_chars(In, Chars),
	norm_space(Chars,NormChars),
	atom_chars(Out,NormChars).

first_non_white([H|T], T1) :-
	char_type(H,white),
	first_non_white(T,T1).
first_non_white([H|T], [H|T]) :-
	\+ char_type(H,white).
	
user:norm_space([H|T],[H|T2]) :-
	char_type(H,white),
	first_non_white(T,T1),
	norm_space(T1,T2).
user:norm_space([H|T],[H|T1]) :-
	\+ char_type(H,white),
	norm_space(T,T1).
user:norm_space([],[]).


explicit_rel(A,B,Label) :-
	map(Map),
	xpath:xpath(Map, //(relationships)/relationship(@end1=Id,@end2=OtherEnd), Rel),
	Id \= OtherEnd,
	xmind_class(Id,A),
	xmind_class(OtherEnd,B),
	xpath:xpath(Rel, /(relationship)/title(text), Label).
	
xmind_search :-	
	debug(xmind),
	current_prolog_flag(argv, Args),
	format('xmind search arg ~w\n',[Args]),
	Args = 	[xmind_search,File|_],
	exists_file(File),
	file_directory_name(File,Dir),
	working_directory(_,Dir),
	file_base_name(File,Base),
	format('xmind search dir ~w base ~w\n',[Dir,Base]),
	handle_file(Base),
%	delete_file('create_mm.py'),
%	delete_file('content.xml'),
	halt,
	true.
run :-
	\+ current_prolog_flag(argv, [xmind_search,File|_]),
	current_prolog_flag(argv, Args),
	format('no search: ~w\n',[Args]).
:- working_directory(Dir,Dir), format('Starting in ~w\n',[Dir]).
:- xmind_search.
%:- halt.

