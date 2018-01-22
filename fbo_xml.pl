
/*
   
FedBizOpps

	- Initializes graph database from FedBizOpps XML data file
		- Solicitation
		- NAICS
		
solicitations -> Solicitation -> Notice -> Attachment

1) Structure defined - 10
2) Structure populated - 12
3) Attachments - 15
4) Data mined - 18
5) Front end
	- Xmind
	- Search form
	
	
	
Executives:

	- FBO Update Execute
	- Download Exec
	- File catalog exec
	- GATE Exec
	
*/

:- module(fedbizopps,[]).


:- dynamic(user:home_dir/1).
:- working_directory(Dir,Dir), assert(user:home_dir(Dir)).
user:abs_file(In,Out) :-
	user:home_dir(Dir),
	atom_codes(In, [_,_|T]),
	atom_codes(In1, T),
	atom_concat(Dir,In1,Out),
	log_messageF(abs_file_xlate(In,Out)).



:- use_module(alchemy).
:- use_module(graph_lib).
:- use_module(watch).
:- use_module(fbo_update).
:- use_module(greplite).
:- use_module(xquery).
:- use_module(library(http/http_ssl_plugin)).
:- use_module(library(http/http_open)).
:- use_module(library(sgml)).
:- use_module(library(sgml_write)).
%:- use_module(wordnet).
:- use_module(doctool).
:- use_module(util).
:- use_module(solr).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% FBO Update Executive %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

/*

The FUE retrieves daily FBO updates and stores them in the database.


Processing:

	- Define oldest update desired
	- Get updates starting with today's date moving backwards to the earliest desired date
	- Every day get the latest update
	- Store update in gdb and on file
	- Run through gate*

*/

baseline_date(date(2014,12,7)).

:- dynamic(fbo_update/2).
fue_delay(60).

get_latest_update :-
% Up to date
	get_time(T),
	date(T,Date),
	update(Date).
get_latest_update :-
% Not up to date
	get_time(T),
	date(T,Date),
	\+ fbo_update(Date,_),
	process_fbo_updates(Date).
	
process_fbo_updates(Date) :-
	baseline_date(Start),
	delta_days(Start,Date,Days),
	numlist(1, Days, List),
	(
		member(Day, Days),
		add_days(Start, Day, Date1),
		\+ fbo_update(Date1, _),
		process_fbo_update(Date1),
	fail;true
	).
	
process_fbo_update(Date) :-
	fbo_update_url(Date, URL),
	http_get(URL, Reply, []),
	load_fbo_xml_update(Reply, XML),
	process_fbo_xml_update(XML),
	assert(fbo_update(Date1,XML)).
	
save(fbo_updates).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Graph DB Tool %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


user:cert_verify(_SSL, _ProblemCert, _AllCerts, _FirstCert, _Error) :-
		true.
%        format('Accepting certificate~n', []).

notices(['PRESOL','SRCSGT','COMBINE','AMDCSS','MOD','AWARD','JA','ITB','FAIROPP','FSTD','SNOTE']).
links([]).

user:load_max_id :-
		fail_error( fcypher_query('MATCH (n) RETURN max(n.id) limit 5', [], row([Max|_])) ),
		number(Max),
		flag(import_id, _, Max+1).
user:load_max_id.


:- dynamic(discrepency/1).

test_fbo_read :-
	fbo_read__sequential(test_fbo_read).

get_fbo_full(File) :-
% Retrieve the full xml file
	todays_date(date(Y,M,D)),
	format(atom(File), './fbofullxml/fbofullxml_~w~w~w.xml', [Y,M,D]),
	\+ exists_file(File),
	curl(get, 'ftp://ftp.fbo.gov/datagov/FBOFullXML.xml', File, []).
get_fbo_full(File) :-
% Retrieve the full xml file
	todays_date(date(Y,M,D)),
	format(atom(File), './fbofullxml/fbofullxml_~w~w~w.xml', [Y,M,D]),
	exists_file(File).
	
user:curl(get, URL, OutFile, Options) :-
	fshell('curl ~w --OUTPUT ~w', [URL,OutFile], Status),
	must(Status=0,'Curl error ~w ~w',[URL,Status]).

	
user:check_missing_notices :-
	retractall(discrepency(_)),
	get_fbo_full(File),
	fbo_read__sequential(File,check_missing_notices),
	tell('discrepency.pl'),
	listing(discrepency),
	told.
	
%%	fbo_solr
%
% Read the latest Full FBO xml file and translate it into solr format
%	
	
user:fbo_solr :-
	get_fbo_full(File),
	file_base_name(File, Base),
	catch( fbo_read__sequential(File,write_solr), Error, format('read fbo fatal error ~w\n',[Error])),
%	solr:index_xml_file(XMLFile,_,_),
	true.
	
write_solr(Notice, element(Node,_,Sub)) :-
	gensym(solr_, SolrFile),
	format(atom(File), './solr_xml/~w.xml', [SolrFile]),
	open(File, write, Wr, []),
	format(Wr,'<add>\n',[]),
	Include=[notice_type,date_s,agency_s,zip_s,class_cod_s,naics_s,subject_s,solnbr_s,respdate_s,setaside_s],
	xpath:xpath(element(Node,_,Sub), /(Notice)/'SOLNBR'(text), SOLNBR),
	xpath:xpath(element(Node,_,Sub), /(Notice)/'DATE'(text), DATE),
	atomic_list_concat([SOLNBR,'-',Notice,'-',DATE], Id),
		findall(element(field, [name=SName], [Value]),
		(
			member(element(Name, _, [Value|_]), Sub),
			downcase_atom(Name, DName),
			atom_concat(DName, '_s', SName)
		), Fields),
		findall(Txt,
		(
			member(element(field, [name=SName], [Value|_]), Fields),
			member(SName, Include),
			format(atom(Txt), '&literal.~w=~w', [SName,Value])
		), Arguments),
		atomic_list_concat(Arguments, Args),
		lxs(Str, element(doc,[],[element(field,[name=id],[Id]),element(field,[name=notice_type],[Notice])|Fields])),
		write(Wr, Str),
		write(Wr, '<commit/></add>'),
		close(Wr),
		solr:index_xml_file(File,[id=Id,literals=Args],_),
		delete_file(File).


/*
  <field name="id">SPE7M815Q0425-COMBINE-02082015</field>
  <field name="notice_type">COMBINE</field>
  <field name="date_s">02082015</field>
  <field name="agency_s">Defense Logistics Agency</field>
  <field name="location_s">DLA Land and Maritime - BSM</field>
  <field name="zip_s">43218-3990</field>
  <field name="classcod_s">61</field>
  <field name="naics_s">331318</field>
  <field name="offadd_s">331318</field>
  <field name="subject_s">61--CABLE,POWER,ELECTRI</field>
  <field name="solnbr_s">SPE7M815Q0425</field>
  <field name="respdate_s">02192015</field>
  <field name="archdate_s">03212015</field>
  <field name="setaside_s">Total Small Business</field>


*/
		
fbo_read__sequential(File,Goal) :-
	notices(Notices),
	open(File, read, Str, []),
	read_line_to_chars(Str, Txt1),
	read_line_to_chars(Str, Txt2),
	repeat,
	read_line_to_chars(Str, Txt),
	wildcard_match('*<*>*', Txt),
	once(extract_text(Txt, '<', '>', Extract)),
	\+ wildcard_match('*xml*', Extract),
	member(Extract, Notices),
	format(atom(End), '*</~w>*',[Extract]),
	read_node_until(Str, End, Lines),
	flatten([Txt|Lines], Lines1),
	atomic_list_concat(Lines1, Text),
	lxs(Text, [XML|_]),
	catch( call(Goal,Extract,XML), Error, format('read fbo callback error ~w\n',[Error])),
	at_end_of_stream(Str).
	
