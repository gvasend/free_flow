:- module(exec,[]).

:- use_module(graph_lib).
:- use_module(watch).
:- use_module(greplite).
:- use_module(xquery).
:- use_module(library(http/http_ssl_plugin)).
:- use_module(library(http/http_open)).
:- use_module(library(sgml)).
:- use_module(library(sgml_write)).
:- use_module(xmind).

/*

Process solicitation updates

	- Find newest data
	- Process newest data + 1 day
	
Teams
	- FBO updator
		- Notice/solicitation records
	- File cataloger
		- File records
	- Downloader
		- Manages download process
	- GATE
		- Manages mining process

	
FBO updator process
	- runds in background
	- runs once per day.
	
*/	

current_error(Stream) :-
    stream_property(Stream, alias(user_error)), !. % force det.

set_error(Stream) :-
    set_stream(Stream, alias(user_error)).

:- meta_predicate
    redirect_error(0, +).

redirect_error(Goal, File) :-
    current_error(OldErr),
    setup_call_cleanup(
        open(File, write, Err),
        setup_call_cleanup(
        set_error(Err),
        once(Goal),
        set_error(OldErr)),
        close(Err)).

fbo_update_schedule([]).

user:start_exec(Name) :- start_exec(Name, []).
user:start_exec(Name,Options) :-
	thread_create(exec:executive(Name,Options), Thread, [alias(Name)]).
	
member_default(Term, List, Default) :-
	member(Term, List), !.
member_default(Default, _, Default).
	
executive(Name,Options) :-
	set_state(Name, running),
	increment(started),
	tflag(exec_state,_,started),
	gephi:set_neo_mode(instant),
	add_graph_dest(neo4j),
%	must(healthy,'Database inoperable during startup',[]),
%	debug(new_node),
%	debug(fbo_update),
	log_messageF(info(exec_start(Name,Options,Mode))),
	intersection([handler=Goal], Options, _),
	repeat,
%	(flag(exec_pause,1,1), sleep(60), increment(paused), fail;\+ flag(exec_pause,0,0)),
	member_default(timeout=Timeout, Options, timeout=60),
	tflag(exec_state,_,wait_for_message),
	thread_get_message(Name, Message, [timeout=Timeout]),
	nonvar(Message),
	increment(process_message),
	tflag(exec_state,_,processing_message),
	log_messageF(info(thread_message_received(Name,Message))),
	once(generic_handler(Message)),
	nonvar(Goal),
	call(Goal,Message),
%	must(healthy,'Database inoperable during execution',[]),
	fail.
	
generic_handler(Term) :- member(Term, [exit,quit,stop]), thread_exit(normal).
generic_handler(call(Term)) :- call(Term).
generic_handler(periodic(Term,Time)) :- 
	periodic(Term,Time).
generic_handler(periodic_message(Name,Term,Time)) :- 
	periodic_message(Name,Term,Time).
	
periodic(Term,Time) :-
	catch(Term, Error, log_messageF(error(periodic(Term,Time),error(Error)))),
	compute_time(Time, T),
	alarm(T, periodic(Term,Time), Id, []).
periodic_message(Name,Term,Time) :-
	thread_send_message(Name,Term),
	log_messageF(info('Creating alarm',Name,Term,T)),
	compute_time(Time, T),
	alarm(T, periodic_message(Term,Time), Id, []).


user:norm_time(T,T1) :- compute_time(T,T1).	
compute_time(seconds(T),T).
compute_time(T,T) :- number(T).
compute_time(days(T), T1) :- T1 is T*60*60*24.
compute_time(minutes(M), S) :- S is M*60.
compute_time(hours(H), S) :- S is H*60*60.

user:process_check(Type, BeforeStatus, SuccessStatus, ErrorStatus, Goal) :-
	process_check(Type, BeforeStatus, SuccessStatus, ErrorStatus, Goal, []).
	
user:process_check(Type, BeforeStatus, SuccessStatus, ErrorStatus, Goal, Options) :-
		intersection([max_per_day=Max],Options,_),
		(
			nonvar(Max),
			todays_date(Today),
			tflag(Type-Today, Inc, Inc+1),
			Inc < Max,
			fail
		;
			true
		),

		fcypher_query('MATCH (n:check {type: "~w", status: "~w"} )  RETURN id(n),n.created order by n.created', [Type,BeforeStatus], row([Id,Created])),
		gephi:set_property(neo4j, Id, status, in_process), 
		catch( call(Goal,Id), Error, 
		(
			gephi:set_property(neo4j, Id, status, ErrorStatus),
			gephi:set_property(neo4j, Id, message, Error),
			fail
		)),
		(
			SuccessStatus\=delete,
			get_time(Time),
			Dt is Time-Created,
			gephi:set_property(neo4j, Id, status, SuccessStatus), 
			gephi:set_property(neo4j, Id, duration, Dt)
		;
			SuccessStatus=delete,
			gephi:del_node(Id)
		).

		
generic_handler(_).

fbo_update_process(Name) :-
	repeat,
	get_thread_queue(Command),
	process_command(Command),
	end_loop(Name).

end_loop(Name) :-
	sleep(60).
	
process_command(Goal) :-
	call(Goal).

:- dynamic(internal_fbo_update/1).

:- assert(internal_fbo_update(date(2015,1,1))).

/*

fbo_up :-
	nq(fbo_update_date(date=Date)),
	todays_date(Today),
	subtract_days(Date, Today, Days),
	numlist(1, Days, List),
	(
		member(Day, List),
		add_days(Date, Day, CheckDate),
		get_time(T),
		na(update_record(date=Date,created=T)),
		increment_stat(create_update_record),
	fail;true
	).
fbo_up :-
	\+ nq(fbo_update_date(date=_)),
	internal_fbo_update(TheDate),
	na(fbo_update_date(date=TheDate)).

*/

