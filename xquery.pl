:- module(xquery, []).

:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_client)).
:- use_module(library(http/http_open)).
:- use_module(library(http/http_session)).
:- use_module(library(xpath)).

% query ( XQuery, Response, Options ) - query using xquery
% xq ( Xpath, Response, Options )	Query using xpath
% qget( Collection, Response, Options ) - query collection
% xup(Collection, Select, Update, Response) - update collection
% xdel
% xcreate
% xq_attr - query XML attributes - convenience function for accessing 1st level attributes in an xquery

/*

Prolog exist i/f
	exist(path,[attr=a])
	exist('//table/row', [fname=FName,lname=LName]).


*/

set_xquery(Flag) :-
	flag(xquery_available,_,Flag).
	
:- set_xquery(1).

user:xq_attr(Path, List) :-
% Perform xquery and unify with attributes of 1st level nodes in the result set
	xq(Path, X, [format(xml)]),
	X = [element(_,_,Subs)],
	member(Sub, Subs),
	Sub = element(_,AttrList,_),
	findall(Attr, member(Attr, AttrList), Attrs),
	intersection(List, Attrs, _).
	
user:xq_attr_all(Path, Row, Out) :-
% Collect all matching attributes from xquery
	findall(Row, xq_attr(Path, Row), Out).

base_url1('http://192.168.1.128:8080/exist/servlet/db/').

% try looking in session data first for the exist url. If not found then use the default.

user:base_url(URL) :-
	http_session:http_in_session(_),
	http_session:http_session_data(exist_url(URL)), 
	debug(xquery(url), 'get xquery url is ~w', [URL]),
	!.
user:base_url(URL) :-
	base_url1(URL), 
	debug(xquery(url), 'set xquery url is ~w', [URL]),
	!.
	
user:set_base(URL) :-
	debug(xquery(url), 'set xquery url to ~w', [URL]),
	http_session_asserta(exist_url(URL)).
	
set_base_default(X) :- retractall(base_url/1), assert(base_url(X)).

debug_goal(Flag, Goal) :-
	debug(Flag, 'before ~w', [Goal]),
	call(Goal),
	debug(Flag, 'after ~w', [Goal]).


eval(G,true) :- call(G).
eval(G,false) :- \+ call(G).


qhttp(S1,S2,Reply,[]) :-
	qhttp(S1,S2, Reply, [format(text)]).

qhttp(URL,Search,Reply,Options) :-
	member(format(text), Options),
	format_url(URL,Search,URLe),
	debug(get, '~w', [URLe]),
	http_get(URLe, Reply, []).

qhttp(URL,Search,Reply,Options) :-
	member(format(xml), Options),
	format_url(URL,Search,URLe),
	debug(get, '~w', [URLe]),
	load_xml_url(URLe, Reply).

load_xml_url(URL, Reply) :-
	http_get(URL, Reply1, []),
	lxs(Reply1, Reply).

:- dynamic(option/2).
option(howmany,1000000000).

format_url(URL, '', URL).

format_url(URL, Search, Result) :-
	Search \= '',
	www_form_encode(Search, Encoded),
	option(howmany,HowMany),
	sformat(Result, '~w?_query=~w&_howmany=~w', [URL,Encoded,HowMany]).
	

% query ( XQuery, Response, Options ) - query using xquery

safe:query(String,Sub) :- query(String,[element('exist:result', _Attr, Sub)],[format(xml)]).
user:query(String,Reply,Options) :-
	base_url(Base),
%	catch( qhttp(Base, String, Reply, Options), Error, throw(error('X Query failed',Error))).
	flag(xquery_available,1,1),
	catch( qhttp(Base, String, Reply, Options), Error, (set_xquery(0), fail)).
	
% xq ( Xpath, Response, Options )	Query using xpath

user:xq(Xpath, Reply, Options) :-
	sformat(Q, 'for $p in ~w return $p', [Xpath]),
	query(Q,Reply,Options).
user:xqs(Xpath, Reply, Options) :-
	sformat(Q, 'for $p in ~w return string($p)', [Xpath]),
	query(Q,Reply,Options).
