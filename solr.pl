
:- module(solr, []).

:- use_module(library(http/http_ssl_plugin)).
:- use_module(library(http/http_open)).
:- use_module(library(http/http_client)).
:- use_module(library(sgml)).
:- use_module(library(sgml_write)).
:- use_module(library(xpath)).
:- use_module(greplite).
:- use_module(util).
:- use_module(library(uri)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  Solr Search Server %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_client)).
:- use_module(library(http/http_cors)).
 

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



get_reply(Request, [File|_]) :-
% for now only serve robots.txt
	string_to_atom(File, File1),
	wildcard_match('*robots*', File1),
	exists_file(files(File1),File2),
	debug(serv, 'serve file (~w)', [File2]),
	http_reply_file(File2, [cache(false),unsafe(true)], Request).

get_reply(Request, [open|Rest]) :-
	debug(serv, 'attempt serve file ~w', [[F|Rest]]),
	(member(search(Search), Request); \+member(search(Search), Request), Search=[]),
	intersection([file=Filename], Search, _),
	debug(serv, 'attempt serve abs file ~w', [File1A]),
%	exists_file(File1A),
	debug(serv, 'serve file ~w', [File1A]),
	http_reply_file(Filename, [cache(false),unsafe(true)], Request).
	
get_reply(Request, [fedbiz,files|Rest]) :- 
	debug(serv, 'attempt serve FBO file ~w', [[F|Rest]]),
	(member(search(Search), Request); \+member(search(Search), Request), Search=[]),
	member(cmd=open, Search),
	atomic_list_concat(['./files/'|Rest], '/', File),
	string_to_atom(File, File1a),
	absolute_file_name(File1a,File1A),
	debug(serv, 'attempt serve abs file ~w', [File1A]),
	exists_file(File1A),
	debug(serv, 'serve file ~w', [File1A]),
	http_reply_file(File1A, [cache(false),unsafe(true)], Request).
	
get_reply(Request, [F|Rest]) :- 
	debug(serv, 'attempt serve resource ~w', [[F|Rest]]),
	atomic_list_concat([F|Rest], '/', File),
	string_to_atom(File, File1),
	atom_concat('./resources/', File1, File1a),
	absolute_file_name(File1a,File1A),
	debug(serv, 'attempt serve resource ~w', [File1A]),
	exists_file(File1A),
	debug(serv, 'serve file ~w', [File1A]),
	http_reply_file(File1A, [cache(false),unsafe(true)], Request).
	
get_reply(Request, [analyze|_]) :-
	debug(serv, 'analyze file ~w', [[F|Rest]]),
	
/*

	Inputs
		cypher - Cypher template
		name=value - Template parameters
		name=value - Styling information

*/

	(member(search(Search), Request); \+member(search(Search), Request), Search=[]),

	intersection([cypher_template=Cpt1],Search,_),
	replace_list(Search, Cpt1, Cypher),
	absolute_file_name('./neoviz/neoviz.html',File1A),
	absolute_file_name('./neoviz/neoviz_template.html',Template),
	rewrite_file(Template, [cypher=Cypher|Search], File1A),
	debug(serv, 'attempt serve abs file ~w', [File1A]),
	exists_file(File1A),
	debug(serv, 'serve file ~w', [File1A]),
	http_reply_file(File1A, [cache(false),unsafe(true)], Request).
	
rewrite_file(In, Change, Out) :-
	read_file_to_codes(In, Codes, []),
	atom_codes(Atom, Codes),
	replace_list(Change, Atom, Atom1),
	open(Out, write, Wr, []),
	format(Wr, '~w', [Atom1]),
	close(Wr).
	
replace_list([Name=Value|T], AtomIn, AtomOut) :-
	format(atom(From), ':~w:', [Name]),
	replace(AtomIn, From, Value, AtomIn1),
	replace_list(T, AtomIn1, AtomOut).
replace_list([], Atom, Atom).
	
format_solr_link(File, Path, Text, Result) :-
	base_url(sss,Base),
	\+ wildcard_match('*[?]*',Path),
	format(atom(Result), '<a href="~w~w?file=~w" >~w</a>', [Base,Path,File,Text]).
format_solr_link(File, Path, Text, Result) :-
	base_url(sss,Base),
	wildcard_match('*[?]*',Path),
	format(atom(Result), '<a href="~w~w&file=~w" >~w</a>', [Base,Path,File,Text]).
	
file_solicitation(File, Solicitation) :-
	absolute_file_name(File, Abs),
	atomic_list_concat(DirList, '/', Abs),
	reverse(DirList, [_,Solicitation1|_]),
	upcase_atom(Solicitation1, Solicitation).
	
member_default(Term, List, Default) :-
	member(Term, List), !.