fbo_update_date(Date) :-
	fcypher_query('match (n:fbo_update_date) return n.date order by n.date desc', [], row([Time])),
	stamp_date_time(Time, Date1, local),
	date_time_value(date, Date1, Date),
	!.
fbo_update_date(Date) :-
	internal_fbo_update(Date).
	
update_fbo_date(Date) :-
		date_time_stamp(Date, Time),
		new_node(_, fbo_update_date, [date=Time,date1=Date]).
		
update_fbo_date1(Date) :-
	retractall(fbo_update_date(_)),
	assert(fbo_update_date(Date)).
	
user:process_fbo_updates :-
% create a list of days that need to be updated
	fbo_update_date(Date),
	todays_date(Today),
	subtract_days(Date, Today, Days),
	numlist(1, Days, List),
	(
		member(Day, List),
		add_days(Date, Day, CheckDate),
		create_update_record(CheckDate),
		increment(create_update_record),
	fail;true
	).
	
user:process_fbo_updates11 :-
	debug(fbo_update,'fbo_updates1',[]),
	log_messageF(info(fbo_updates1)),	
	add_graph_dest(neo4j),
	(
		% using once allows multiple hosts to work on the pending list.
		once(fcypher_query('MATCH (n:check {type: "fbo_update" status: "pending"} )  RETURN id(n),n.date,n.created order by n.created', [], row([Id,Date0,_]))),
		debug(fbo_update,'Process updates: ~w\n',[Date0]),
		increment_stat(processing_fbo_update),
		term_to_atom(CheckDate, Date0),
		gephi:set_property(neo4j, Id, status, in_process),
		catch( process_fbo_update(CheckDate), Error, (log_message(error(error_during_update,CheckDate,Error)),gephi:set_property(neo4j, Id, status, error),fail)),
		get_time(T0),
		gephi:set_property(neo4j, Id, status, complete),
		na(fbo_update_complete(date=Date0,time=T0)),
		increment_stat(processing_fbo_update_complete),
	fail;true
	).

user:process_fbo_updates1 :-
	add_graph_dest(neo4j),
%	ignore(process_check(fbo_update, retry_error, complete, retry_error1, exec:fbo_up)),
	ignore(process_check(fbo_update, error, complete, retry_error, exec:fbo_up)),
	ignore(process_check(fbo_update, pending, complete, error, exec:fbo_up)),
	!.
	
fbo_up(Id) :-
	once(fcypher_query('MATCH (n:check)  where id(n)=~w RETURN n.date,n.created order by n.created', [Id], row([Date0,_]))),
	debug(fbo_update,'Process updates: ~w\n',[Date0]),
	increment_stat(processing_fbo_update),
	term_to_atom(CheckDate, Date0),
	process_fbo_update(CheckDate),
	na(fbo_update_complete(date=Date0,time=T0)),
	increment_stat(processing_fbo_update_complete).
	
create_update_record(Date) :-
	term_to_atom(Date, Date1),
	fcypher_query('MATCH (n:check {type: "fbo_update"} ) where n.date="~w" RETURN count(n)', [Date1], row([Count])),
	Count < 1,
	get_time(T0),
	new_node(_, check, [date=Date,type=fbo_update,status=pending,created=T0]),
	true.
	
user:todays_date(Date) :-
	get_time(T),
	stamp_date_time(T,D,local),
	date_time_value(date, D, Date).
	
user:subtract_days(Date1, Date2, Days) :-
	SecPerDay is 60*60*24,
	date_time_stamp(Date1, Time1),
	date_time_stamp(Date2, Time2),
	Delta is Time2-Time1,
	Days is floor(Delta/SecPerDay).
	
user:add_days(Date1, Days, Date3) :-
	SecPerDay is 60*60*24,
	date_time_stamp(Date1, Time1),
	Result is Time1+Days*SecPerDay,
	stamp_date_time(Result, Date2, local),
	date_time_value(date, Date2, Date3).

process_fbo_update(date(Y,M,D)) :-
	Date = date(Y,M,D),
	log_messageF(info(fbo_update_start(Date))),
	fbo_get_update(Date, [XML|_]),
	format(atom(SaveXML), './fbofullxml/fbo_update_fixed_~w_~w_~w.xml', [Y,M,D]),
	open(SaveXML, write, XOut, []),
	xml_write(XOut, XML, []),
	close(XOut),
	debug(fbo_update, 'retrieved FBO update ~w', [XML]),
	process_fbo_update(date(Y,M,D),XML),
	log_message(info(fbo_update_complete(Date,XML))),
	update_fbo_date(Date).
	
process_fbo_update_old(date(Y,M,D)) :-
	Date = date(Y,M,D),
	fbo_update_date(Date0),
	subtract_days(Date0,date(Y,M,D),Days),
	(
		Days > 0,
		increment(fbo_update_new_data)
	;
		Days =< 0,
		increment(attempt_to_update_existing_data),
		log_messageF(warning('attempt to update duplicate fbo data')),
		fail
	),
	log_messageF(info(fbo_update_start(Date))),
	fbo_get_update(Date, [XML|_]),
	format(atom(SaveXML), 'fbo_update_fixed_~w_~w_~w.xml', [Y,M,D]),
	open(SaveXML, write, XOut, []),
	xml_write(XOut, XML, []),
	close(XOut),
	debug(fbo_update, 'retrieved FBO update ~w', [XML]),
	process_fbo_update(date(Y,M,D),XML),
	log_message(info(fbo_update_complete(Date,XML))),
	update_fbo_date(Date).


	