user:xqs_list(Path, List) :- 
	xqs(Path, Reply, [format(xml)]),
	findall(Value, xpath(Reply, //'exist:value'(text), Value), List).

% update replace //*[id="~w"] with <...>
% update replace //fname[. = "Andrew"] with <fname>Andy</fname>
user:x_replace(Replace, With, Reply, Options) :-
	sformat(Q, 'update replace ~w with ~w', [Replace,With]),
	query(Q,Reply,Options).
	
% update value //fname[. = "Andrew"] with 'Andy'	
user:x_value(Replace, With, Reply, Options) :-
	sformat(Q, 'update replace ~w with ~w', [Replace,With]),
	query(Q,Reply,Options).

/* 
for $city in //address/city 

return

    update delete $city 
*/
	
user:x_delete(Delete, Reply, Options) :-
	sformat(Q, 'for $node in ~w return update delete $node', [Delete]),
	query(Q,Reply,Options).

% update insert <email type="office">andrew@gmail.com</email> into //address[fname
% ="Andrew"]

user:x_insert(Keyword, Expr, Node, Reply, Options) :-
	sformat(Q, 'return update insert ~w ~w ~w', [Expr,Keyword,Node]),
	query(Q,Reply,Options).

/* 
for $city in //address/city 

return

    update rename $city as 'locale'
*/

user:x_rename(Rename, With, Reply, Options) :-
	sformat(Q, 'for $node in ~w return update rename $node as ~w', [Rename,To]),
	query(Q,Reply,Options).




% qget( Collection, Response, Options )

user:qget(Col,Reply,Options) :-
	base_url(Base),
	sformat(URL, '~w~w', [Base,Col]),
	debug(get, '~w', [URL]),
	qhttp(URL, '', Reply, Options).

http_xml(URL,Reply) :-
	debug(get, '~w', [URL]),
	http_open(URL, Str, []),
	load_xml_file(Str, Reply),
	close(Str).

http_xml(URL,Q,Reply) :-
	format_url(URL,Q,URLe),
	debug(get, '~w', [URLe]),
	http_open(URLe, Str, []),
	load_xml_file(Str, Reply),
	close(Str).


tx(R) :-
	http_xml('http://localhost:8080/exist/servlet/db/ugs.xmi', R).

tx1(R) :-
	http_xml('http://localhost:8080/exist/servlet/db/data.xml', 'for $p in //row return $p', R).




tq(R) :- 
	query('for $p in //row return $p',R,[format(text)]).

tq1(R) :- 
	query('for $p in //row return $p',R,[format(xml)]).

% XUpdate predicates

% xup(Collection, Select, Update, Response)

user:xup(Collection, Select, Update, Reply) :-
	base_url(Base),
	sformat(URL, '~w~w', [Base,Collection]),
	X = [element('xupdate:update', ['xmlns:xupdate'='http://www.xmldb.org/xupdate',select=Select], [Update])],
	XML = xml(X),
	debug(serv_up, 'exist update: ~w', [XML]),
	http_post(URL, XML, Reply, []).


user:xremove(Collection, Select, Reply) :-
	base_url(Base),
	sformat(URL, '~w~w', [Base,Collection]),
	X = [element('xupdate:remove', ['xmlns:xupdate'='http://www.xmldb.org/xupdate',select=Select], [])],
	XML = xml(X),
	http_post(URL, XML, Reply, []).

xremt(R) :-
	xremove('', '//new', R).

user:xappend(Collection, Select, AppXML, Reply, []) :-
	compound(AppXML),
	AppXML = [element(Name,_,AppXML1)],
	base_url(Base),
	sformat(URL, '~w~w', [Base,Collection]),
	X = [element('xupdate:append', ['xmlns:xupdate'='http://www.xmldb.org/xupdate',select=Select], 
		[element('xupdate:element', [name=Name], AppXML1)]
	)],
	XML = xml(X),
	debug(get, '~w', [XML]),
	http_post(URL, XML, Reply, []).

user:xappend(Collection, Select, String, Reply, []) :-
	atom(String),
	lxs(String, AppXML),
	AppXML = [element(Name,_,AppXML1)],
	base_url(Base),
	sformat(URL, '~w~w', [Base,Collection]),
	X = [element('xupdate:append', ['xmlns:xupdate'='http://www.xmldb.org/xupdate',select=Select], 
		[element('xupdate:element', [name=Name], AppXML1)]
	)],
	XML = xml(X),
	debug(get, '~w', [XML]),
	http_post(URL, XML, Reply, []).

xappt(R) :-
	xappend(
		'', 
		'//row', 
		[ element(new,[],[element(test,[],[])])], 
		R, []).

xappt1(R) :-
	xappend(
		'', 
		'//row', 
		'<really_new><test/><test1/></really_new>', 
		R, []).

user:xrename(Collection, Select, NewName, Reply, []) :-
	base_url(Base),
	sformat(URL, '~w~w', [Base,Collection]),
	X = [element('xupdate:rename', ['xmlns:xupdate'='http://www.xmldb.org/xupdate',select=Select], [NewName])],
	XML = xml(X),
	http_post(URL, XML, Reply, []).



xinsert(_Collection, _Select, _AppXML, _Reply, []).



xupt(R) :- xup('data.xml', '//firstName', 'Joe', R).


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

user:xpost_file(Collection, File, Reply) :-
	base_url(Base),
	sformat(URL, '~w~w', [Base,Collection]),
	http_post(URL, file(File), Reply, []).
user:xpost_file(File) :-
	base_url(Base),
	sformat(URL, '~w~w', [Base,File]),
	http_post(URL, file(File), _Reply, []).

	
% xsort( XML, [sort(attribute,order), ... ], ResultXML)
% sort XML DOM one layer below root based on attribute value

xsort(element(Node, Attr, Sub), [Sort|Tail], Result) :-
	xsort(element(Node, Attr, Sub), Tail, Result1),
	xsort(Result1, Sort, Result).

xsort(element(Node, Attr, Sub), [], element(Node, Attr, Sub)).


% if it is a list of elements, make up a dummy root with the list as children, sort that and return the sorted children
xsort([H|T], Sort, Result) :-
	xsort(element(node, [], [H|T]), Sort, element(_, _, Result)).


xsort(element(Node, Attr, Sub), sort(Attribute,ascending), element(Node, Attr, Sub1)) :-
	findall(Key-Value, key_value(Key-Value, Sub, Attribute), List),
	keysort(List, Sorted),
	findall(Val, member(Key-Val, Sorted), Sub1).

xsort(element(Node, Attr, Sub), sort(Attribute,descending), element(Node, Attr, Sub1)) :-
	findall(Key-Value, key_value(Key-Value, Sub, Attribute), List),
	keysort(List, Sorted),
	reverse(Sorted, SortedR),
	findall(Val, member(Key-Val, SortedR), Sub1).

key_value(Key-element(Node, Attr, Sub), List, Attribute) :-
	member(element(Node, Attr, Sub), List),
	member(Attribute=Key, Attr).


/*

Exist admin functions
	- Store xml file
	- Create collection
	- Collection exists
	


*/

user:store_xml_files :-
	expand_file_name('*.xml', Files),
	(
		member(File, Files),
		store_file(File, '/db/templates'),
		fail;true
	).

store_file(FileName,Collection) :-
	Base = 'http://localhost:8080/exist/rest',
	format(atom(URL), '~w~w/~w', [Base,Collection,FileName]),
	upload_query(FileName,Collection,Q),
	Element = element(query, [xmlns='http://exist.sourceforge.net/NS/exist'], [element(text,[],[Q])]),
%	format('PUT ~w ~w~n',[URL,Element]),
	http_post(URL, xml(Element), Reply, []),
	format('REPLY ~w~n',[Reply]),
	true.
	
upload_query(FileName,Collection,Q) :-
	load_xml_file(FileName, XML),
	lxs(XMLStr, XML),
	Pass = 'N7287W06',
	L = 
	[
		'let $collection := "~w"~n',
		'let $filename := "~w"~n',
		'let $x := ~n~w~n',
		'let $login := xmldb:login($collection, "admin", "~w")~n',
		'let $store := xmldb:store($collection, $filename, $x)~n'
		, 'return~n <results> File {$filename} has been stored at collection={$collection} </results> '
	],
	L1 = 
	[
		'let $message := "Hello World!"~n',
		'return~n   <message>{$message}</message> '
	],
	atomic_list_concat(L, F),
	format(atom(Q), F, [Collection,FileName,XMLStr,Pass]).
	
create_colletion(Collection,Name).
collection_exists(Collection).
	
	
test(key_value) :-
	X = element(node,[],[
				element(node,[name=bull,age=20],[])
				,element(node,[name=zeke,age=25],[])
				,element(node,[name=oscar,age=53],[])
				,element(node,[name=oscar,age=24],[])
				,element(node,[name=oscar,age=44],[])
				,element(node,[name=bill,age=18],[])
				,element(node,[name=fred,age=24],[])
				,element(node,[name=bob,age=20],[])
			]),
	xsort(X, sort(name,ascending), Name),
	xsort(X, sort(age, descending), Age),
	xsort(X, [sort(age, ascending),sort(name,ascending)], AgeName),
	format('original xml:\n', []),
	xml_write(X, []),

	format('sort name:\n', []),
	xml_write(Name, []),

	format('sort age:\n', []),
	xml_write(Age, []),

	format('sort age, name:\n', []),
	xml_write(AgeName, []).




