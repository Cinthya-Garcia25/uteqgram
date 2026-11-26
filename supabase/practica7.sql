-- Ejecutar una vez en SQL Editor. Tablas aisladas del proyecto anterior.
create schema if not exists practica7;
revoke all on schema practica7 from public;
create table if not exists practica7.devices (
 id text primary key, name text not null, role text not null,
 token text not null default replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''), seen timestamptz
);
insert into practica7.devices(id,name,role) values
 ('admin','Administrador','admin'),('agent','Agente de atención','agent'),
 ('user1','Usuario 1','user'),('user2','Usuario 2','user') on conflict do nothing;
create table if not exists practica7.reports (
 id text primary key, owner text not null, equipment text not null, description text not null,
 kind text not null, priority text not null, assignee text not null, status text not null default 'Abierto',
 created_at timestamptz not null default now(), deleted boolean not null default false
);
create table if not exists practica7.messages (
 id bigint generated always as identity primary key, sender text not null, recipient text not null,
 body text not null, attachment jsonb, created_at timestamptz not null default now()
);
create table if not exists practica7.counts (id text primary key, total bigint not null default 0);
create table if not exists practica7.tests (id text primary key, result text not null, notes text not null, updated_by text, updated_at timestamptz default now());
insert into practica7.tests select 'TC0'||i,'Sin registrar','Sin observaciones',null,now() from generate_series(1,8) i on conflict do nothing;
alter table practica7.devices enable row level security;
alter table practica7.reports enable row level security;
alter table practica7.messages enable row level security;
alter table practica7.counts enable row level security;
alter table practica7.tests enable row level security;

