 
 :- module(graph, []).

:- use_module(library(xpath)).
 :- use_module(library('http/json')).
 

 :- dynamic(node/3).
 :- dynamic(edge/5).
 :- dynamic(key/4).
 :- dynamic(graph_xml/2).
 
replace(In, From, To, Out) :-
    atomic_list_concat(L, From, In),
    atomic_list_concat(L, To, Out).

value_type(In, string, In).
value_type(In, Type, Out) :-
    member(Type, [int, integer, float, real]),
    atom_number(In, Out).
value_type(In, _, In).
    
xml_node(XML, Id, Label, Attrs) :-
    xpath:xpath(XML, //node(@id=Id), Node),
    findall(Key=Value1,
        (xpath:xpath(Node, //data(@key=AttrId), element(data, _, [Value])), 
         xml_key(XML, Key, Type, node, AttrId), 
         once(value_type(Value, Type, Value1))),
    Attrs1),
    (
        select(label=Label, Attrs1, Attrs)
    ;
        \+ member(label=_, Attrs1),
        Label = null_pl,
        Attrs = Attrs1
    ).

xml_edge(XML, Id, From, To, Label, Attrs) :-
    xpath:xpath(XML, //edge(@source=From,@target=To), Edge),
    findall(Key=Value1,
        (xpath:xpath(Edge, //data(@key=AttrId), element(data, _, [Value])), 
         xml_key(XML, Key, Type, edge, AttrId),
         once(value_type(Value, Type, Value1))
         ),
    Attrs1),
    gen_id(Id),
    (
        select(label=Label, Attrs1, Attrs)
    ;
        \+ member(label=_, Attrs1),
        Label = null_pl,
        Attrs = Attrs1
    ).
 
 

user:new_edge(Id,From,To,Label,Attr) :-
%    format('make new edge ~w\n',[new_edge(Id,From,To,Label,Attr)]),
    (
        nonvar(Id),
        \+ edge(Id, _, _, _, _),
        From \= To,
%        format('new edge with Id ~w\n',[new_edge(Id,From,To,Label,Attr)]),

        assert(edge(Id,From,To,Label,Attr))
    ;
        var(Id),
        \+ edge(_, From, To, Label, Attr),
        gen_id(Id),
        From \= To,
%        format('new edge, auto gen id ~w\n',[new_edge(Id,From,To,Label,Attr)]),

        assert(edge(Id,From,To,Label,Attr))
    ;
        var(Id),
        edge(Id,From,To,Label,Attr)
%        listing(edge/5),
%        format('edge record exists ~w\n',[edge(Id,From,To,Label,Attr)])
    ;
        nonvar(Id),
        edge(Id, _, _, _, _)
%        ,format('edge Id exists already\n',[])
    ), 
    !.
user:new_edge(Id, From, To, Label, Attr) :- format('new edge fail ~w\n',[new_edge(Id, From, To, Label, Attr)]).

user:delete_node_property(Id, Label, Prop) :-
    (
      node(Id, Label, Props),
      select(Prop=_, Props, NewProps),
      retractall(node(Id, Label, _)),
      assert(node(Id, Label, NewProps)),
    fail;true).

add_node_attributes(Id, Attr) :-
    nonvar(Id),
    node(Id, Label, Attr1),
    retractall(node(Id, Label, _)),
    append(Attr, Attr1, AllAttr),
    assert(node(Id, Label, AllAttr)), !.
add_node_attributes(_, _).

    
user:new_node(Id, Label, Attr) :-
    format('~w\n',[new_node(Id, Label, Attr)] ),
    (
        nonvar(Id),
        \+ node(Id,_,_),
%        format('new node ~w\n',[node(Id, Label, Attr)]),
        assert(node(Id, Label, Attr))
    ;
        var(Id),
        gen_id(Id),
%        format('new node ~w\n',[node(Id, Label, Attr)]),
        assert(node(Id, Label, Attr))
    ;
        nonvar(Id),
        node(Id,_,_)
    ).

gen_id(Id) :-
    var(Id),
	uuid(Id,[version(1)]).

gen_id(Id) :- ground(Id).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    
attr_type(X,string) :-
    atom(X), !.
attr_type(X,integer) :-
    integer(X), !.
attr_type(X,float) :-
    float(X), !.
attr_type(X, string).

% <key attr.name="seq" attr.type="long" for="node" id="d0" />

% lookup gramphml key. if it does not exist create a staging fact for the new key. must be merged with XML on write

add_keys :-
    add_keys(node),
    add_keys(edge).

add_keys(NType) :-
    (
        (
          NType = 'node',
          node(_, _, Attr)
        ;
          NType = edge,
          edge(_,_,_,_,Attr)
        ),
        member(Key=Val, [label=xxx|Attr]),
        attr_type(Val, Type),
        \+ key(Key, Type, NType, Id),
        gen_keyname(NewId),
        assert(key(Key, Type, NType, NewId)),
    fail;true
    ).

user:gramphml_node_attr(XML, Label, Key, Value) :-
    format('searching type ~w for ~w\n',[Label,Key]),
    graphml_key(XML, Key, _, _, AttrId),
    graphml_key(XML, label, _, _, LabelId),
    format('found keys label ~w attr ~w\n',[LabelId,AttrId]),
    xpath:xpath(XML, //node(@id=NodeId)/data(@key=LabelId), element(data,_,[Label])),
    xpath:xpath(XML, //node(@id=NodeId)/data(@key=AttrId), element(data,_,[Value])),
    format('found ~w ~w=~w\n',[Label, Key, '...']).

user:graphml_key(XML, Key, Id) :-
   graphml_key(XML, Key, string, node, Id).

   
user:graphml_key(XML, Key, Type, For, Id) :-
   key(Key, Type, For, Id),
%   format('found local key ~w\n',[key(Key,Type,For,Id)]), 
   !.
   
gen_keyname(Name) :-
    repeat,
    gensym(x, Name),
    \+ key(_, _, _, Name), !.
   
user:graphml_key(XML, Key, Type, For, Id) :-
\+ key(Key, Type, For, Id),
   nonvar(Key),
   nonvar(Type),
   var(Id),
   gen_keyname(Id),
   format('generate new key ~w\n',[key(Key,Type,For,Id)]),
   assert(key(Key, Type, For, Id)), !.

   
xml_key(XML, Key, Type, For, Id) :-
    nonvar(XML),
    xpath:xpath(XML, //key(@'attr.name'=Key,@id=Id,@'attr.type'=Type,@for=For), _).

  
key_node(element(key, ['attr.name'=Key, 'attr.type'=Type, for=For, id=Id],[])) :-
    key(Key, Type, For, Id),
    debug([section,new_key],'generating new key ~w',[element(key, ['attr.name'=Key, 'attr.type'=Type, for=For, id=Id],[])]).
 
edge_node(XML, Node) :- 
    edge(Eid, From, To, Label, EAttr),
    graphml_key(XML, label, string, edge, LabelId),
    LabelNode = element(data,[key=LabelId],[Label]),
    findall(element(data,[key=AId],[AttrVal]), (member(Akey=AttrVal, EAttr), key(Akey, Type, edge, AId)), AllData),
    Node = element(edge,[source=From,target=To],[LabelNode|AllData]).

node_node(XML, Node) :-
    node(Nid, Nlabel, NAttr),
    graphml_key(XML, label, string, node, LabelId),
    LabelNode = element(data,[key=LabelId],[Nlabel]),
    findall(element(data,[key=AId],[AttrVal]), (member(Akey=AttrVal, NAttr), key(Akey, Type, node, AId)), AllData),
    Node = element(node,[id=Nid],[LabelNode|AllData]).
%    format('generating new node ~w\n',[Node]).
    
merge_write :-
    graph_xml(File,_),
    merge_write(File,element(graphml,[],[element(graph,[],[])])).

merge_write_auto :-
    get_filename(prefix, xml, File),
    merge_write(File,element(graphml,[],[element(graph,[],[])])).


merge_write(File, element(graphml,Attr,Sub)) :-
    add_keys,
    select(element(graph,Gattr,Gsub), Sub, Remain),
    findall(Node, key_node(Node), KeyNodes),
    findall(Node, node_node(element(graphml,Attr,Sub),Node), Nodes),    
    findall(Node, edge_node(element(graphml,Attr,Sub),Node), Edges),
    flatten([Gsub,Nodes,Edges],Gsub2),

    flatten([Remain,KeyNodes,element(graph,[edgedefault=undirected],Gsub2)], Sub2),
    format('<app_data>\n{"graph_output":"~w"}\n</app_data>\n',[File]),
    open(File, write, Str, []),
	xml_write(Str, [element(graphml,[xmlns="http://graphml.graphdrawing.org/xmlns", xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance", xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd"],Sub2)], [header(false)]),
    close(Str).
    
get_filename(Pre, Ext, Name) :-
    gen_id(Id),
    format(atom(Name), '~w_~w.~w', [Pre,Id,Ext]).
    
formatted_node(Map,element(node,[id=Nid],Sub)) :-
    node(Nid, Nlabel, Nattr),
    intersection([title=Title],Nattr,_),
    get_key(Map,label,Label),
    get_key(Map,text,Text),
    Sub = [element(data,[key=Label],[Nlabel]),element(data,[key=Text],[Title])].


get_key(Map, Name, Key) :-
    member(map(Name,Key),Map).
    

load_graphml(File) :-
    format('before loading ~w\n',[File]), 
    load_xml_file(File, [XML]), 
    format('loading ~w\n',[File]), 
    retractall(graph_xml(_,_)),
    retractall(node(_,_,_)),
    retractall(edge(_,_,_,_,_)),
    retractall(key(_, _, _, _)),
    assert(graph_xml(File,XML)),
%    format('~w\n',[XML]),
    findall(node(Id, Label, Attrs), xml_node(XML, Id, Label, Attrs), AllNodes),
    length(AllNodes, NNodes),
    format('found ~w nodes\n',[NNodes]),
    findall(edge(Id, From, To, Label, Attrs), xml_edge(XML, Id, From, To, Label, Attrs), AllEdges),
    length(AllEdges, NEdges),
    format('found ~w edges\n',[NEdges]),
    findall(key(Key, Type, For, Id), xml_key(XML, Key, Type, For, Id), AllKeys),
    length(AllKeys, NKeys),
    format('found ~w keys\n',[NKeys]),
    maplist(assert, AllNodes),
    maplist(assert, AllEdges),
    maplist(assert, AllKeys),
    format('load complete\n',[]).
    
delete_node(Id) :-
    nonvar(Id),
    retractall(node(Id, _, _)).

   
save_graphml :-
    merge_write_auto,
    retractall(graph_ml(_, _)).
save_graphml(File) :-
    graph_xml(_,XML).

    
    
%%%%%%%%%%%%%%%%


