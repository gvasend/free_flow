:- module(watch,[]).
    
:- use_module(library(socket)).
  
receive(Port) :-   
        udp_socket(Socket),
        tcp_bind(Socket, Port), 
		format('starting udp receive loop\n',[]),
%		listen(file_event(From,Data), format('received ~w from ~w\n',[Data,From])),
        repeat, 
            udp_receive(Socket, Data, From, [as(atom)]),
			broadcast(file_event(From,Data)),
            fail.

run :-	 		
	current_prolog_flag(argv, [send,Arg2|_]),
	format('sending ~w\n',[Arg2]),
	format(atom(A), '', [L]),
	send(localhost, 8887, Arg2), 
	halt.
run1 :-
	\+ current_prolog_flag(argv, [send,Arg2|_]),
	watch('*.xmind;'), !.
run.
	
watch(X) :-
	thread_create(receive(8887), _, []),
	format(atom(Atom), 'watch2.bat ~w', [X]),
	win_exec(Atom,hide).
	
 
send(Host, Port, Message) :-
        udp_socket(S),
        udp_send(S, Message, Host:Port, []),
        tcp_close_socket(S).
			
:- run.