create or replace function public.practica7_api(p_device text, p_token text, p_action text default 'sync', p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = pg_catalog, practica7 as $$
declare me practica7.devices; target practica7.devices; r practica7.reports; result jsonb; report_id text;
begin
 select * into me from practica7.devices where id=p_device and token=p_token;
 if not found then raise exception 'Enlace o clave de dispositivo incorrectos'; end if;
 -- Serializar cambios de roles para preservar un administrador y un agente.
 if p_action='swap' then
  perform 1 from practica7.devices order by id for update;
  select * into me from practica7.devices where id=p_device;
 end if;
 update practica7.devices set seen=now() where id=me.id;
 if p_action='swap' then
  if me.role<>'admin' then raise exception 'Solo el administrador puede intercambiar roles'; end if;
  select * into target from practica7.devices where id=p_data->>'target' and id<>me.id;
  if not found then raise exception 'Selecciona otro dispositivo'; end if;
  update practica7.devices set role=target.role where id=me.id;
  update practica7.devices set role='admin' where id=target.id;
 elsif p_action='disconnect' then
  update practica7.devices set seen=null where id=me.id;
  -- Los casos pendientes pasan al agente disponible; las solicitudes directas permanecen identificadas por tipo.
  update practica7.reports set assignee=(select id from practica7.devices where role='agent') where assignee=me.id and not deleted and status<>'Resuelto' and me.role='admin';
 elsif p_action='send' then
  if length(trim(coalesce(p_data->>'body','')))=0 then raise exception 'Escribe un mensaje; no se permiten mensajes vacíos'; end if;
  if length(p_data->>'body')>2000 then raise exception 'Mensaje demasiado largo'; end if;
  if not exists(select 1 from practica7.devices where id=p_data->>'recipient' and id<>me.id) then raise exception 'Selecciona otro dispositivo'; end if;
  if p_data->'attachment' <> 'null'::jsonb and p_data->'attachment' is not null then
   if length(p_data->'attachment'->>'data')>140000 or (p_data->'attachment'->>'data') !~ '^data:application/octet-stream;base64,[A-Za-z0-9+/=]+$' then raise exception 'Archivo inválido o mayor a 100 KB'; end if;
  end if;
  insert into practica7.messages(sender,recipient,body,attachment) values(me.id,p_data->>'recipient',trim(p_data->>'body'),p_data->'attachment');
  insert into practica7.counts values(me.id,1) on conflict(id) do update set total=counts.total+1;
 elsif p_action='clear' then
  if me.role<>'admin' then raise exception 'Solo el administrador puede limpiar el historial'; end if;
  delete from practica7.messages; -- Los contadores totales se conservan.
 elsif p_action='create' then
  report_id=upper(trim(p_data->>'id'));
  if coalesce(report_id,'') !~ '^[A-Z0-9_-]{1,30}$' or length(trim(coalesce(p_data->>'equipment','')))=0 or length(trim(coalesce(p_data->>'description','')))=0 then raise exception 'Identificador, equipo y descripción son obligatorios'; end if;
  if length(p_data->>'equipment')>100 or length(p_data->>'description')>2000 then raise exception 'Campos demasiado largos'; end if;
  if p_data->>'priority' not in ('Alta','Media','Baja') or p_data->>'kind' not in ('Reporte de falla','Proceso de atención','Acceso perdido') then raise exception 'Tipo o prioridad inválida'; end if;
  if coalesce(p_data->>'assignee','') not in ('admin','agent') then raise exception 'Responsable inválido'; end if;
  select * into target from practica7.devices where role=p_data->>'assignee';
  if not found then raise exception 'Responsable inválido'; end if;
  begin
   insert into practica7.reports(id,owner,equipment,description,kind,priority,assignee) values(report_id,me.id,trim(p_data->>'equipment'),trim(p_data->>'description'),p_data->>'kind',p_data->>'priority',target.id);
  exception when unique_violation then raise exception 'El identificador ya existe; no se sobrescribió el reporte'; end;
 elsif p_action in ('update','delete') then
  if me.role not in ('admin','agent') then raise exception 'Solo administrador y agente pueden modificar reportes'; end if;
  select * into r from practica7.reports where id=upper(trim(p_data->>'id')) and not deleted for update;
  if not found then raise exception 'Reporte inexistente'; end if;
  if me.role='agent' and r.assignee<>me.id and exists(select 1 from practica7.devices where id=r.assignee and seen>now()-interval '45 seconds') then raise exception 'El caso está asignado a otro dispositivo conectado'; end if;
  if p_action='delete' then update practica7.reports set deleted=true where id=r.id;
  else
   if p_data->>'priority' not in ('Alta','Media','Baja') or p_data->>'status' not in ('Abierto','En atención','Resuelto') or not exists(select 1 from practica7.devices where id=p_data->>'assignee' and role in ('admin','agent')) then raise exception 'Actualización inválida'; end if;
   update practica7.reports set priority=p_data->>'priority',status=p_data->>'status',assignee=p_data->>'assignee' where id=r.id;
  end if;
 elsif p_action='test' then
  if me.role not in ('admin','agent') then raise exception 'Matriz reservada a administrador y agente'; end if;
  if p_data->>'result' not in ('Sin registrar','Aprobado','Fallido','Bloqueado') then raise exception 'Resultado inválido'; end if;
  update practica7.tests set result=p_data->>'result',notes=left(coalesce(p_data->>'notes','Sin observaciones'),2000),updated_by=me.id,updated_at=now() where id=p_data->>'id';
 elsif p_action not in ('sync','lookup') then raise exception 'Operación inválida';
 end if;
 if p_action='lookup' then
  select to_jsonb(x) into result from practica7.reports x where id=upper(trim(p_data->>'id')) and not deleted and (me.role in ('admin','agent') or owner=me.id);
  return jsonb_build_object('report',result);
 end if;
 return jsonb_build_object(
  'me',jsonb_build_object('id',me.id,'role',(select role from practica7.devices where id=me.id)),
  'devices',(select jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'role',d.role,'online',d.seen>now()-interval '45 seconds','total',coalesce(c.total,0))) from practica7.devices d left join practica7.counts c on c.id=d.id),
  'messages',coalesce((select jsonb_agg(x order by x.id) from (select * from practica7.messages where sender=me.id or recipient=me.id order by id desc limit 100) x),'[]'::jsonb),
  'reports',coalesce((select jsonb_agg(x order by x.created_at desc) from practica7.reports x where not deleted and (me.role in ('admin','agent') or owner=me.id)),'[]'::jsonb),
  'tests',case when me.role in ('admin','agent') then (select jsonb_agg(x order by x.id) from practica7.tests x) else '[]'::jsonb end
 );
end $$;
revoke all on function public.practica7_api(text,text,text,jsonb) from public;
grant execute on function public.practica7_api(text,text,text,jsonb) to anon, authenticated;
-- Guarda estos cuatro enlaces. Las claves son credenciales: no publiques esta salida.
select name, '/?device='||id||'#token='||token as enlace from practica7.devices order by id;
