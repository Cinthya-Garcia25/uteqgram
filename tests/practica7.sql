\set ON_ERROR_STOP on
begin;
do $$
declare a text; g text; u text; v text; data jsonb;
begin
 select token into a from practica7.devices where id='admin';
 select token into g from practica7.devices where id='agent';
 select token into u from practica7.devices where id='user1';
 select token into v from practica7.devices where id='user2';
 -- TC01
 perform public.practica7_api('user1',u,'create','{"id":"REP001","equipment":"Laptop","description":"No enciende","kind":"Reporte de falla","priority":"Media","assignee":"agent"}');
 data=public.practica7_api('user1',u,'lookup','{"id":"REP001"}');
 assert data->'report'->>'equipment'='Laptop','Alta no persistió';
 -- TC02
 begin
  perform public.practica7_api('user1',u,'create','{"id":"REP002","equipment":" ","description":" "}');
  raise exception 'TEST: aceptó campos vacíos';
 exception when others then if sqlerrm like 'TEST:%' then raise; end if; end;
 -- TC03
 begin
  perform public.practica7_api('user1',u,'create','{"id":"REP001","equipment":"Otro","description":"Duplicado","kind":"Reporte de falla","priority":"Alta","assignee":"agent"}');
  raise exception 'TEST: aceptó duplicado';
 exception when others then if sqlerrm like 'TEST:%' then raise; end if; end;
 assert (select equipment='Laptop' from practica7.reports where id='REP001'),'Sobrescribió reporte';
 -- TC04
 perform public.practica7_api('agent',g,'update','{"id":"REP001","priority":"Alta","status":"En atención","assignee":"agent"}');
 data=public.practica7_api('user1',u,'lookup','{"id":"REP001"}');
 assert data->'report'->>'priority'='Alta','Actualización no persistió';
 -- Privacidad: usuario 2 no ve reportes ni matriz de otros.
 data=public.practica7_api('user2',v);
 assert jsonb_array_length(data->'reports')=0 and jsonb_array_length(data->'tests')=0,'Filtró datos privados';
 begin
  perform public.practica7_api('user2',v,'delete','{"id":"REP001"}');
  raise exception 'TEST: usuario eliminó reporte';
 exception when others then if sqlerrm like 'TEST:%' then raise; end if; end;
 -- Mensajería y contadores.
 perform public.practica7_api('user1',u,'send','{"recipient":"agent","body":"Hola","attachment":{"name":"prueba.txt","data":"data:application/octet-stream;base64,SG9sYQ=="}}');
 assert (select total=1 from practica7.counts where id='user1'),'Contador incorrecto';
 data=public.practica7_api('agent',g);
 assert jsonb_array_length(data->'messages')=1,'No recibió el mensaje';
 data=public.practica7_api('user2',v);
 assert jsonb_array_length(data->'messages')=0,'Conversación filtrada';
 begin
  perform public.practica7_api('user1',u,'send','{"recipient":"agent","body":"  "}');
  raise exception 'TEST: mensaje vacío aceptado';
 exception when others then if sqlerrm like 'TEST:%' then raise; end if; end;
 -- Matriz y permisos.
 perform public.practica7_api('agent',g,'test','{"id":"TC01","result":"Aprobado","notes":"Verificado localmente"}');
 begin
  perform public.practica7_api('user1',u,'test','{"id":"TC01","result":"Fallido"}');
  raise exception 'TEST: usuario modificó matriz';
 exception when others then if sqlerrm like 'TEST:%' then raise; end if; end;
 -- Desconexión y atención delegada.
 perform public.practica7_api('admin',a,'update','{"id":"REP001","priority":"Alta","status":"Abierto","assignee":"admin"}');
 perform public.practica7_api('admin',a,'disconnect');
 assert (select assignee='agent' from practica7.reports where id='REP001'),'No delegó al agente';
 -- Intercambio de rol y rechazo al administrador anterior.
 perform public.practica7_api('admin',a,'swap','{"target":"user2"}');
 assert (select role='admin' from practica7.devices where id='user2'),'No transfirió administrador';
 begin
  perform public.practica7_api('admin',a,'clear');
  raise exception 'TEST: administrador anterior conservó permisos';
 exception when others then if sqlerrm like 'TEST:%' then raise; end if; end;
 perform public.practica7_api('user2',v,'clear');
 assert (select count(*)=0 from practica7.messages),'No limpió historial';
 assert (select total=1 from practica7.counts where id='user1'),'Borró contador total';
 -- TC05 y TC06
 perform public.practica7_api('agent',g,'delete','{"id":"REP001"}');
 data=public.practica7_api('user1',u,'lookup','{"id":"REP001"}');
 assert data->'report'='null'::jsonb,'Eliminado sigue activo';
 data=public.practica7_api('agent',g,'lookup','{"id":"REP999"}');
 assert data->'report'='null'::jsonb,'Inexistente no controlado';
 -- Clave falsa no autentica.
 begin
  perform public.practica7_api('agent','invalid');
  raise exception 'TEST: clave falsa aceptada';
 exception when others then if sqlerrm like 'TEST:%' then raise; end if; end;
 raise notice 'Pruebas locales de altas, validación, duplicados, actualización, borrado, consulta, permisos, mensajería, contadores y roles: OK';
end $$;
rollback;
