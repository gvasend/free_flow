
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

user:increment(_).
user:must(X) :- call(X).


:- debug(log_message).
:- dynamic(user:home_dir/1).
:- working_directory(Dir,Dir), assert(user:home_dir('/home/gvasend/nfs/Simbolika/fedbiz/')).
user:abs_file(In,Out) :-
	user:home_dir(Dir),
	atom_codes(In, [_,_|T]),
	atom_codes(In1, T),
	atom_concat(Dir,In1,Out),
	log_messageF(abs_file_xlate(In,Out)).

user:set_home(Dir) :-
    retractall(home_dir(_)),
    assert(home_dir(Dir)).

:- use_module(graph_lib).
:- use_module(library(http/http_ssl_plugin)).
:- use_module(library(http/http_open)).
:- use_module(library(sgml)).
:- use_module(library(sgml_write)).
:- use_module(util).
:- use_module(argparse).

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


		

user:throwF(Format, Args) :-
	format(atom(Atom), Format, Args),
	throw(Atom).


make_dir_if_not(Dir) :-
	\+ exists_directory(Dir),
	make_directory(Dir).
make_dir_if_not(Dir) :-
	exists_directory(Dir).



	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Download Manager %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


/*

The download manager has the responsibility to manage downloading solicitation files. A download is requested by placing a solicitation in the queue which
is eventually read and process by the download manager.

*/


download_window([window(1-5,0,8,20.0),window(1-5,20,23.9,30.0),window(1-5,8,20,300.0),window(6-7,0,24,10.0)]).
max_download(1000000,60.0).


	
get_solicitation_folders(List) :-
	working_directory(Old,'./Files'),
	expand_file_name('*', List),
	working_directory(_,Old),
	true.

create_download_queue(ProcessDate) :-
    working_directory(OldDir,'/home/gvasend/nfs/Simbolika/fedbiz'),
	gephi:set_neo_mode(instant),
	add_graph_dest(neo4j),
% Create a download queue that consists of each solicitation that has a document_package (should mean it has files)
% There are lots of directories with no files. Need to figure out why.
    findall(SOL, 
        fcypher_query('MATCH (n:DATE {iname:"~w"})-[]-(:FBO_Announcement)-[]-(s:SOLNBR)  RETURN distinct s.iname', [ProcessDate], row([SOL])),
        SolList),
	list_to_set(SolList, SolSet),
    format('solset:~w\n',[SolSet]),
	get_solicitation_folders(Folders),
	subtract(SolSet, Folders, DLSet),
	length(SolSet, SolSetN),
	length(Folders, FoldersN),
	length(DLSet, DLSetN),
	log_messageF(info(create_dlq,SolSetN,FoldersN,DLSetN)),
    dl_priority(ProcessDate,Pri),
	(
		member(S, SolSet),
		get_time(T0),
		atom_concat(S, download, Iname),
		new_node(Iname, check, [type=download,priority=Pri, date=ProcessDate,solnbr=S,time=T0,status=pending]),
	fail;true
	),
	true.

dl_priority(Date,Pri) :-
    sub_string(Date, 0, 2, _, Month),
    sub_string(Date, 2, 2, _, Day),
    sub_string(Date, 4, 4, _, Year),
    format(atom(Atom), '~w-~w-~w', [Year,Month,Day]),
	parse_time(Atom, _, TimeStamp),
    get_time(Now),
    Delta is Now-TimeStamp,
    Ratio is round(Delta/(86400*30)),
    format(atom(Pri), 'p~w', [Ratio]), !.
    
dl_priority(_,p3).
	

	

	
	
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
	
replace(In, From, To, Out) :-
    atomic_list_concat(List, From, In),
    atomic_list_concat(List, To, Out).

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

:- argparse:add_argument('--ts',[default='*run_id',required=True,help='Date being processed']).
		

run :- 
    argparse:argparse, 
    argparse:argument_value('ts',IsoDate),
    atomic_list_concat([IsoDate1|_],'T', IsoDate),
    atomic_list_concat([Year,Month,Day], '-', IsoDate1),
    atomic_list_concat([Month,Day,Year], Date),
    log_message(info(IsoDate1,Date)),
    create_download_queue(Date), 
    halt(0).

run :- halt(11).

:- debug([match,keyword]).
	
:- run.