test_fbo_read(Notice, XML) :-
	format('found ~w\n',[Notice]).
	

check_missing_notices(Notice, XML) :-
	xpath:xpath(XML, /(Notice)/'SOLNBR'(text), SOLNBR),
	xpath:xpath(XML, /(Notice)/'DATE'(text), DATE),
%	downcase_atom(Notice, Notice1),
%	P =.. [Notice1,solnbr=SOLNBR,date=DATE],
%	nq(Id,P),
	once(fcypher_query('match (n:~w {solnbr: "~w", date: "~w"}) return id(n),count(n)', [Notice,SOLNBR,DATE], row([Id,Count]))),
	format('found sol notice ~w solnbr ~w date ~w id ~w count ~w\n',[Notice,SOLNBR,DATE,Id,Count]),
	(
		Count > 1,
		assert(discrepency([duplicate,Notice,SOLNBR,DATE,Count])),
		increment(found_duplicate),
		log_messageF(warning('Detected duplicates, delete all but one',SOLNBR,DATE,Count)),
		findall(Idx, fcypher_query('match (n:~w {solnbr: "~w", date: "~w"}) return id(n)', [Notice,SOLNBR,DATE], row([Idx])), [_|Dups]),
		(
			member(Idx, Dups),
			gephi:del_node(mark(Idx)),
		fail;true
		)
	;
		Count = 1
	),
	!.
check_missing_notices(Notice, XML) :-
	XML = element(_,_,SubE),
	xpath:xpath(XML, /(Notice)/'SOLNBR'(text), SOLNBR),
	xpath:xpath(XML, /(Notice)/'DATE'(text), DATE),
	format('missing sol notice ~w solnbr ~w date ~w\n',[Notice,SOLNBR,DATE]),
	assert(discrepency([missing,Notice,SOLNBR,DATE])),
	debug(fbo_update, '~w Processing notice ~w for ~w\n',[Date,Node0,Sol]),
	increment(add_new_solicitation_via_fullxml),
	new_node(Sol, solicitation, ['SOLNBR'=Sol]),
	findall(DownName=Value, (member(element(Attr000,_,[Value]), SubE), downcase_atom(Attr000,DownName)), Attrs),
	new_node(NewNotice, [Notice,notice], Attrs),
	get_time(T0),
	new_node(Check, check, [type=file,status=pending,solnbr=Sol,created=T0]),
	log_messageF(info(created_notice,id(NewNotice))),
	new_edge(Rel, Sol, NewNotice, notice),
	increment_stat(new_notice_created),
	!.
check_missing_notices(_Notice, _XML) :-
	format('All failed ~w ~w',[Notice,XML]).

read_line_to_chars(Str, Atom) :-
	read_line_to_codes(Str, Codes),
	atom_codes(Atom, Codes).
	
extract_text(Str, Start, End, Extract) :-
	atomic_list_concat([_,Second|_], Start, Str),
	atomic_list_concat([Extract|_], End, Second).
	
	
read_node_until(Str, End, Lines) :-
	read_node_until1(Str, End, [], Lines).
	
read_node_until1(Str, End, In, Lines) :-
		read_line_to_chars(Str, Line),
		(
			\+ wildcard_match(End, Line),
			read_node_until1(Str, End, [In,Line], Lines)
		;
			wildcard_match(End, Line),
			Lines = [In,Line]
		).
		

init_fbo1 :-
	thread_create(initialize_gdb, _, [alias(init_fbo_data)]).

	
:- dynamic(new_node/3).
:- dynamic(new_edge/5).

new_node(A,B,C) :- assert(node(A,B,C))
	
init_fbo :-
	get_time(StartTime),
	log_messageF(info(start_import)),
%	load_max_id,
	notices(Notices),
%	gephi:set_neo_mode(import),
%	add_graph_dest(neo4j),
	new_node(test, test, [a=b]),
%	add_graph_dest(gephi),
	findall(Sn, fcypher_query('match (n:solicitation) return n.SOLNBR', [], row([Sn])), Snlist),
	(
		fcypher_query('MATCH (n:`solicitations`) RETURN id(n) limit 5', [], row([Id|_]))
	;
		new_node('solicitations', 'solicitations', [size=20])
	), !,
	findall(sol(SOLNBR,Notice,Attributes),
	(
		member(Notice, Notices),
		format(atom(Q), '//~w/SOLNBR/..', [Notice]),
		xq(Q, Result, [format(xml)]),
		Result = [element(_,_,List)],
		member(element(Notice,_,Sub), List),
		member(element('SOLNBR',_,[SOLNBR]),Sub),
		findall(Attribute=Value, (member(element(Attr,_,[Value|_]),Sub), downcase_atom(Attr, Attribute)), Attributes)
	), Solicitations1),
	findall(Sol, member(sol(Sol,_,_), Solicitations1), SolList),
	list_to_set(SolList, SolSet1),
	subtract(SolSet1, Snlist, SolSet),
	length(SolSet1, Total1),
	length(Snlist, NDup),
	length(SolList, TNot),
	length(SolSet, Total),
	format('Solicitation total notices ~w skipped solicitations ~w unique solicitations ~w unique solicitations left to import ~w\n',[TNot, Total1, NDup, Total]),
	links(Links),
	Max = 5000,
	flag(nsol, _, 0),
	flag(tnsol, _, 0),
	(
		member(Solicitation, SolSet),
		flag(nsol, NSol, NSol+1),
		flag(tnsol, TNSol, TNSol+1),
		(
			NSol >= Max,
			flag(nsol, _, 0),
			flag(import_id,Curr,Curr),
			log_messageF(info(flush_import,TNSol,Curr)),
			format('transmitting batch update transactions ~w total ~w ImportId ~w\n',[NSol,TNSol,Curr]),
			flush(import)
		;
			NSol < Max
		),
		new_node(Solicitation, solicitation, [size=10,'SOLNBR'=Solicitation]),
		new_edge(sol_+Solicitation, solicitations, Solicitation, solicitation),
		member(sol(Solicitation,Notice,AttrList), Solicitations1),
		(
			member(Attr=Value, AttrList),
			member(Attr, Links),
			new_node(Value, Attr, [size=15,Attr=Value]),
			new_edge(Attr+Solicitation+Notice+Date, Solicitation+Notice+Date, Value, Attr),
		fail;true),
		intersection([date=Date], AttrList, _),
%		\+ tmember(Solicitation+Notice+Date, Snlist),
		findall(Attr=Val, (member(Attr=Val, AttrList), \+member(Attr,Links)), Attrs),
		new_node(Solicitation+Notice+Date, [Notice,notice], [size=5|Attrs]),
		new_edge(notice_+Solicitation+Notice+Date, Solicitation, Solicitation+Notice+Date, notice),
	fail;true),
	format('Loading database \n',[]),
	gephi:flush(import),
	gephi:set_neo_mode(instant),
	index_solicitation,
	get_time(EndTime),
	Delta is EndTime-StartTime,
	log_messageF(info(end_import,Total,Delta)),
	true, !.

tmember(E, L) :-
		gephi:atomic_id(E, E1),
		member(E1, L).
		
index_solicitation :-
	cypher_query('CREATE CONSTRAINT ON (s:solicitation) ASSERT s.SOLNBR IS UNIQUE', [], _),
	true.
		
test(old) :-
	retractall(neo4j_id(_,_)),
	add_graph_dest(neo4j),
%	gephi:set_neo_mode(instant),
	new_node(mynode1, testnode, []),
%	new_node(mynode2, testnode, []),
%	new_edge(Rel, mynode1, mynode2, testrel),
	true.	
	
test(instant_mode) :-
	retractall(neo4j_id(_,_)),
	add_graph_dest(neo4j),
	gephi:set_neo_mode(instant),
	new_node(MyNode1, testnode, [a=b,b=c,d=f]),
	new_node(MyNode2, testnode, [a=b,b=c,d=f]),
	new_edge(Rel, MyNode1, MyNode2, testrel),
	true.	