process_fbo_update(Date,element(Node0,Attr0,Sub)) :-
	XML = element(Node0,Attr0,Sub),
	failsafe(
		member(element(Notice,Attr,SubE), Sub),
	(
		xpath:xpath(SubE, //('SOLNBR'(text)), Sol0),
		replace(Sol0, '\n', '', Sol),		% was seeing \n's in solicitation. should be fixed upstream as this may be happening to other attributes as well
		debug(fbo_update, '~w Processing notice ~w for ~w\n',[Date,Node0,Sol]),
		increment(add_new_solicitation_via_update),
		get_time(Time0),
		new_node(Sol, solicitation, ['SOLNBR'=Sol]),
		findall(DownName=Value, (member(element(Attr000,_,[Value]), SubE), downcase_atom(Attr000,DownName)), Attrs),
		intersection([date=BadDate1, year=BadYear, url=URL], Attrs, _),
		atom_chars(BadDate1, [A,B,C,D|_]),
	    atom_chars(BadDate, [A,B,C,D]),
		format(atom(NewDate), '~w20~w', [BadDate,BadYear]),
		select(date=_, Attrs, Remaining),
		append(Remaining, [date=NewDate,time=Time0], AttrsGood),
%		\+ exists_notice(Notice,AttrsGood),
		new_node(NewNotice, [Notice,notice], AttrsGood),
		get_time(T0),
		new_node(Check, check, [type=file,solnbr=Sol,created=T0,status=pending]),
		log_messageF(info(created_notice,id(NewNotice))),
		new_edge(Rel, Sol, NewNotice, notice),
		increment_stat(new_notice_created)
	), Errors),
	log_messageF(warning('Errors during process_fbo_update',Errors)).
	
if_true(Cond,Goal) :- call(Cond), call(Goal).
if_true(Cond,Goal) :- \+ call(Cond).

exists_notice(Type, Attrs) :-
	intersection([solnbr=Sol,date=Date, year=Year], Attrs, _),
	var(Year),
	find_node_id1('MATCH (n:~w) where n.solnbr="~w" and n.date="~w" return id(n)', [Type,Sol,Date], Id).
exists_notice(Type, Attrs) :-
	intersection([solnbr=Sol,date=Date, year=Year], Attrs, _),
	nonvar(Year),
	atomic_list_concat([Date,'20',Year], D),
	find_node_id1('MATCH (n:~w) where n.solnbr="~w" and n.date="~w" return id(n)', [Type,Sol,D], Id).
	
user:delete_file_if_exists(File) :-
	exists_file(File),
	delete_file(File), !.
user:delete_file_if_exists(_).

user:must(X) :-
	must(X, '', []).
	
user:must(X,_Format,_Args) :-
	call(X), !.
user:must(X,Format,Args) :-
	format(atom(A), Format, Args),
	throw(must_exception(X,A)).
	
fbo_get_todays_update(XML) :-
	get_time(T),
	fbo_get_update(T, XML).
	
fbo_get_update(Date, XML) :-
	format_time(atom(A), '%Y%m%d', Date),
	format(atom(URL), 'ftp://ftp.fbo.gov/FBOFeed~w', [A]),
	debug(process_fbo_update, 'CURL... ~w', [URL]),
	curl_load_xml(URL, XML).

curl_load_xml(URL, XML) :-
	delete_file_if_exists('temp1.xml'),
	increment(curl_start),
	fshell('curl ~w --OUTPUT temp1.xml', [URL], Status),
	increment(curl_complete),
	must(Status = 0, 'Curl status non-zero: ~w',[Status]),
	exists_file('temp1.xml'),
	debug(fbo_update,'Downloaded FBO update ~w\n',[URL]),
	read_file_to_codes('temp1.xml', Codes, []),
	atom_codes(Atom0, Codes),
	debug(fbo_update,'Fixing update xml\n',[]),
%	split1(Atom0,Atom),
	increment(fbo_fix_start),
	fbo_fix(Atom0),
	increment(fbo_fix_end),
%	declare(Dec),
%	atomic_list_concat(['<?xml version="1.0" encoding="UTF-8"?>\n\n<fbo_files>\n',Dec,Atom,'\n</fbo_files>\n'], NewXML),
%	delete_file_if_exists('temp.xml'),
%	open('fbo_fix.xml', write, Wr, []),
%	write(Wr, NewXML),
%	close(Wr),
	debug(fbo_update,'Loading fixed xml\n',[]),
	increment(fbo_update_load_attempt),
	redirect_error( load_structure('fbo_fix.xml', XML, [max_errors(-1),dialect(xml)]), 'fbo_xml_error.txt'), 
	increment(fbo_xml_loaded),
	debug(fbo_update,'Fixed xml loaded\n',[]),
%	assert(fbo_update(XML)),
	!.
curl_load_xml(URL, XML) :-
	\+ exists_file('temp.xml'),
	format('unable to load ~w\n', [URL]),
	increment_stat(curl_unable_to_load),
	fail.

declare('<!DOCTYPE some_name [ \n<!ENTITY nbsp "&#160;"> \n]> ').

	
fix_xml(off, [H|T], In, Out) :-
	atom_code(A,H),
	A = '<',
	get_node([H|T], Node, Rest),
	fix_xml(Node, Rest, Out).
fix_xml(off, [H|T], In, Out) :-
	atom_code(A,H),
	A = '<',
	\+ get_node([H|T], Node, Rest),
	fix_xml([], T, Out).


	
fix0(TextIn, TextOut) :-
		fix(Before, Node, TextIn, TweenText, NextNode, RemainingText),
		atomic_list_concat([Before, Node, TweenText, EndNode, NextNode], TextOut).
		
test_fix :-
	fix0('qgdc <ABC> asdfasdf asdfasdfl;kj asdddasdf  fdsdfasdf  <DEF> adfasdfasdfasdfasdfasdf   <EFG>', Out).
		
fix(Before, Node, TextIn, TweenText, NextNode, RemainingText) :-
	atomic_list_concat([Before,T2|Rest], '<', TextIn),
	atomic_list_concat([Node,T3|Rest3], '>', T2),
	RR = [T3|Rest3],
	atomic_list_concat(RR, RRText),
	upcase_atom(Node,UpNode),
	Node=UpNode,
	format(atom(TheNode), '<~w>', [Node]),
	format(atom(AntiNode), '</~w>', [Node]),
	
%	fix(TweenText, NextNode, RRText, TweenText1, NextNextNode, RemainingText1).
		true.
		
fbo_fix(In) :-
	declare(Dec),
	flag(last_node, _, ''),
	delete_file_if_exists('fbo_fix.xml'),
	open('fbo_fix.xml',write,Wr,[]),
	format(Wr, '<?xml version="1.0" encoding="UTF-8"?>\n ~w\n<fbo_files>\n', [Dec]),
	atomic_list_concat(Lines, '\n', In),
	failsafe(
	  member(Line, Lines),
	 (
		once((atomic_list_concat([Node,Remain|T], '>', Line);Node='.NULL',Remain=Line,T=[])),
		atomic_list_concat([Remain|T], MinusNode),
		atom_chars(Node, [First,Second|NodeChars]),
		fix_node(Wr, First, Second, NodeChars, NodeName),
		(
			nonvar(NodeName),
			flag(last_node, _, NodeName),
			format(Wr, '~w', [MinusNode])
		;
			var(NodeName),
			format(Wr, '~w', [Line])
		)
	  ), Errors),
	  log_messageF(warning('Errors during fbo_fix: ',Errors)),
		format(Wr, '\n</fbo_files>\n',[]),
	close(Wr).
	
user:failsafe(Iter,Code,Errors) :-
% Iterate with backtracking. An error does not stop iteration. Errors are collected and provided back to caller at the end.
	findall(Error,
	(
		Iter,
		catch(Code,Error,true),
		nonvar(Error)
	), Errors).
	
good_nodes(['PRESOL','FAIROPP','AWARD','MOD','JA','SNOTE','FSTD','SRCSGT','COMBINE','ITB','ARCHIVE','UNARCHIVE','AMDCSS']).
	
fix_node(Str, '<', Second, Node1, Node) :-
	Second \= '/',
	char_type(Second, upper),
	atomic_list_concat([Second|Node1], Node),
	good_nodes(Good),
	flag(last_node, Last, Last),
	Last \= '',
	\+ member(Last, Good),
	format(Str,']]></~w><~w><![CDATA[',[Last,Node]), !.
fix_node(Str, '<', Second, Node1, Node) :-
	Second \= '/',
	char_type(Second, upper),
	atomic_list_concat([Second|Node1], Node),
	good_nodes(Good),
	flag(last_node, Last, Last),
	Last \= '',
	member(Last, Good), \+ member(Node, Good),
	format(Str,'<~w><![CDATA[',[Node]), !.
fix_node(Str, '<', Second, Node1, Node) :-
	Second \= '/',
	char_type(Second, upper),
	atomic_list_concat([Second|Node1], Node),
	good_nodes(Good),
	member(Node, Good),
	format(Str,'<~w>',[Node]),
	!.
fix_node(Str, '<', '/', Node1, Node) :-
	atomic_list_concat(Node1, Node),
	flag(last_node, Last, Last),
	format(Str,']]></~w></~w>',[Last,Node]),
	true, !.
fix_node(_, _, _, _, _).
		
make_node(start, In, start(Out)) :-
		atomic_list_concat(['<',In,'>'], Out).
make_node(end, In, end(Out)) :-
		atomic_list_concat(['</',In,'>'], Out).
		
		
test_fixit :-
	read_file_to_codes('temp1.xml', Codes, []),
	atom_codes(Atom, Codes),
	profile(split1(Atom, Out)).
	
split1(In, Out) :-
	trace,
%	read_file_to_codes('temp.xml', Codes, []),
%	atom_codes(Atom, Codes),
	replace(In, '\n', '', In1),
	atomic_list_concat(List, '<', In1),
	findall([Node1,Text],
	(
		member(E, List),
		(
			atomic_list_concat([Node,Text|_], '>', E)
		;
			\+ atomic_list_concat([Node,Text|_], '>', E),
			Node = '',
			Text = E
		),
		upcase_atom(Node,UpNode),
		once((
			atom_codes(Node, [47,First|Tail]),code_type(First,upper),atom_codes(Node2,[First|Tail]),Node1=end(Node2)
		;
			atom_codes(Node, NodeCodes),
			NodeCodes = [First|Tail],
			code_type(First, upper),
			Node1=start(Node)
		;
			Node1 = Node
		))
	), List1),
	flatten(List1,List0),
	findall(end(Node), member(end(Node), List0), EndNodes),
	findall(start(Node), member(start(Node), List0), StartNodes),
	fixup1(List0,Lista),
	once(fixup(Lista, EndNodes, List2)),
	flatten(List2,List3),
	tell('temp.txt'),
	format('~w\n~w\n~w\n',[Lista,EndNodes,StartNodes]),
	told,
	atomic_list_concat(List3, Out),
%	open('out.txt',write, Wr, []),
%	format(Wr, '~w', [OutText]),
%	close(Wr),
	true, !.
	
fixup([start('EMAIL'),_,start('EMAIL'),Text|Tail], EndNodes, ['<EMAIL>',Text,'</EMAIL>'|Tail1]) :-
	fixup(Tail, EndNodes,Tail1).
fixup([start(Node1),Text,start(Node2)|Tail], EndNodes, ['<',Node1,'>',Text1,'</',Node1,'>'|Tail1]) :-
	cdata(Text,Text1),
	\+ member(end(Node1), EndNodes),
	fixup([start(Node2)|Tail], EndNodes,Tail1).
fixup([start(Node1),Text,start(Node2)|Tail], EndNodes, ['<',Node1,'>',Text1|Tail1]) :-
	cdata(Text,Text1),
	member(end(Node1), EndNodes),
	fixup([start(Node2)|Tail], EndNodes,Tail1).
fixup([start(Node1),Text,end(Node2)|Tail], EndNodes, ['<',Node1,'>',Text1,'</',Node1,'>'|Tail1]) :-
	cdata(Text,Text1),
	\+ member(end(Node1), EndNodes),
	fixup([end(Node2)|Tail], EndNodes,Tail1).
fixup([start(Node1),Text,end(Node2)|Tail], EndNodes, ['<',Node1,'>',Text1|Tail1]) :-
	cdata(Text,Text1),
	member(end(Node1), EndNodes),
	fixup([end(Node2)|Tail], EndNodes,Tail1).
fixup([H|T], EndNodes, [H|T1]) :-
	atomic(H),
	fixup(T, EndNodes, T1).
fixup([end(Node)|T], EndNodes, ['</',Node,'>'|T1]) :-
	fixup(T, EndNodes, T1).
fixup([], _,[]).

fixup(A, _, [Text]) :-
	format(atom(Text),'<<<fail on ~w>>>\n',[A]).
	
fixup1([H|T], [H|T1]) :-
		compound(H),
		fixup1(T,T1).
fixup1([H|T], [Text|T1]) :-
		atomic(H),
		split_list([H|T], compound, Before, After),
		atomic_list_concat(Before, Text),
		fixup1(After,T1).
fixup1([],[]).

split_list([H|T], Goal, [H|BT], AT) :-
	\+ call(Goal,H),
	split_list(T, Goal, BT, AT).

split_list([H|T], Goal, [], [H|T]) :-
	call(Goal,H).
	
split_list([], _, [], []).

cdata(In, Out) :-
	atomic_list_concat(['<![CDATA[',In,']]>'], Out).
	
back(Goal) :-
	thread_create(exec:back1(Goal), Id, []).

back1(Goal) :-
		call(Goal),
		thread_exit(Goal).
		
%%% Various Data correction tools

user:delete_class(Class) :-
	fcypher_query('match (n:~w) optional match (n)-[r]-() delete n,r ',[Class],Response,[]),
	format('operation complete, response: ~w\n',[Response]).
		
check_dups :-
	delete_duplicates(check,'MATCH (n:`check`{status:"pending", type:"file"}) RETURN id(n),n.solnbr',[]). 
	
check_dup_files :-
	check_duplicates('MATCH (n:`file`) RETURN id(n),n.absolute_filename',[]).
delete_dup_files :-
	delete_duplicates(file,'MATCH (n:`file`) RETURN id(n),n.absolute_filename',[]).
	
check_duplicates(Query,Args) :-
	findall(Id-Tail, fcypher_query(Query,Args,row([Id|Tail])), List), 
	check_duplicates(List).
	
delete_duplicates(Type,Query,Args) :-
	findall(Id-Tail, fcypher_query(Query,Args,row([Id|Tail])), List), 
	delete_duplicates(Type,List).

check_duplicates(Sols) :-
	findall(Data, member(Id-Data, Sols), AllData),
	length(AllData, SLen), 
	list_to_set(AllData, Set), 
	length(Set, SetLen),
	Delta is SLen - SetLen,
	format('Total ~w unique ~w duplicates ~w',[SLen,SetLen,Delta]).
	
delete_duplicates(Type,Sols) :-
	fcypher_query('match (n:~w)-[r]-() where n.status="delete" delete n,r',[Type],_Reply),
	fcypher_query('match (n:~w) where n.status="delete" delete n',[Type],_Reply),
	findall(Data, member(Id-Data, Sols), AllData),
	length(AllData, SLen), 
	list_to_set(AllData, Set), 
	length(Set, SetLen),
	Delta is SLen - SetLen,
	(
		member(Data, Set),
		once(member(Id0-Data, Sols)),
		(
			member(Id-Data, Sols),
			Id\=Id0,
			gephi:set_property(neo4j, Id, status, delete), 
%			del_node(Id),
		fail;true
		),
	fail;true
	),
	format('~w duplicates marked for deletion\n',[Delta]),
	fcypher_query('match (n:~w)-[r]-() where n.status="delete" delete n,r',[Type],_Reply),
	fcypher_query('match (n:~w) where n.status="delete" delete n',[Type],_Reply),
	format('delete: ~w\n',[Reply]).
	
%% Add nodes+relationships that model properties to allow graph analysis. E.g. Zip code as a property becomes a node that represents the zip code and an edge connecting to it

test(property_graph) :-
	property_graph('notice','zip').
	
naics :-
	property_graph('notice','naics').
	
% match (n:notice) where n.naics="null" remove n.naics return count(n)
% match (s:notice) where (has (s.naics)) match (x:naics {id:s.naics}) return s,x
% match (s:notice) where (has (s.naics)) match (x:naics {id:s.naics}) return s,x limit 2

property_graph(Type, Property) :-
	fcypher_query('match (s:~w) where s.~w="null" remove s.~w return count(s)', [Type,Property,Property], _Reply, [background1]),
	fcypher_query('match (s:~w) where (has (s.~w)) merge (:~w {id:s.~w,title:s.~w}) return s;', [Type,Property,Property,Property,Property], _Reply, [background1]),
	fcypher_query('match (s:~w) where (has (s.~w)) match (x:~w {id:s.~w})  merge p=(s)-[r:~w]->(x) return p;', [Type,Property,Property,Property,Property,Property], _Reply, [background1]),
	true.
	
property_graph_nodes(Type, Property) :-
	fcypher_query('match (s:~w) where (has (s.~w)) merge (:~w {id:s.~w,title:s.~w}) return s;', [Type,Property,Property,Property,Property], _Reply, [background1]),
%	format('query executed, results: ~w\n',[Reply]),
	true.
property_graph_edges(Type, Property) :-
	fcypher_query('match (s:~w) where (has (s.~w)) match (x:~w {id:s.~w})  merge p=(s)-[r:~w]->(x) return p;', [Type,Property,Property,Property,Property,Property], _Reply, [background]),
%	format('query executed, results: ~w\n',[Reply]),
	true.	
	
user:bind(Var,Var).
user:bind(Var,Val) :- Var\=Val.

property_graph1(Class,Property,Options) :-
	intersection([exclude=Exclude],Options,_),
	bind(Exclude,[]),
	findall(Value,
	fcypher_query('match (x:~w) where (has (x.~w)) return x.~w',[Class,Property,Property],row([Value])),
	ValueList),
	list_to_set(ValueList, ValueSet),
	length(ValueList, Len1),
	length(ValueSet, Len2),
	format('len1 ~w len2 ~w \n',[Len1,Len2]),
	(
		nth1(Index, ValueSet, Value),
		\+member(Value,Exclude),
		format('linking ~w of ~w: (~w)\n',[Index,Len2,Value]),
		fcypher_query('match (x1:~w {~w:"~w"}) merge (x2:~w {id:"~w",title:"~w"}) merge (x1)-[r:~w]-(x2)',[Class,Property,Value,Property,Value,Property,Property],_),
	fail;true
	).
	
	
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% DL Exec %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

dl_exec_main :-
	increment_stat(run),
	process_check(file, pending, delete, error, exec:dl_exec1).

log_messageF(Term) :-
    format('log: ~w',[Term]).
	
dl_exec1(Id) :-
	increment(run),
	(
		fcypher_query('match (ck:check) where id(ck)=~w return ck.solnbr', [Id], row([Solicitation0])),
		once((
		increment(new_file_ck),
		replace(Solicitation0, '\n', '',Solicitation),
		log_messageF(info(dl_exec,Solicitation)),
		get_time(T0),
		new_node(_, check, [type=download,status=pending,priority=p1,solnbr=Solicitation,created=T0]),
		increment(new_file_ck_complete)))
	).
		
dl_exec_main1 :-
	increment(run),
	(
		fcypher_query('match (ck:check {type: "file"}) return ck.solnbr,id(ck)', [], row([Solicitation0,Ck])),
		once((
		increment(new_file_ck),
		replace(Solicitation0, '\n', '',Solicitation),
		log_messageF(info(dl_exec,Solicitation)),
		get_time(T0),
		new_node(_, check, [type=download,status=pending,priority=p1,solnbr=Solicitation,created=T0]),
		gephi:del_node(Ck),
		increment(new_file_ck_complete))),
	fail;true).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Backup Exec %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

backup_exec_main :-
	increment(run),
	get_time(T),
	increment(backup_started),
	
	% create backup
	% 
	todays_date(date(Y,M,D)),
	format(atom(Dir), 'f:\\backups\\~w~w~w_backup', [Y,M,D]),
	(
		\+ exists_directory(Dir),
		fshell('mkdir ~w', [Dir],_),
		Host = localhost,
		fshell('.\\neo4j-enterprise-2.1.6\\bin\\neo4jbackup.bat -full -host ~w -to ~w ',[Host, Dir],Result),
		must(Result=0,'Backup exec status nonzero: ~w',[Result]),
		get_time(T1),
		increment(backup_complete),
		Delta is T1-T,
		na(backup(start_time=T,end_time=T1,backkup_duration=Delta))
	;
		exists_directory(Dir), increment(backup_already_exists)),
	true.
	
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% FCAT Exec %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fcat_exec_main1 :-
		increment_stat(run),
	(
		fcypher_query('match (ck:check {type: "fcat"}) return ck.filename,id(ck)', [], row([File,Ck])),
		once((
		increment(new_fcat_ck),
		log_messageF(info(fcat_exec,File)),
		fedbizopps:fcat_analyze_file(File),
		get_time(T0),
		new_node(_, check, [type=gate,priority=p1,filename=File,created=T0,status=pending]),
		gephi:del_node(Ck),
		increment(new_fcat_ck_complete))),
	fail;true).
	
fcat_exec_main :-
	increment_stat(run),
	process_check(fcat, pending, delete, error, exec:fcat_exec1).

fcat_exec1(Id) :-
		fcypher_query('match (ck:check) where id(ck)=~w return ck.filename', [Id], row([File])),
		once((
		increment(new_fcat_ck),
		log_messageF(info(fcat_exec,File)),
		fedbizopps:fcat_analyze_file(File),
		get_time(T0),
		new_node(_, check, [type=gate,status=pending,priority=p1,filename=File,created=T0]),
		increment(new_fcat_ck_complete))).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% GATE Exec %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
gate_exec_main :-
	increment_stat(run),
	process_check(gate, pending, delete, error, exec:gate_exec1, [max_per_day=950]).

max_alchemy_calls(950).
	
gate_exec_main1 :-
		increment(run),
	(
	% TODO - order by priority not working for some stupid reason. Need to reintroduce feature 
%		fcypher_query('match (ck:check {type: "gate"}) return ck.filename,id(ck) order by ck.priority ', [], row([File,Ck])),
		fcypher_query('match (ck:check {type: "gate"}) return ck.filename,id(ck)  ', [], row([File,Ck])),
		todays_date(Today),
		tflag(gate-Today, Inc, Inc+1),
		max_alchemy_calls(MaxAlchemy),
		Inc < MaxAlchemy,								
		increment(processing_check),
		once((
		increment_stat(gate_process_check),
		log_messageF(info(gate_exec,File)),
		fedbizopps:mine_file(File,_,_),
		gephi:del_node(Ck),
		increment_stat(gate_check_completed))),

	fail;true).
	
gate_exec1(Id) :-
	% TODO - order by priority not working for some stupid reason. Need to reintroduce feature 
		fcypher_query('match (ck:check) where id(ck)=~w return ck.filename  ', [Id], row([File])),
		increment(processing_check),
		once((
		increment_stat(gate_process_check),
		log_messageF(info(gate_exec,File)),
		fedbizopps:mine_file(File,_,_),
		increment_stat(gate_check_completed))).
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Health Exec %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Xmind Exec %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
xmind_exec_main :-
		increment(run),
	(
	% TODO - order by priority not working for some stupid reason. Need to reintroduce feature 
		xmind:process_xmind_files,
	fail;true).
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Health Exec %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

/*

The job of the health exec is to monitor overall activities, determine if problems exist, attempt to automatically fix problems and notify admin if needed

1) Check status of all execs
	- Make sure they are alive
	- Ascertain if they are stuck on something
	- Check on activiy throughput. Is it reasonable.
	
2) Check system resources
	- Memory, disk space, etc.
	- Any trouble on the horizon?

Exec states

stopped -> attempt_restart -> restart_failed -> notify admin
	
*/

:- dynamic(state/3).
	
executive_list([fbo_update, dl_exec, fcat_exec, gate_exec, defer_exec]).
	
health_exec_main :-
	(
		heartbeat,
		check_thread_health,
		restart_process,
	fail;true).

heartbeat :-
	increment(heartbeat),
	log_messageF(info(heartbeat)).
	
check_thread_health :-
	increment(check_thread_health),
	exec_stopped(Exec),
	increment(exec_stopped),
	state(Exec, running),
	restart(Exec),
	fail.
check_thread_health.

restart_process :-
	increment(restart_process),
	state(Exec, restarting, Data),
	intersection([time=T],Data,_),
	must(nonvar(T),'restart process',[]),
	get_time(Now),
	D is Now-T,
	D < 60, 
	!.
restart_process :-
	state(Exec, restarting, Data),
	intersection([time=T],Data,_),
	get_time(Now),
	D is round(Now-T),
	notify(admin,'Health exec states executive ~w has been dead for ~w seconds\n',[Exec,D]),
	increment(exec_died),
	set_state(Exec, dead).
	

restart(Exec) :-
	increment(restart_exec),
	set_state(Exec, restarting),
	thread_join(Exec, _),
	call(Exec).
		
exec_stopped(Exec) :-
	executive_list(Execs),
	member(Exec, Execs),
	safe_thread_status(Exec, Status),
	Status \= running,
	Status \= nonexistant.
	
reassert(A,B) :-
	retractall(A),
	assert(B).
	
safe_thread_status(Thread, S) :-
		catch( thread_property(Thread, status(S)), _Error, S=nonexistant).
	
state(E,S) :- state(E,S,_).

set_state(Exec, State) :-
	get_time(Time),
	reassert(state(Exec, _, _), state(Exec, State, [start=Time])).
	
user:notify(Who, Format, Args) :-
	format(atom(Message), Format, Args),
	log_messageF(notify(Message)).
	
:- dynamic(stat/2).
	
user:report_state :-
	thread_self(Self),
	report_state(Self).
user:report_state(Exec) :-
	state(Exec, State, Data),
	intersection([start=Start],Data,_),
	get_time(Now),
	D is round(Now-Start),
	format_delta_time(D, DText),
	format('\t\tExecutive ~w has been in state ~w for ~w\n',[Exec,State,DText]), 
	safe_thread_status(Exec, Status),
	format('\t\tExecutive ~w has status ~w\n',[Exec, Status]), 	
	!.
user:report_state(_).

format_delta_time(Time,String) :-
	Time < 60,
	T is round(Time),
	format(atom(String), '~w seconds', [T]), !.
format_delta_time(Time,String) :-
	Time < 60*60,
	T is round(Time/60.0),
	format(atom(String), '~w minutes', [T]), !.
format_delta_time(Time,String) :-
	Time < 60*60*24,
	T is round(Time/(60.0*60.0)),
	format(atom(String), '~w hours', [T]), !.
format_delta_time(Time,String) :-
	Time > 60*60*24,
	T is round(Time/(60.0*60.0*24.0)),
	format(atom(String), '~w days', [T]), !.
format_delta_time(T,T) :-
	T is round(Time),
	format(atom(String), '~w seconds', [T]), !.

user:report_stats :- report_stats(keep).
user:report_stats(Flag) :-
	findall(stat(Thread,Stat), stat(Thread,Stat), Stats),
	findall(Thread, stat(Thread,_), Threads),
	list_to_set(Threads, ThreadSet),
	(
		member(Thread, ThreadSet),
		format('Thread statistics for ~w:\n',[Thread]),
		report_state(Thread),
		(
			member(stat(Thread,Stat),Stats),
			(Flag=reset,cflag(Thread-Stat,Value,0);Flag=keep,cflag(Thread-Stat,Value,Value)),
			format('\t\t~w:\t\t~w\n',[Stat,Value]),
		fail;true
		),
	fail;true
	).
	
user:increment(Exec,Stat) :-
	cflag(Exec-Stat,X,X+1).
	
user:increment(X) :- increment_stat(X).
user:increment_stat(Stat) :-
	thread_self(Self),
	add_stat(Stat),
	tflag(Stat,X,X+1).
	
user:add_stat(Stat) :-
	thread_self(Self),
	\+stat(Self,Stat),
	assert(stat(Self,Stat)), !.
user:add_stat(Stat) :-
	thread_self(Self),
	stat(Self,Stat).
	
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  SMS Messaging %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

/*

curl -X POST 'https://api.twilio.com/2010-04-01/Accounts/AC38bf41ea2f49557f0eba907ef93333a9/Messages.xml' \
--data-urlencode 'To=8182718170'  \
--data-urlencode 'From=+18182736351'  \
--data-urlencode 'Body=Test message' \
-u AC38bf41ea2f49557f0eba907ef93333a9:[AuthToken]

*/
user:sms_text(Message) :- sms_text('18182718170',Message).

user:sms_text(To,Message) :-
	sms_text('18182736351',To,Message).
	
user:sms_text(From,To,Message) :-
	fshell('~w --data-urlencode "To=~w" --data-urlencode "From=~w" --data-urlencode "Body=~w" ~w', 
	[
		'curl -X POST https://api.twilio.com/2010-04-01/Accounts/AC38bf41ea2f49557f0eba907ef93333a9/Messages.xml' ,
		To,
		From,
		Message,
		'-u AC38bf41ea2f49557f0eba907ef93333a9:724634fae82746a0175c8435b0310e03'
	],
	Status).
	
xxxdownload_file(Link,File) :-
%	URL = 'https://api.twilio.com/2010-04-01/Accounts/AC38bf41ea2f49557f0eba907ef93333a9/Messages.xml' ,
%	http_open(Link, Str, [cert_verify_hook(user:cert_verify)]), 
%	read_stream_to_codes(Str, Codes), 
%	atom_codes(Reply, Codes).
http_open(URL, Str,  [cert_verify_hook(user:cert_verify),
            search([ 'Body'='Hello world', 'From'=f, 'To'=t, 
                     lang=en
                   ])
          ]).
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Deferred Link Exec %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% This executive periodically scans for deferred links and creates the linkage.
%	match (node) where has (node.defer_link_to__) return id(node),node.defer_link_to__ limit 25
defer_exec_main :-
	(
		increment_stat(run),
		fcypher_query('match (node) where has (node.defer_link_to__) return id(node),node.defer_link_to__', [], row([Node,Link])),
		create_deferred_link(Node,Link),
		increment(defer_request),
		log_messageF(info(resolved_link,Link)),
		% remove property
		gephi:del_property(neo4j, Node, defer_link_to__),
		increment(defer_exec, defer_complete),
	fail;true).
	
create_deferred_link(Node,Link) :-
	atomic_list_concat([Expr,Dir,Type|_], ';', Link),
	create_deferred_link(Node,Expr,Dir,Type).
	
create_deferred_link(Node,Expr,from,Type) :-
	find_node_id1('match (n:~w) return n', [Expr], Id),
	new_edge(_, Id, Node, Type).
create_deferred_link(Node,Expr,to,Type) :-
	find_node_id1('match (n:~w) return id(n)', [], Id),
	new_edge(_, Node, Id, Type).

	
user:fbo_update :- start_exec(fbo_update), thread_send_message(fbo_update,periodic(process_fbo_updates,minutes(1))), thread_send_message(fbo_update,periodic(process_fbo_updates1,minutes(1))).
user:dl_exec :- start_exec(dl_exec), thread_send_message(dl_exec, periodic(dl_exec_main,minutes(1))).
user:fcat_exec :- start_exec(fcat_exec), thread_send_message(fcat_exec, periodic(fcat_exec_main,seconds(1))).
user:gate_exec :- start_exec(gate_exec), thread_send_message(gate_exec, periodic(gate_exec_main,minutes(1))).
user:defer_exec :- start_exec(defer_exec), thread_send_message(defer_exec, periodic(defer_exec_main,minutes(1))).
user:health_exec :- start_exec(health_exec), thread_send_message(health_exec, periodic(health_exec_main,minutes(1))).
user:backup_exec :- start_exec(backup_exec), thread_send_message(backup_exec, periodic(backup_exec_main,days(1))).
user:xmind_exec :- start_exec(xmind_exec), thread_send_message(xmind_exec, periodic(xmind_exec_main,seconds(30))).
user:fboval_exec :- start_exec(fboval_exec), thread_send_message(fboval_exec, periodic(check_missing_notices,days(7))).

start_execs :- fbo_update, dl_exec, fcat_exec, gate_exec, defer_exec, heath_exec.
kill_execs :-
	findall(Thread, stat(Thread,_Stat), Threads),		% This assume the statistics feature is being used by all execs. Should be ok but keep in mind.
	list_to_set(Threads, ExecSet),
	(
		member(Exec, ExecSet),
		Exec \= main,
		thread_signal(Exec, thread_exit(terminated_on_demand)),
	fail;true).