member_default(_=Default, _, Default).

get_reply(Request, [ping|_]) :-
	debug(serv, 'serv ping ~w', [Request]),
	format('Content-type: text/html~n~nsearch-links ping reply~n').


get_reply(Request, [get_links|_]) :-
	debug(serv, 'serv get_links ~w', [Request]),
	(member(search(Search), Request); \+member(search(Search), Request), Search=[]),
	intersection([solnbr=Solnbr1], Search, _),
	(
		nonvar(Solnbr1),
		replace(Solnbr1, ' ', '', Solnbr),
		select(solnbr=_, Search, Search1),
		append(Search1, [solnbr=Solnbr], Search2)
	;
		var(Solnbr1),
		Search2=Search
	),
	debug(serv, 'serv solnbr ~w ~w', [Search2, Solnbr]),
	format('Content-type: text/html~n~n'),
	format('<html>\n', []),
	format('<body>\n', [Width]),
	format('<table border="1">\n', [Width]),
	format('<tr>', []),
	(
		action_link(_, Search2, ActLink),
		debug(serv, 'action link ~w ',[ActLink]),
		format('<td>~w</td>',[ActLink]),
	fail;true),
	format('</tr></table>', []),
	format('</body></html>\n', []).
	

clean_parameters([H|T], [H1|T1]) :-
	clean_parameter(H,H1),
	clean_parameters(T,T1).
clean_parameters([], []).

clean_parameter(solnbr=Sol,solnbr=Sol1) :-
	replace(Sol,' ','',Sol1), !.
