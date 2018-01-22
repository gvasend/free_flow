:- module(util,[]).

:- dynamic(log_file/1).
user:init_log :-
	absolute_file_name('log.pl', Abs),
	retractall(log_file(_)),
	assert(log_file(Abs)).
:- init_log.


:- dynamic(log_filter/1).

set_log_filter(Filter) :-
	retractall(log_filter(_)),
	assert(log_filter(Filter)).

:- set_log_filter([error,warning]).
	
user:log_message(Term) :-
	debug(log_message, '~w', [Term]),
	Term =.. [Type|_],
	log_filter(Filter),
	member(Type, Filter),
	thread_self(Thread),
	get_time(Time),
	log_file(File),
	open(File, append, Str, []),
	write_term(Str, entry(Thread,Time,Term), [quoted(true)]),
	format(Str, '.\n',[]),
	close(Str), !.
user:log_message(_).
user:log_messageF(Term) :-
	debug(log_message, '~w', [Term]),
	Term =.. [Type|_],
	log_filter(Filter),
	member(Type, Filter),
	thread_self(Thread),
	get_time(Time),
	log_file(File),
	open(File, append, Str, []),
	format_time(atom(FTime), '%FT%T', Time),
	write_term(Str, entry(Thread,time(Time,FTime),Term), [quoted(true)]),
	format(Str, '.\n',[]),
	close(Str), !.
user:log_messageF(_).