test(batch_mode) :-
	retractall(neo4j_id(_,_)),
	add_graph_dest(neo4j),
	gephi:set_neo_mode(batch),
	new_node(MyNode1, testnode, [a=b,b=c,d=f]),
	new_node(MyNode2, testnode, [a=b,b=c,d=f]),
	new_edge(Rel, MyNode1, MyNode2, testrel),
	gephi:flush(batch),
	true.
	
/*


-<file_data modified="1418483532.5513496" size="271934" type="unknown" ext="pdf" filename="15T0040_sol.pdf" absolute_filename="c:/users/jerryxeon/google drive/fedbiz/files/15t0040_sol.pdf" solicitation="FILES">

<pdf_info PDFversion="1.5" Optimized="yes" Filesize="271934 bytes" Pagesize="612 x 792 pts (letter) (rotated 0 degrees)" Encrypted="no" Pages="39" Form="none" Tagged="no" ModDate="11/26/14 15:02:57" CreationDate="11/26/14 15:02:57" Producer="Acrobat Distiller 10.1.10 (Windows)" Creator="PScript5.dll Version 5.2.2" Author="phyllis.hoggatt" Title="Microsoft Word - pd27AC5"/>

</file_data>



*/

compile_file_data :-
	load_xml_file('file_data.xml', XML),
	findall(Solicitation, xpath:xpath(XML, //(file(@solicitation)), Solicitation), Sols),
	list_to_set(Sols, SolSet),
	(
		member(Sol, SolSet),
		xpath:xpath(XML, //(file(@solicitation=Sol)), FileData),
		compile_xml_gdb(Sol, FileData, []),
	fail;true
	).
	
	
/*

Compile xml to graph database

	Features
		- link_to - contains enough information to link the node to another node
			'solicitation{attr: "value"};direction;label'
			'solicitation{attr: "value"};label'
			'solicitation{attr: "value"}'
		- defer_link_to - same as link_to but is deferred until later
*/
compile_xml_gdb(element(Node,Attr,Sub)) :-
	compile_xml_gdb(element(Node,Attr,Sub),[]).
compile_xml_gdb(element(Node,Attr,Sub), Options) :-
	compile_xml_gdb(null, element(Node,Attr,Sub), Options).
	
compile_xml_gdb(Parent, element(Node,Attr,Sub), Options) :-
	\+ member(instant, Options),
	set_neo_mode(Old,import),
	reset_import,
	add_graph_dest(neo4j),
	compile_xml_gdb1(Parent, element(Node,Attr,Sub), XOut),
	intersection([xml_out=XOut], Options, _),
	(
		\+ member(noflush, Options),
		ignore(flush(import)),
		ignore(flush(execute)),
		set_neo_mode(Old)
	; true
	), !,
	true.
compile_xml_gdb(Parent, element(Node,Attr,Sub), Options) :-
	member(instant, Options),
	compile_xml_gdb1(Parent, element(Node,Attr,Sub), XOut),
	intersection([xml_out=XOut], Options, _),
	true.
	
compile_xml_gdb1(Parent, element(Node,Attr,Sub), element(Node,[id=P|Attr],NewSub)) :-
			\+ is_list(Parent),
			Parent \= null,
			(
				\+ member(gdb_option=Options, Attr),
				new_node(P, Node, Attr),
				new_edge(_, Parent, P, Node)
			;
				member(gdb_option=Options, Attr),
				member(load=false, Options),
				P = null
			),
			findall(XOut, 
			(
				member(SubNode, Sub),
				compile_xml_gdb1(P, SubNode, XOut)
			), NewSub).
compile_xml_gdb1(null, element(Node,Attr,Sub), element(Node,[id=P|Attr],NewSub)) :-
			(
				\+ member(gdb_option=Options, Attr),
				new_node(P, Node, Attr)
			;
				member(gdb_option=Options, Attr),
				member(load=false, Options),
				P = null
			),
			(
				member(link_to__=Link, Attr),
				new_node(P, Node, Attr),
				new_edge(_, Link, P, Node)
			;
				\+member(link_to__=Link, Attr)
			),
			findall(XOut, 
			(
				member(SubNode, Sub),
				compile_xml_gdb1(P, SubNode, XOut)
			), NewSub).
compile_xml_gdb1(_, Node, Node) :-
	Node \= element(_,_,_).
	

download_file(Link,File) :-
	http_open(Link, Str, [cert_verify_hook(user:cert_verify)]), 
%	read_stream_to_codes(Str, Codes), 
%	atom_codes(Reply, Codes), 
	increment(download_attempt),
	open(File, write, W, [type(binary)]),
	copy_stream_data(Str, W),
	close(Str),
	close(W),
	increment(download_complete),
	log_message(download(Link,File)).


	
get_url(Link,Reply) :-
	http_open(Link, Str, [cert_verify_hook(user:cert_verify)]), 
	read_stream_to_codes(Str, Codes), 
	atom_codes(Reply, Codes).
	
parse_files(Html, FileList) :-
	atomic_list_concat(List, 'class="file"', Html),
	findall(File, (member(Text, List), atomic_list_concat([File|_], '</div>', Text)), Files),
	findall(file(Name,Link), 
	(
		member(FileText, Files), 
		atomic_list_concat([_,Link1|_], 'href=\'', FileText), 
		atomic_list_concat([Link|_], '\'', Link1),
		atomic_list_concat([_,Name1|_], 'class=\'file\'>', FileText), 
		atomic_list_concat([Name|_], '</a>', Name1)
	), FileList),
	debug(parse_files, '~w', [FileList]).

test_download :-
	format(atom(Q), '//SOLNBR[text()="~w"]/../LINK[1]', ['BAA-RVKD-2014-0001']),
	xq(Q, Result, [format(xml)]),
	once(xpath:xpath(Result, //('LINK'), element(_,_,[Link|_]))),
	get_url(Link, Reply),
	parse_files(Reply, Files),
	(
		member(file(Name,File), Files),
		atomic_concat('https://www.fbo.gov',File,URL),
		atomic_concat('./Files/',Name,FullName),
		download_file(URL,FullName),
	fail;true).
	
solicitation_link2(SolNbr, Link) :-
	format(atom(Q), '//SOLNBR[text()="~w"]/../LINK', [SolNbr]),
	xq(Q, Result, [format(xml)]),
	once(xpath:xpath(Result, //('LINK'), element(_,_,[Link|_]))).
	
solicitation_link(Sol, Link) :-
	once(fcypher_query('match (n:notice {solnbr: "~w"}) return n.link', [Sol], row([Link]))),
	log_messageF(info(link(Sol,Link))),
	atom(Link),
	wildcard_match('*http*',Link), 
	increment(dl_using_link),
	!.
solicitation_link(Sol, Link0) :-
% got same bad data with \n at end of solnbr. delete this when it is cleaned up.
	once(fcypher_query('match (n:notice {solnbr: "~w\n"}) return n.link', [Sol], row([Link]))),
	log_messageF(info(link_cr(Sol,Link))),
	atom(Link),
	wildcard_match('*http*',Link), 
	replace(Link, '\n', '', Link0),
	increment(dl_using_linkcr),
	!.
solicitation_link(Sol, Link) :-
	once(fcypher_query('match (n:notice {solnbr: "~w"}) return n.url', [Sol], row([Link]))),
	log_messageF(info(url(Sol,Link))),
	atom(Link),
	wildcard_match('*http*',Link), 
	increment(dl_using_url),
	!.	
solicitation_link(Sol, Link0) :-
	once(fcypher_query('match (n:notice {solnbr: "~w\n"}) return n.url', [Sol], row([Link]))),
	log_messageF(info(url_cr(Sol,Link))),
	atom(Link),
	wildcard_match('*http*',Link), 
	replace(Link, '\n', '', Link0),
	increment(dlm_using_url_cr),
	!.	
solicitation_link(Sol, Link) :-
	increment(dlm_no_link),
	throwF('No link found for solicitation ~w',[Sol]),
	!.		
	
user:throwF(Format, Args) :-
	format(atom(Atom), Format, Args),
	throw(Atom).


make_dir_if_not(Dir) :-
	\+ exists_directory(Dir),
	make_directory(Dir).
make_dir_if_not(Dir) :-
	exists_directory(Dir).
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Text Mining Manager %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

/*

Process:

	1. Categorize files
		- create DB entry for each file and solicitation e
			- categorize (best guess) based on filename m
	2. Mine FBO files and compile into gdb
	3. Mine FBO images and compile into gdb using Tesseract

 

*/

:- listen(check_solicitation(Solicitation), thread_send_message(file_cataloger, analyze_fbo_files(Solicitation))).

user:fcat :-
	exec:back(fedbizopps:fcat1).
user:fcat1 :-
% Analyze and catalog fbo files and compile results into gdb
	retractall(walk_file(_,_)),
	add_graph_dest(neo4j),
	log_messageF(info(fcat_start)),
	append(LoadedFiles, ['*.pdftext', '*image*.*','info.txt', '*annie*.*','*.ignore','*.pl'], Exclude),
	greplite:walk_files([fedbizopps:analyze_file], ['*.*'], Exclude, ['./Files'], Hits, [output=escape]),
%	open('fbo_files.xml', write, W, []), xml_write(W, [element(fbo_files,[],Hits)], []), close(W),
	log_messageF(info(fcat_complete)),
%	findall(H, fedbizopps:walk_file(_,H), Hits1),
%	format('output = ~w\n',[Hits1]), 
	!.
%	compile_xml_gdb(element(fbo_files,[],Hits1)), !.
	
fcat_import :-
	findall(H, walk_file(_,H), Hits1),
%	format('output = ~w\n',[Hits1]),
	compile_xml_gdb(element(fbo_files,[],Hits1)), 
	retractall(walk_file(_,_)),
	!.

fcat_analyze_file(File) :-
	analyze_file(File,_,Out),
	increment(analyze_file),
	compile_xml_gdb(Out), 
	increment(fcat_compiled),
	!.
	
analyze_fbo_files(Solicitation) :-
	add_graph_dest(neo4j),
	log_on_error(analyze_fbo_files1(Solicitation)).
	
log_on_error(Goal) :-
	catch( Goal, Error, (log_messageF(error(Error)),fail)).
	
analyze_fbo_files1(Solicitation) :-
% Analyze and catalog fbo files and compile results into gdb
	format(atom(Dir), './FILES/~w', [Solicitation]),
	findall(FileName, fcypher_query('MATCH (n:file) RETURN n.filename', [], row([FileName])), LoadedFiles),
	greplite:walk_files([fedbizopps:analyze_file], ['*.*'], ['*.pdftext', '*image*.*','info.txt', '*annie*.*','*.ignore','*.pl'], [Dir], Hits),
	open('fbo_files.xml', write, W, []), xml_write(W, [element(fbo_files,[],Hits)], []), close(W),
	compile_xml_gdb(element(fbo_files,[],Hits)).	
	
	
fbo_gate :-
% Run fbo files through GATE and compile output into gdb
	findall(FileName, fcypher_query('MATCH (n:gate) RETURN n.filename', [], row([FileName])), LoadedFiles),
	append(LoadedFiles, ['*.pdftext', '*image*.*','info.txt', '*annie*.*','*.ignore','*.pl'], Exclude),
	greplite:walk_files([fedbizopps:mine_file], ['*.*'], ['*.pdftext', '*image*.*','info.txt','*annie*.*','*.ignore','*.pl'], ['./Files'], Hits, []),
	true.
	
queue_fbo_gate :-
% Run fbo files through GATE and compile output into gdb
	set_neo_mode(Old,import),
	findall(FileName, fcypher_query('MATCH (n:gate) RETURN n.filename', [], row([FileName])), LoadedFiles),
	append(LoadedFiles, ['*.pdftext', '*image*.*','info.txt', '*annie*.*','*.ignore','*.pl'], Exclude),
	greplite:walk_files([fedbizopps:queue_mine_file], ['*.*'], ['*.pdftext', '*image*.*','info.txt','*annie*.*','*.ignore','*.pl'], ['./Files'], Hits, []),
	flush(import),
	flush(execute),
	set_neo_mode(Old),
	true.
	
count_files(File, _, File).
user:count_files :-
	get_time(T),
	greplite:walk_files([fedbizopps:count_files], ['*.*'], ['*.pdftext', '*image*.*','info.txt','*annie*.*','*.ignore','*.pl'], ['./Files'], Hits, [output=escape]),
	get_time(T1),
	Delta is T1-T,
	length(Hits, Total),
	format('Number of hits=~w time = ~w\n',[Total,Delta]).	
fbo_gate1 :-
% Run fbo files through GATE and compile output into gdb
	greplite:walk_files([fedbizopps:mine_file], ['*.*'], ['*.pdftext', '*image*.*','info.txt','*annie*.*','*.ignore','*.pl'], ['./Files'], Hits),
	true.
	
	
image_mine_fbo :-
% Extract images from pdf files, run through GATE and compile output into gdb
	greplite:walk_files([fedbizopps:extract_images], ['*.pdf'], [], ['./Files'], Hits),
	true.
	

test_anal :-
	greplite:walk_files([fedbizopps:analyze_file], ['*.*'], ['*.pdftext', '*image*.*','info.txt'], ['./Files'], Hits),
	assert(hits(Hits)),
	open('fbo_files.xml', write, W, []), xml_write(W, [element(fbo_files,[],Hits)], []), close(W).


:- dynamic(file_category/2).

user:fshell(Format, Args, Status) :-
	format(atom(Cmd), Format, Args),
	shell(Cmd, Status).

:- dynamic(pdfinfo/1).
	
register_bat :-
	working_directory(Old,Old),
	retractall(pdfinfo(_)),
	atomic_list_concat([Old,'/','pdf.bat'], Pdfinfo),
	assert(pdfinfo(Pdfinfo)).
	
:- register_bat.



twn(Nodes, [element(Node,Attr,Sub)|T], Out) :-
	member(id=Id, Attr),
	append(Nodes, [element(Node,[nid=Id],Sub)], NodeList), !,
	twn(NodeList, T, Out), !.
twn([element(_,Attr,_)|_], [H|T], [element(word,[text=H,nid=Start],[])|Out]) :-
	H \= element(_,_,_),
	intersection([nid=Start],Attr,_),
	\+ white_space(H),
	twn([], T, Out), !.
twn(Nodes, [H|T], Out) :-
% skip white space
	H \= element(_,_,_),
	white_space(H),
	twn(Nodes, T, Out), !.
twn(Nodes, [], []).


white_space(X) :-
	atom_codes(X, Codes),
	white_space1(Codes).
	
white_space1([H|T]) :-
	code_type(H, white),
	white_space1(T).
white_space1([]).

user:mine(File) :-
	mine_file(File, _, _).


queue_mine_file(File, _, na) :-
	File\=absolute(_),
	absolute_file_name(File, Abs),
	get_time(T0),
	file_solicitation(Abs, Solicitation),
	file_solicitation(Abs, Solicitation),
	notice_dates(Solicitation, Dates),
	sort(Dates,[_-date(_,Priority)]),
	new_node(_, check, [type=gate,priority=Priority,filename=Abs,created=T0,status=pending]).
	
queue_mine_file(absolute(Abs), _, na) :-
	get_time(T0),
	file_solicitation(Abs, Solicitation),
	notice_dates(Solicitation, Dates),
	sort(Dates,[_-date(_,Priority)]),
	new_node(_, check, [type=gate,priority=Priority,filename=Abs,created=T0,status=pending]).
	
notice_dates(Solicitation, Dates) :-
	findall(Days-date(date(Y,M,D),Priority), 
	(
		fcypher_query('match (n:notice {solnbr: "~w"}) return n.date',[Solicitation],row([Date])),
		atom_codes(Date, [A1,A2,A3,A4,A5,A6,A7,A8|_]),
		atom_codes(YearA, [A5,A6,A7,A8]),
		atom_codes(MonthA, [A1,A2]),
		atom_codes(DayA, [A3,A4]),
		atom_number(YearA,Y),
		atom_number(MonthA,M),
		atom_number(DayA,D),
		todays_date(Today),
		subtract_days(date(Y,M,D), Today, Days),
		notice_priority(Days,Priority)
	), Dates).
	
notice_priority(D,p0) :-
	D < 30, !.
notice_priority(D,p1) :-
	D < 90, !.
notice_priority(D,p2) :-
	D < 180, !.
notice_priority(D,p3) :-
	D < 360, !.
notice_priority(_,p5).
	
mine_file(File, _, Out) :-
	File\=absolute(_),
	absolute_file_name(File, Abs),
	mine_file1(Abs, X, Out), 
	!.
mine_file(absolute(Abs), _, Out) :-
	mine_file1(Abs, X, Out),
	!.
mine_file(File, _, _) :-
	get_time(T0),
	new_node(_,failed_gate,[filename=File,time=T0]),
	increment(failed_gate),
	fail.
	
file_solicitation(Abs, Solicitation) :-
	atomic_list_concat(DirList, '/', Abs),
	reverse(DirList, [_,Solicitation1|_]),
	upcase_atom(Solicitation1, Solicitation).

/*
 
GATE processing

	- Break document down into sentences, sections and words

	sol -> gate -> section -> sent -> words -> w

*/

mine_file1(Abs, _, na) :-

	fcypher_query('match (n:gate {absolute_file_name: "~w"}) return count(n)',[Abs], row([Cnt])),
	must(Cnt = 0,'Gate already run for this file ~w',[Abs]),				% No duplicates
	atomic_list_concat(FileList, '/', Abs), 
	reverse(FileList, [File|_]),
	log_messageF(info(start_mining,Abs,File)),
	atomic_list_concat(DirList, '/', Abs),
	reverse(DirList, [_,Solicitation1|_]),
	upcase_atom(Solicitation1, Solicitation),
%	log_messageF(info(start_gate,File)),
	categorize_file(Abs, _, DocType),
	
	increment(run_annie),
	fshell('c:/san.bat "file:///~w"', [Abs], _),
	increment(annie_completed),
	log_messageF(info(gate_complete,File)),
	increment(load_annie),
	catch( load_xml_file('StANNIE_toXML_1.xml', [XML|_]), Error, (log_messageF(gate_load_fail(Solicitation,Abs,Error)),increment(gate_load_fail),fail)),
	increment(load_annie_complete),
	delete_file('StANNIE_toXML_1.xml'),
	gate_features([XML], Features),

%	log_messageF(info(before_annotations,File)),
	
	xpath:xpath(XML, /('GateDocument')/('TextWithNodes'(text)), AllText),
	
	gate_annotations(XML, AllText, ['Sentence',b], Annotations),		% Extract selected annotations
	increment(gate_annotations),
	
%	log_messageF(info(after_annotations,File)),
	
	gate_sections(element(node,[],Annotations), AllText, Sections),		% Create section annotations. Right now using b annotations to derive sections
	increment(gate_sections),
	
%	format('~w\n',[Out]),

	flatten([Features, Annotations, Sections], Gate),
	
%	log_messageF(info(before_compile,File)),
	
	format(atom(Defer), 'solicitation{SOLNBR: "~w"};from;gate', [Solicitation]),
	get_time(T0),
	GateXML = element(gate, [defer_link_to__=Defer,text=AllText,filename=File,absolute_file_name=Abs,type=type,created=T0,contents=[sentences,sections,words,keywords]],Gate),
	
	set_neo_mode(import),
	add_graph_dest(neo4j),
	new_node(Document, document, []),
	compile_xml_gdb(Document, GateXML, [xml_out=NewXML]),	% Compile (into graphdb) 
	increment(gate_compile),
	NewXML = element(_,NewAttr,_),		% NewXML contains id's of graph nodes
	
% construct word links

	intersection([id=GateId], NewAttr, _),	
	xpath:xpath(XML, /('GateDocument')/'TextWithNodes', element(_,_,TWN)),
	twn([], TWN, Out),
	
	findall(w(W,Node), (member(element(word,[text=W0,nid=Node],_), Out), adjust_case(W0,W)), AllWords),		% all words with node location
	findall(w(W), member(w(W,_), AllWords), AllWords1),														% all words w/out node location

/*
Keyword processing
	- Use Alchemy to create a keyword list from the text
	- Add keywords to both wordlists
	- For multiple word keywords, use the node id of the first word
*/
	downcase_atom(AllText, AllTextd),
	min_relevance(MinRel),
	alchemy:extract_keywords(text, AllText, Keywords),		% will this crash if text is too long? May need to put text in body of request
	findall(kw(KW,Node),
	(
		member(keyword(KW,RelA), Keywords),
		downcase_atom(KW, KWd),
		atom_number(RelA, Rel),
		Rel > MinRel,
		sub_atom(AllTextd, Before, _, _, KWd),
		Node is Before+1
	), KeywordList),
	findall(kw(KW), member(kw(KW,_), KeywordList), KeywordList1),
	append(AllWords1,KeywordList1,AllWords2),
	append(AllWords,KeywordList,AllWords0),
	
	list_to_set(AllWords2, WSet),
	(
		member(W1t, WSet),
		W1t =.. [Type1,W1],
		(
			Type1=w,
			Label1=word
		;
			Type1=kw,
			Label1=[keyword,word]
		),
		
/*
		include_word(W1),					% Don't include certain words such as and, the, for, to, etc.
		new_node(W1, w, [word=W1]),			% Make sure the word is in the big wordset
		new_node(XX, word, [word=W1]),		% Create a word for this document
		new_edge(_,W1,XX,word_used),		% Link wordset to this word (means word used in document)
		new_edge(_, GateId, XX, has_word),	% Link the word to the root gate node


*/
		
		include_word(W1),					% Don't include certain words such as and, the, for, to, etc.
		new_node(W1, w, [word=W1]),			% Make sure the word is in the big wordset
		new_node(XX, Label1, [word=W1]),		% Create a word for this document
		new_edge(_,W1,XX,word_used,[owner=unknown,type=DocType]),		% Link wordset to this word (means word used in document)
		new_edge(_, GateId, XX, has_word),	% Link the word to the root gate node
		
		findall(SentenceId,
		(
			member(WordTerm, AllWords0),
			WordTerm =.. [_,W1,Node],
			xpath:xpath(NewXML, /('gate')/('Annotation'(@id=SentenceId,@'Type'='Sentence',@'StartNode'=Start,@'EndNode'=End)), _), 
			fbetween(Start,End,Node)
		), AllSent),
		list_to_set(AllSent,SentSet),
		
		member(ThisSent, SentSet),
		new_edge(_, XX, ThisSent, sentence),	% Create a link to the sentence where it is used.
	fail;true
	),
	trace,
	increment(gate_link_words),

	gate_link_annotations(NewXML, 'Sentence', 'Section'),	%links hierarchical annotations (e.g. sentence -> sentence)
	flush(import),
	flush(execute), 
	set_neo_mode(instant),
	log_messageF(info(mining_complete,File)),
	increment(gate_complete),
	!.
	
user:include_word(W0) :-
	adjust_case(W0,W),
	\+ ignore_word(W),
	downcase_atom(W,Dw),
	catch(term_to_atom(Term, Dw), _, fail),
	atom(Term),
	\+ not_word(Term),
	Dw \= ''.

not_word(W) :-
	atom_codes(W,C),
	member(C1,C),
	\+ once((code_type(C1, alpha);code_type(C1, digit))), 
	!.
	
min_relevance(0.3).
	
user:ignore_word(W) :-
	word_cat(exclude,_,Words),
	member(W,Words), !.
	
adjust_case(In, Out) :-
% try to account for case variations. For example, if the first letter of a word is upper and the rest lower, covert to lower. All upper should stay upper, etc.
	atom_codes(In, [F,S|_]),
	code_type(F, upper),
	code_type(S, lower),
	downcase_atom(In, Out), !.
adjust_case(In, In).

	
word_cat(exclude,pronoun, [i, me, we, us, you, he, him, she, her, it, they, them]).
word_cat(exclude,conjunction, [for,and,nor,but,or,yet,so]).
word_cat(exclude,article,[the,a,an,some]).
word_cat(exclude,demonstrative,[this,that,these,those,yon,yonder]).
word_cat(exclude,possessive,[my,mine,yours,his,her,their,our]).
word_cat(exclude,determiner,[all,some,many,few,every,most,lot]).
word_cat(exclude,numeral,[one,two,three,four,five,six,seven,eight,nine,ten,eleven,twelve,thirteen,fourteen,fifteen,sixteen,seventeen,eighteen,nineteen,twenty,thirty,fourty,fifty,sixty,seventy,eighty,ninety,hundred,thousand]).
word_cat(include,interrogative,[who,what,where,whence,whither,when,how,why,whether]).

gate_link_words(XML) :-
	(
		xpath:xpath(XML, //(word(@id=WordId,@nid=Node)), _),
		
		xpath:xpath(XML, /('gate')/('Annotation'(@id=SentenceId,@'Type'='Sentence',@'StartNode'=Start,@'EndNode'=End)), _), 
		fbetween(Start,End,Node),
		new_edge(_, WordId, SentenceId, sentence),
	fail;true).
gate_link_sentences(XML) :-
	(
		xpath:xpath(XML, //('Annotation'(@'Type'='Sentence',@id=SentenceId,@'StartNode'=Node,@'EndNode'=_End)), _),
		xpath:xpath(XML, //('Annotation'(@id=SectionId,@'Type'='Section',@'StartNode'=Start,@'EndNode'=End)), _), 
		fbetween(Start,End,Node),
%		format('linking word ~w to sentence ~w\n',[WordId, SentenceId]),
		new_edge(_, SentenceId, SectionId, section),
	fail;true).
gate_link_annotations(XML, Lower, Higher) :-
	(
 		xpath:xpath(XML, /('gate')/('Annotation'(@'Type'=Lower,@id=SentenceId,@'StartNode'=Node,@'EndNode'=_End)), _),
		xpath:xpath(XML, /('gate')/('Annotation'(@id=SectionId,@'Type'=Higher,@'StartNode'=Start,@'EndNode'=End)), _), 
%		format('linking ~w ~w to ~w ~w\n',[Lower, SentenceId, Higher, SectionId]),
		fbetween(Start,End,Node),
		new_edge(_, SentenceId, SectionId, section),
	fail;true).

fbetween(A,B,C) :-
	toint(A,A1),
	toint(B,B1),
	toint(C,C1),
	between(A1,B1,C1).
	
toint(In,In) :-
	number(In).
toint(In,Out) :-
	atom(In),
	atom_number(In,Out).

gate_annotations(XML, TextIn, Types, Annotations) :-
	findall(element(Node,Attr1,Sub),
	(
		member(Type, Types),
		xpath:xpath(XML, /('GateDocument')/'AnnotationSet', Aset),
		xpath:xpath(Aset, /('AnnotationSet')/'Annotation'(@'Type'=Type), element(Node,Attr,Sub)),
		intersection(['StartNode'=StartNode,'EndNode'=EndNode], Attr, _),
		atom_number(StartNode, Start),
		atom_number(EndNode, End),
		extract_text(Start,End,TextIn,Text),
		append(Attr, ['Text'=Text], Attr1)
	), Annotations).
	
extract_text(Start, End, Text, Out) :-
		Len is max(End-Start,1),
		sub_string(Text, Start, Len, _, Text1),
		atom_string(Out, Text1).
	
gate_features(XML, Features) :-
	xpath:xpath(XML, //('GateDocumentFeatures'), DocFeatures),
	findall(element(feature, [name=Name,value=Value], []),
	(
		xpath:xpath(DocFeatures, //('Feature'), Feature),
		xpath:xpath(Feature, /('Feature')/('Name'(text)), Name),
		xpath:xpath(Feature, /('Feature')/('Value'(text)), Value),
		Name \= 'Original_document_content_on_load',
		atom_length(Value, Len)
	), Features).
	
/*
Annotation Id="65" Type="b" StartNode="2530" EndNode="2560">
</Annotation>
*/
	
gate_sections(XML, TextIn, Sections) :-
	Type=b,
	findall(StartNode-section(Id,EndNode),
	(
		xpath:xpath(XML, //('Annotation'(@'Type'=Type)), element(_,Attr,_)),
		intersection(['Id'=Id, 'StartNode'=StartNode,'EndNode'=EndNode], Attr, _)
	), Sect),
	keysort(Sect,SortedSect),
	findall(element('Annotation', ['Type'='Section', 'Id'=0, 'Title'=Title, 'Text'=SectionText, 'StartNode'=StartNode, 'EndNode'=SectionEnd], []),
	(
		member(StartNode-section(Id, EndNode), SortedSect),
		nextto(StartNode-section(Id, EndNode), NextStart-section(NextId,NextEnd), SortedSect),
		atom_number(NextStart, NS),
		SectionEnd is NS-1,
		atom_number(StartNode, TitleStart),
		atom_number(EndNode, TitleEnd),
		SectTextStart is TitleEnd+1,
%		format('extract ~w ~w ~w ~w\n',[TitleStart,TitleEnd,SectTextStart,SectionEnd]),
		extract_text(TitleStart, TitleEnd, TextIn, Title),
		extract_text(SectTextStart, SectionEnd, TextIn, SectionText)
%		format('~w ~w\n',[Title,SectionText])
		
	), Sections).
	
gate_text(XML, Start, End, Text) :-
	xpath:xpath(XML, //('TextWithNodes'), element(_,_,TWN)),
	gate_text1(TWN, Start, End, 0, [], Out, 0),
	atomic_list_concat(Out, Text).
	
gate_text1([element(_,Attr,_)|T], Start, End, Current, _, Out, 0) :-
	member('id'=Id, Attr),
	atom_number(Id, Curr),
	between(Start, End, Curr),
	gate_text1(T, Start, End, Curr, [], Out, 1).
gate_text1([element(_,Attr,_)|T], Start, End, Current, _, Out, 0) :-
	member('id'=Id, Attr),
	atom_number(Id, Curr),
	\+ between(Start, End, Curr),
	gate_text1(T, Start, End, Curr, [], Out, 0).
gate_text1([element(_,Attr,_)|T], Start, End, Current, In, Out, 1) :-
	member('id'=Id, Attr),
	atom_number(Id, Curr),
	between(Start, End, Curr),
	gate_text1(T, Start, End, Curr, In, Out, 1).
gate_text1([element(_,Attr,_)|T], Start, End, Current, In, In, 1) :-
	member('id'=Id, Attr),
	atom_number(Id, Curr),
	\+ between(Start, End, Curr).
gate_text1([H|T], Start, End, Current, In, Out, 0) :-
	H \= element(_,_,_),
	gate_text1(T, Start, End, Current, In, Out, 0).
gate_text1([H|T], Start, End, Current, In, Out, 1) :-
	H \= element(_,_,_),
	append(In, [H], In1),
	gate_text1(T, Start, End, Current, In1, Out, 1).
	
gate_text1([], _, _, _, In, In, _).



test(gate_text) :-
	load_xml_file('test.xml', XML),
	trace,
	gate_text(XML, 10, 100, Text),
	format('gate_text test results=~w\n',[Text]).
	
test(extract_sections) :-
	load_xml_file('test.xml', XML),
	trace,
	gate_sections(XML, Sections),
	format('gate_text test results=~w\n',[Sections]).	

%%%%%%%%%%%%%%%%%  end replace
	
:- dynamic(walk_file/2).
analyze_file(File, _, Out) :-
%	log_messageF(info(start_analyze_file,File)),
	categorize_file(File, _, Type),
	file_name_extension(BaseFile, Ext, File),
	absolute_file_name(File, Abs),
	atomic_list_concat(DirList, '/', Abs),
	reverse(DirList, [_,Solicitation1|_]),
	upcase_atom(Solicitation1, Solicitation),
%	analyze_file(Ext, File, BaseFile, _, Detail),
	size_file(File, Size),
	time_file(File, Time),
	format(atom(Defer), 'solicitation{SOLNBR: "~w"};from;file', [Solicitation]),
	Out = element(file,[defer_link_to__=Defer, solicitation=Solicitation,absolute_filename=Abs,filename=File,ext=Ext,'Type'=Type,size=Size,modified=Time],[]),
%	log_messageF(info(end_analyze_file,File)),
	assert(fedbizopps:walk_file(File,Out)).

	
analyze_file(pdf, File, BaseFile, _, [Out]) :-
%	fshell('pdftotext ~w ~w.pdftext',[File, BaseFile],_),
	parse_pdf_info(File, Out),
%	fshell('pdfimages ~w ~wimage', [File,BaseFile], _),
%	fshell('c:\san ~w', [File], _),
%	compile_gate(F),
%	delete_file('StANNIE_toXML_1.xml'),
	!.
	
parse_pdf_info(File,element(pdf_info,Info,[])) :-
	pdfinfo(Path),
	fshell('~w ~w', [Path,File], _),
	read_file_to_codes('info.txt', Codes, []),
	atom_codes(Atom, Codes),
	atomic_list_concat(Lines, '\n', Atom),
	findall(Attribute=Value,
	(
		member(Line, Lines),
		sub_string(Line, 0, 16, After, Attribute1s),
		atom_string(Attribute1, Attribute1s),
		replace(Attribute1, ':', '', Attribute2),
		replace(Attribute2, ' ', '', Attribute),
		sub_string(Line, 16, After, _, Values),
		atom_string(Value, Values)
	), Info).
	

analyze_file(_, _, _, _, []).

categorize_file(File, _, Type) :- 
	file_type(Strings, Type),
	member(String, Strings),
	downcase_atom(File, Dfile), 
	downcase_atom(String, Dstring),
	wildcard_match(Dstring, Dfile), !.  
categorize_file(File, _, Type) :-
	file_type(Strings, Type),
	member(String, Strings),
	downcase_atom(File, Dfile),
	downcase_atom(String, Dstring),
	atomic_list_concat([_,_|_], Dstring, Dfile), !. 
categorize_file(_, _, unknown).

determine_file_type(File, _, file_category(File,Type)) :-
	categorize_file(File, _, Type).

categorize_all_files :-
	greplite:walk_files([fedbizopps:determine_file_type], ['*.*'], ['./Files'], Hits),
	maplist(assert, Hits).

	
:- listen(file_event(From,Data), user:process_file(Data)). 

user:process_file(File) :-
	categorize_file(File, _, Type),
	retractall(file_category(File,Type)),
	assert(file_category(File,Type)), !.
	
file_type([question,answer,'q&a'], q_and_a).
file_type([jotfoc,otfo], jotfoc).
file_type([terms,conditions], t_and_c).

file_type(['*sources*sought*'], sources_sought).
file_type([cdrl], cdrl).
file_type([soo], soo).

file_type([industry], industry_day).
file_type([pws,sow], pws).
file_type([rfi], rfi).
file_type([rfp], rfp).
file_type([attendee], attendee_list).

categorize_files(File) :-
	(
		get_file(Path,Sol,File), 
		categorize_file(File,Sol,Type),
		new_node(FName, FName, [category=Type]),
		new_edge(Sol+FName, Sol, FName),
		gate(Path), 
		tesseract(Path),
	fail;true).

categorize_file(FileName,Type) :-
	(
		file_type(Names, Type),
		(
			member(Name, Names),
			once((wildcard_match(Name, FileName);contains(FileName,Name)))
		)
	).
	
contains(Big,Small) :-
	atomic_list_concat([_,_|_], Big, Small).
	
compile_xml_to_graph(File) :- 
	load_xml_file(File, XML),
	determine_xml_type(XML, Type),
	compile_file(Type,XML).
	
complile_xml(annie, File, XML) :-
	xpath:xpath(XML, //(x), element(_,_,List)),
	(
		member(Sub, List),
		next_to(List, Sub, Word),
		new_node(File-Sub, '', [value=Word]),
		new_edge(Name, From, To)
	).
	



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Download Executive %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

/*

The Download Executive is responsible for making sure that all solicitations that have files have been processed for downloads.

Assumes:

	- ExistDB up and running
	- Neo4j up and running
	
Rules:

	- Every solicitation that has files should have those files downloaded.
	
Processing:

	- Need updated list of solicitations that have files
	- Need list of solicitations that have at least one file downloaded
	- Need list of solicitation files on the system
	- Track delta changes with periodic complete resyncs
	
Metrics:

	- Total number of solicitations
	- Total number of solicitations with at least one file.
	- Total number of solicitation files captured.
	- Total number of solicitations in queue for processing.

*/

	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Download Manager %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


/*

The download manager has the responsibility to manage downloading solicitation files. A download is requested by placing a solicitation in the queue which
is eventually read and process by the download manager.

*/


download_window([window(1-5,0,8,20.0),window(1-5,20,23.9,30.0),window(1-5,8,20,300.0),window(6-7,0,24,10.0)]).
max_download(1000000,60.0).

:- dynamic(entry/2).
:- dynamic(dq/1).
user:cdq :- create_download_queue.
user:dm :- start_download_manager.




stats :-
	dq(Sol),
%	reconsult(log),
	length(Sol, Total),
	findall(S, log:entry(_,complete(S)), Completed),
	list_to_set(Completed, CompletedSet),
	length(CompletedSet, NCompleted),
	PComplete is 100*NCompleted/Total,
	format('Total Solicitations: ~w\nTotal Downloaded: ~w\nPercent Downloaded: ~w\n',[Total,NCompleted,PComplete]).

create_download_queue1 :-
% Create a download queue that consists of each solicitation that has a document_package (should mean it has files)
% There are lots of directories with no files. Need to figure out why.
	xq('//DOCUMENT_PACKAGES/PACKAGE/../../SOLNBR', X, [format(xml)]),
	findall(Sol, xpath:xpath(X, //('SOLNBR'), element(_,_,[Sol|_])), SolList),
	list_to_set(SolList, SolSet),
	open('download_queue.txt', write, Str, []),
	write_term(Str, SolSet, [quoted(true)]),
	format(Str, '.\n',[]),
	close(Str).

create_download_queue :-
% Create a download queue that consists of each solicitation that has a document_package (should mean it has files)
% There are lots of directories with no files. Need to figure out why.
	xq('//DOCUMENT_PACKAGES/PACKAGE/../../SOLNBR', X, [format(xml)]),
	findall(Sol, xpath:xpath(X, //('SOLNBR'), element(_,_,[Sol|_])), SolList),
	list_to_set(SolList, SolSet),
	get_solicitation_folders(Folders),
	subtract(SolSet, Folders, DLSet),
	length(SolSet, SolSetN),
	length(Folders, FoldersN),
	length(DLSet, DLSetN),
	log_messageF(info(create_dlq,SolSetN,FoldersN,DLSetN)),
	set_neo_mode(Old,import),
	(
		member(S, SolSet),
		get_time(T0),
		new_node(_, check, [type=download,priority=p3,solnbr=S,time=T0]),
	fail;true
	),
	flush(import),
	flush(execute),
	set_neo_mode(Old),
	true.
	
get_solicitation_folders(List) :-
	working_directory(Old,'./files'),
	expand_file_name('*', List),
	working_directory(_,Old),
	true.
	
update_dq1 :-
	dq(Sols),
	findall(Sol, 
	(
		member(Sol, Sols),
		\+ complete(Sol)
	), SolSet),
	open('download_queue.txt', write, Str, []),
	write_term(Str, SolSet, [quoted(true)]),
	format(Str, '.\n',[]),
	close(Str),
	retractall(dq(_)),
	assert(dq(SolSet)).
	
update_dq :-
	dq(Sols),
%	reconsult(log),
	findall(Sol, 
	(
		member(Sol, Sols),
		\+ complete(Sol)
	), SolSet),
	open('download_queue.txt', write, Str, []),
	write_term(Str, SolSet, [quoted(true)]),
	format(Str, '.\n',[]),
	close(Str).	
	
download_solicitation(SolNbr) :-
	increment(download_solicitation_check),
	format(atom(Dir), './Files/~w', [SolNbr]),
	abs_file(Dir, AbsDir),
	make_dir_if_not(AbsDir),
	solicitation_link(SolNbr, Link),
	get_url(Link, Reply),
	increment(retrieved_file_list),
	parse_files(Reply, Files),
	(
		member(file(Name,File), Files),
		atomic_concat('https://www.fbo.gov',File,URL),
		atomic_list_concat([Dir, '/',Name], FullName),
		(\+ exists_file(FullName) ; exists_file(FullName), (log_message(info('File already exists\n',FullName)), increment(file_exists)), fail),
		increment(download_file_attempt),
		download_file(URL,FullName),
		get_time(T0),
		new_node(_, check, [type=fcat,status=pending,url=URL,filename=FullName,created=T0]),
	fail;true).
	
start_download_manager :-
	increment(start_dl_manager),
	flag(download_manager_running,_,1),
	thread_create(download_manager, _, [alias(download_manager)]),
	sleep(1.0),
	load_log,
	load_queue.
	
stop_download_manager :-
	save_queue,
	flag(download_manager_running, _, 0).


get_next_solicitation(Id,Solicitation) :-
	increment(get_next_solicitation),
	once(
			fcypher_query('match (ck:check{type: "download", status: "pending"}) return id(ck),ck.solnbr order by ck.priority',[],row([Id,Solicitation]))
			),
	increment(next_solicitation_retrieved), !.
get_next_solicitation(_,_Solicitation) :- 
	increment(get_next_solicitation_sleep),
	sleep(60), 
	fail.
	
	
download_manager :-
	gephi:set_neo_mode(instant),
	add_graph_dest(neo4j),
	increment(dl_manager_started),
	log_message(info('Download manager started')),
	repeat,
	check_connection,
	download_window_open(Delay),
	get_next_solicitation(Id,Solicitation0),
	gephi:set_property(neo4j, Id, status, in_process),
	replace(Solicitation0, '\n', '', Solicitation),	
	must(nonvar(Solicitation),'DL Manager Solicitation not bound ~w\n',[Solicitation]),
	increment(dl_check_sol),
	log_messageF(info(dl_check_sol,Id,Solicitation)),
	catch( ignore(download_solicitation(Solicitation)), Error, 
	(
		gephi:set_property(neo4j, Id, status, error), 
		gephi:set_property(neo4j, Id, message, Error),
		fail_error(log_message(error(Error,Solicitation))), 
		increment(dl_sol_error), 
		fail
	)),
	gephi:set_property(neo4j, Id, status, delete),
%	gephi:del_node(Id),
	fail_error(log_message(complete(Solicitation))),
	increment(completed_solicitation),
	sleep(Delay),
	\+ flag(download_manager_running, 1,1).

check_connection :-
	increment(check_connection),
	check_connection1,
	flag(disconnected, 1, 1),
	sleep(60),
	check_connection1,
	flag(disconnected, 0, 0).
check_connection :-
	flag(disconnected, 0, 0),
	increment(check_disconnected),
	true.
	
check_connection1 :-
	flag(disconnected, Old, Old),
	catch( http_client:http_get('http://www.time.gov/', _, []), _, lost_connection(Old)), 
	(
		Old=1,New=0,
		increment(connection_restored),
		sms_text('Internet connection restored'),
		format('Internet connection restored\n', []),
		log_message(info(connection_restored))
	;
		true
	),
	flag(disconnected, _, 0),
	!.
check_connection1 :-
	flag(disconnected, _, 1).
	
lost_connection(Old) :-
	(
	  once(
		(
			Old=0,
			increment(connection_lost),
			sms_text('Internet connection lost'),
			format('Internet connection lost\n', []),
			log_message(error(connection_lost))
		))
	;
		true
	),
	fail.
	
failed_download(Solicitation) :-
	log:entry(T0,complete(Solicitation)), 
	log:entry(T1,error(error(_,Solicitation))),
	Dt is abs(T0-T1),
	Dt < 60, 
	increment(failed_download),
	!.
failed_download(Solicitation) :-
	log:entry(_,start(Solicitation)), 
	\+ log:entry(_,complete(Solicitation)).
	
complete(_) :- fail.
complete1(Solicitation) :-
	log:entry(_,complete(Solicitation)),
	\+ failed_download(Solicitation).
	
	
user:fail_error(Goal) :-
	catch( Goal, _, fail).
	
save_queue :-
	increment(save_queue),
	catch( findall(Message, thread_get_message(download_manager, Message), Messages), _, fail),
	open('download_queue.txt', write, Str, []),
	write_term(Str, Messages, [quoted(true)]),
	format(Str, '.\n',[]),
	close(Str), !.
save_queue.

load_log :-
%	reconsult(log),
	true.
	
create_log :-
	File = 'log.pl',
	exists_file(File),
	increment(create_log_exists),
	use_module(log).
create_log :-
	File = 'log.pl',
	\+ exists_file(File),
	increment(create_log_new),
	open(File, write, Str, []),
	format(Str, ':- module(log,[]).\n\n', []),
	close(Str),
%	use_module(log),
	true.
	


load_queue :-
	increment(load_queue),
	exists_file('download_queue.txt'),
	open('download_queue.txt', read, Str, []),
	read_term(Str, Messages, []),
	close(Str),
	retractall(dq(_)),
	assert(dq(Messages)),
	update_dq1,
	dq(Messages1),
	(
		member(Message, Messages1),
		thread_send_message(download_manager, solicitation(3,Message)),
	fail;true), !.
load_queue.

user:dwo :- download_window_open.	
download_window_open(Delay) :-
	flag(dm_pause, 0,0),				% not paused
	get_time(Now),
	stamp_date_time(Now, DT, local), 
	date_time_value(hour, DT, Hour),	
	date_time_value(minute, DT, Min),
	date_time_value(date, DT, Date),
	day_of_the_week(Date,Today),
	Time is Hour + Min/60.0,
	download_window(Windows),
	member(window(From-To,Start,Stop,Delay), Windows),
	between(From,To,Today),
	Start =< Time,
	Time =< Stop,
	increment(dlw_open),
	!.
download_window_open :-
	increment(dlw_not_open),
	sleep(60.0), fail.

/*

Process solicitation updates

	- Find newest data
	- Process newest data + 1 day
	
Process
	- Get update
	- Process each notice
	- Record Solicitation that was updated

*/	

:- add_graph_dest(neo4j).			% always using neo4j at the moment.
	
:- create_log.

	