clean_parameter(H,H).
	
	
get_reply(Request, [solr_select|_]) :-
	debug(serv, 'serv solr_select ~w', [Request]),
	(member(search(Search1), Request); \+member(search(Search1), Request), Search1=[]),
	clean_parameters(Search1, Search),
	intersection([q=Query], Search, _),
	base_url(solr,Base),
	fhttp_get('~w/solr/select?q=~w&wt=xml', [Base,Query], Reply, []),
	debug(serv, 'solr results ~w', [Reply]),
	lxs(Reply,XML),
	member_default(width=Width, Search, 800),
	debug(serv, 'solr XML ~w', [XML]),
	format('Content-type: text/html~n~n'),
	format('<html>\n', []),
	format('<body>\n<table border="1">\n', [Width]),
	base_url(neoviz,Neoviz),
	base_url(xmind,Xmind),
	format('<tr>', []),
	(
		action_link(_, [keywords=Query], ActLink),
		format(' ~w ',[ActLink]),
	fail;true),
	format('</tr>\n', []),
	findall(Solicitation,
	(
		xpath:xpath(XML, //(doc), Doc),
		xpath:xpath(Doc, /doc/(str(@name=id,text)), File),
		xpath:xpath(Doc, /doc/(arr(@name=title))/str(text), Title),
		file_solicitation(File, Solicitation)
		
	), Solicitations),
	(
		member(Solicitation, Solicitations),
		format('<tr><td>Solicitation: <b>~w</b></td><td>\n',[Solicitation]),
		debug(serv, 'serv solicitation ~w', [Solicitation]),
		(
			action_link(_, [solnbr=Solicitation], ActLink),
			format(' ~w ',[ActLink]),
		fail;true),
		format('</td></tr>\n',[]),
		xpath:xpath(XML, //(doc), Doc),
		xpath:xpath(Doc, /doc/(str(@name=id,text)), File),
		xpath:xpath(Doc, /doc/(arr(@name=title))/str(text), Title),
		ignore(xpath:xpath(Doc, /doc/(arr(@name=content))/str(text), Content)),
		debug(serv, 'serv solr_select title ~w', [Title]),
		format('<tr><td>~w</td><td>',[Title]),
		(
			action_link(open, [file=File], ActLink),
			format(' ~w ',[ActLink]),
		fail;true
		),
		format('</td><td>',[Title,D1,D2,D3]),
		(
			action_link(analyze, [file=File], ActLink),
			format(' ~w ',[ActLink]),
		fail;true
		),
		format('</td><td>',[Title,D1,D2,D3]),
		(
			action_link(mind_map, [file=File], ActLink),
			format(' ~w ',[ActLink]),
		fail;true
		),
		format('</td></tr>',[]),
		format('<tr><td>~w</td></tr>', [Content]),
	fail;true),
	format('</table></body>\n', []),
	format('</html>\n', []),
	true.
	
get_reply(Request, [_|_]) :-
	debug(serv, 'default action ~w', [Request]),
	format('Content-type: text/html~n~nPath not recognized~n').
	
% gdb_search(starting_type, name, '', search, parameters)

action_link(Action, Parameters, Link) :-
	gdb_search1(Action, Style, Name, Title, Cypher, Param),
	action_url(Action, URL, Path),
	construct_arguments(Param, [base=URL,path=Path|Parameters], Arguments),
	debug(serv, 'construct args ~w ~w', [Parameters,Arguments]),
	format(atom(FullLink1), Cypher, Arguments),
	replace(FullLink1, '"', '&quot;', FullLink),
	format(atom(StyleData), 'style=~w', [Style]),
	format(atom(Link), '<a target="_top" href="~w&~w">~w ~w</a>', [FullLink,StyleData,Title,Action]).


gdb_search1(Action, Style, Name, Title, Cypher, Param) :-
	gdb_search(ActionList, Name, Title, Cypher, Param),
	is_list(ActionList),
	member(Action-Style, ActionList).
	
gdb_search1(Action, '', Name, Title, Cypher, Param) :-
	gdb_search(Action, Name, Title, Cypher, Param),
	\+ is_list(Action).
	
construct_arguments([H|T], Args, [Value|T1]) :-
	member(H=Value, Args),
	construct_arguments(T, Args, T1).
construct_arguments([], _, []).
	
action_server(open, sss).
action_server(analyze, neoviz).
action_server(mind_map, xmind).
action_server(graph, neoviz).
action_server(map, xmind).
	
action_url(Action, Base, Path) :-
	action_server(Action, Server),
	base_url(Server, Base, Options),
	intersection([path=Path], Options, _).

gdb_search(open, open_file, 'Open', '~w/open?file=~w', [base,absolute_filename]).

%gdb_search([map-[], graph-[]], generic_sol_relations, 'Test', 
%	'~w~w?cypher=match (s:solicitation)-[r_pc]->(n:notice) return s,r_pc,n limit 50', [base,path,solnbr]).

	
gdb_search(
	[
		map-[s=[title=solnbr],n=[title=label,notes=desc]], 
		graph-[curvedEdges=false,initialScale=0.5]
	], generic_sol_relations, 'Solicitation', 
	'~w~w?cypher=match (s:solicitation{SOLNBR:&quot;~w&quot;})-[r_pc]->(n)return s,r_pc,n limit 50', [base,path,solnbr]).

gdb_search(graph, opportunity_research, 
	'Opportunity', '~w~w?cypher=match (k:keyword {w: "~w"})-[r:used_in {type: opportunity"}]->(f:file)->[r3]->(s:solicitation) return k,r,r3,s limit 50', [base,path,keywords]).
	
gdb_search(graph, resumes, 'Candidate', '~w~w?cypher=match (s:solicitation {SOLNBR: "~w"})-[r]->(kw:keyword)-[r1]->(w)-[r2]->(res:resume) return s,r,r1,res limit 50', [base,path,solnbr]).

gdb_search(graph, resumes, 'Keyword candidate', '~w~w?cypher=match (kw:w {text: "~w"})-[r]->(res:resume) return kw,r,res limit 50', [base,path,keywords]).

gdb_search(graph, resumes, 'Document/skills', '~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,file]).

gdb_search(graph, document, 'Document graph', '~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,file,location]).

gdb_search(map, mm_document, 'Mind Map', '~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,file,location]).

gdb_search(graph, keyword_document_analysis, 'Keyword document analysis', 
	'~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,keywords,location]).

gdb_search(map, mm_research, 'Mind Map Research', 
	'~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,keywords,location]).
	
gdb_search(graph, partner_research, 'Partner', 
	'~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,solnbr]).
	
gdb_search(graph, keyword_partner_research, 'Keyword Partner', 
	'~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,keywords]).
	
gdb_search(graph, competition_research, 'Competition', 
	'~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,solnbr]).
	
gdb_search(graph, keyword_competition_research, 'Keyword competition', 
	'~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,keywords]).
	
gdb_search(sbir, 'Analyze SBIR', 
'~w~w?cypher=match (n:solicitation{SOLNBR:&quot;~w&quot;})-[r]->(n)return s,r,n limit 50', [base,path,solnbr]).


user:lxs(String, XML) :-
	ground(String),
	new_memory_file(Mem),
	open_memory_file(Mem, write, WStream),
	write(WStream, String),
	close(WStream),
	open_memory_file(Mem, read, RStream),
	load_xml_file(RStream, XML),
	free_memory_file(Mem).
user:lxs(String, XML) :-
	\+ ground(String),
	new_memory_file(Mem),
	open_memory_file(Mem, write, WStream),
	xml_write(WStream, XML, [header(false)]),
	close(WStream),
	memory_file_to_atom(Mem, String),
	free_memory_file(Mem).
	
:- debug(serv).

	
exists_file(A, B) :-
    absolute_file_name(A, B),
    exists_file(B).	

solr_server :- server(57602,false).

base_url(Function, URL) :-
	base_url(Function, URL, _).
base_url(sss,'http://search-links.simbolika.com',[]).
base_url(solr,'http://fbosearch.simbolika.com',[]).
base_url(neoviz,'http://gv.simbolika.com',[path='/index.html']).
base_url(xmind,'http://xmind.simbolika.com',[path='/results.xmind']).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

/*
Solr commands


*/

erase_index :-
	base_url(solr, Base),
	fhttp_get('~w/solr/update?stream.body=<delete><query>*:*</query></delete>', [Base], Reply, []).
commit :-
	base_url(solr, Base),
	fhttp_get('~w/solr/update?stream.body=<commit/>', [Base], Reply, []).

post(File) :-
% uses curl - not working
		solr_base_url(Base),
		gensym(solr, Id),
		File = '-F "myfile=@example/exampledocs/solr-word.pdf"',
		fshell('~w/solr/techproducts/update/extract?literal.id=~w&commit=true ~w', [Id,Base,File], CurlStatus).


create_collection(Name) :-
	solr_base_url(Base),
	fhttp_get('~w/solr/admin/collections?action=CREATE&name=~w', [Base,Name], Reply, []),
	format('Created collection ~w\nReply = ~w',[Name,Reply]).
	
fhttp_get(Format, Args, Reply, Options) :-
	format(atom(URL), Format, Args),
	http_get(URL, Reply, Options).
	
/*
java -Dtype=application/pdf "Durl=http://localhost:8983/solr/collection1/update/extract?literal.id=xxx,commit=true -jar post.jar fbo_synopsis.pdf"

*/

replace(In, From, To, Out) :-
	atomic_list_concat(List, From, In),
	atomic_list_concat(List, To, Out).
	
fshell(Format, Args, Status) :-
	format(atom(Text), Format, Args),
	shell(Text, Status).

user:indexer :-
	thread_create(index_files, _, [alias(indexer)]).
	
user:index_files :-
	get_time(T),
	greplite:walk_files([solr:index_file], ['*.*'], ['*.pdftext', 'info.txt','*annie*.*','*.ignore','*.pl'], ['./Files'], Hits, [output=escape]),
	get_time(T1),
	Delta is T1-T,
	length(Hits, Total),
	format('Number of hits=~w time = ~w\n',[Total,Delta]).	

index_file(File) :- index_file(File,_,_).

index_file(File, _, _) :-
	base_url(solr,Base),
	absolute_file_name(File,Abs1),
	replace(Abs1, '/', '%2F', Abs1a),
	replace(Abs1a, ':', '%3A', Abs1b),
	replace(Abs1b, ' ', '%20', Abs),
	atomic_list_concat(List, '/', Abs1),
	reverse(List,[F,Sol|_]),
	upcase_atom(Sol, SolU),
	atomic_list_concat([Sol, '_', File], Sol1),
	gensym(Sol1,Id),
	debug(index_files, 'index ~w  ~w', [Abs,File]),
	format(atom(Params), 'literal.SOLNBR_S=~w&', [SolU]),
%	Params = '',
	fshell('java -Durl=http://localhost:8983/solr/collection1/update/extract?~wliteral.id=~w&commit=true&resource.name=~w -jar f:\\post.jar ~w"',[Params,Abs,Abs,File],Status),
	debug(indexer, 'index result ~w', [Status]),
%	must(Status=0,'Post.jar failed to index ~w',[File]),
	debug(index_files, 'index complete status ~w file ~w ', [Status,File]).
	
index_xml_file(File, In, _) :-
	intersection([id=Id,literals=Lit], In, _),
	uri_normalized_iri(Lit, Encoded),
	base_url(solr,Base),
	absolute_file_name(File,Abs1),
	replace(Abs1, '/', '%2F', Abs1a),
	replace(Abs1a, ':', '%3A', Abs1b),
	replace(Abs1b, ' ', '%20', Abs),
	atomic_list_concat(List, '/', Abs1),
	file_base_name(Abs1, File0),
	debug(index_files, 'index ~w  ~w', [Abs,File]),
	working_directory(Old,'./solr_xml'),
	base_url(solr,Base),
	fshell('java -Durl=~w/solr/collection1/update/extract?literal.id=~w~w -jar f:\\post.jar ~w"',[Base,Id,Encoded,File0],Status),
	working_directory(_,Old),
%	must(Status=0,'Post.jar failed to index ~w',[File]),
	format(' ~w ',[Status]),
	debug(index_files, 'index complete status ~w file ~w ', [Status,File]).
	
% &numShards= number &replicationFactor= number &maxShardsPerNode= number &createNodeSet= nodelist &collection.configName= configname