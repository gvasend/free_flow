:- module(default_xmind_styles,[]).

%% default_xmind_style ( +Attribs, +Node type, -InterimAttr )
%
%  find default set of render attributes based on node type 
%  this needs to be in some kind of config file	


/*

filename=xxx

link=format_url('http://simbolika.ddns.net:57800/xxx?cmd=open_file', [filename])

link=http://simbolika.ddns.net:57800/xxx?cmd=open_file

*/
	
default_xmind_style(_Attribs, file, [title=format_text('~w: ~w',[label,filename]),link=serve_file(absolute_filename)]).
default_xmind_style(_Attribs, notice, [title=format_text('~w: ~w',[label,first([subject,desc])]),notes=concat([subject,desc])]).
default_xmind_style(_Attribs, 'PRESOL', [title=format_text('~w: ~w',['Presolicitation Notice',first([subject,desc])]),notes=concat([subject,desc])]).

default_xmind_style(Attribs, _, [title=label|Attribs]) :-
	\+ member(title=_, Attribs),
	true.
default_xmind_style(Attribs, _, [title=format_text('~w: ~w',[label,title])]) :-
	member(title=_, Attribs),
	true.	
xmind:serve_file(Filename, URL) :-
	atomic_list_concat([_,Filename1|_], ':', Filename),
	format(atom(URL), 'http://search-links.simbolika.com/~w?cmd=open', [Filename1]).
	
xmind:format_text(Format, Arguments, Text) :-
	format(atom(Text), Format, Arguments).

xmind:concat(List, Value) :-
	atomic_list_concat(List, '\\n', Value).
	
xmind:first(List, Value) :-
	member(Value, List),
	Value \= null, !.