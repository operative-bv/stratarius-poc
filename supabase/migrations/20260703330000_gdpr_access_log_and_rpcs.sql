-- T-034: GDPR audit-log tabel + query_mart_loonkloof + query_dim_persoon_gdpr RPCs

-- ================================================================
-- 1) gdpr_access_log tabel
-- ================================================================

create table public.gdpr_access_log (
    log_id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    "timestamp" timestamptz not null default now(),
    resource_ref text not null,
    columns_accessed text[] not null,
    rechtsgrondslag text not null,
    resulting_rows int not null check (resulting_rows >= 0),
    event_kind text not null check (event_kind in ('read', 'refresh')),
    metadata jsonb not null default '{}'::jsonb
);

comment on table public.gdpr_access_log is
    'GDPR audit trail: elke access op protected data (dim_persoon.geslacht, mart_loonkloof) EN elke refresh event. Immutable log — geen UPDATE/DELETE toegestaan door RLS.';

alter table public.gdpr_access_log enable row level security;

-- Read: alleen eigen entries (tenant scoping via user_id op de log)
create policy gdpr_access_log_read_own on public.gdpr_access_log
    for select to authenticated
    using (user_id = auth.uid());

-- Grant INSERT + SELECT explicitly (RLS narrowt de scope verder).
grant insert, select on public.gdpr_access_log to authenticated;

-- INSERT policy: elke authenticated user kan alleen eigen audit entries schrijven.
-- SECURITY DEFINER RPCs zetten user_id = auth.uid() (self-attesting).
create policy gdpr_access_log_insert_own on public.gdpr_access_log
    for insert to authenticated
    with check (user_id = auth.uid());

-- UPDATE + DELETE: geen policy → geblokkeerd (immutable audit log).

create index gdpr_access_log_user_timestamp_idx on public.gdpr_access_log (user_id, "timestamp" desc);
create index gdpr_access_log_resource_idx on public.gdpr_access_log (resource_ref);


-- ================================================================
-- 2) query_mart_loonkloof RPC
-- ================================================================

create or replace function public.query_mart_loonkloof(
    p_rechtsgrondslag text
)
    returns table (
        persoon_id uuid,
        legale_entiteit_id uuid,
        referentiedatum date,
        kwartaal text,
        uurloon_bruto numeric,
        basis_vte numeric(18, 4),
        variabele_vte numeric(18, 4),
        geslacht text,
        functieniveau smallint,
        ancienniteit_jaren numeric(6, 2)
    )
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_user uuid;
    v_row_count int;
begin
    v_user := auth.uid();
    if v_user is null then
        raise exception 'query_mart_loonkloof: authenticated caller required'
            using errcode = '42501';
    end if;
    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'query_mart_loonkloof: rechtsgrondslag is verplicht'
            using errcode = '22023';
    end if;

    return query
    select
        m.persoon_id, m.legale_entiteit_id, m.referentiedatum, m.kwartaal,
        m.uurloon_bruto, m.basis_vte, m.variabele_vte, m.geslacht,
        m.functieniveau, m.ancienniteit_jaren
    from public.mart_loonkloof m
    where basejump.has_role_on_account((
        select le.basejump_account_id
        from public.dim_legale_entiteit le
        where le.legale_entiteit_id = m.legale_entiteit_id
    ));

    get diagnostics v_row_count = row_count;

    insert into public.gdpr_access_log (user_id, resource_ref, columns_accessed, rechtsgrondslag, resulting_rows, event_kind)
    values (v_user, 'mart_loonkloof',
            array['persoon_id','geslacht','functieniveau','basis_vte','variabele_vte','uurloon_bruto','ancienniteit_jaren'],
            p_rechtsgrondslag, v_row_count, 'read');
end;
$$;

comment on function public.query_mart_loonkloof(text) is
    'GDPR-gate voor mart_loonkloof read access. Logt user_id + rechtsgrondslag + row count in gdpr_access_log. Direct SELECT op mart_loonkloof zonder deze RPC = geen audit trail.';

revoke execute on function public.query_mart_loonkloof(text) from public;
grant execute on function public.query_mart_loonkloof(text) to authenticated;


-- ================================================================
-- 3) query_dim_persoon_gdpr RPC (geslacht + opleidingsniveau)
-- ================================================================

create or replace function public.query_dim_persoon_gdpr(
    p_persoon_id uuid,
    p_rechtsgrondslag text
)
    returns table (
        persoon_id uuid,
        geslacht text,
        opleidingsniveau text
    )
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_user uuid;
    v_row_count int;
begin
    v_user := auth.uid();
    if v_user is null then
        raise exception 'query_dim_persoon_gdpr: authenticated caller required'
            using errcode = '42501';
    end if;
    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'query_dim_persoon_gdpr: rechtsgrondslag is verplicht'
            using errcode = '22023';
    end if;

    return query
    select p.persoon_id, p.geslacht, p.opleidingsniveau
    from public.dim_persoon p
    where p.persoon_id = p_persoon_id
      and basejump.has_role_on_account(p.owning_account_id);

    get diagnostics v_row_count = row_count;

    insert into public.gdpr_access_log (user_id, resource_ref, columns_accessed, rechtsgrondslag, resulting_rows, event_kind, metadata)
    values (v_user, 'dim_persoon', array['geslacht', 'opleidingsniveau'],
            p_rechtsgrondslag, v_row_count, 'read',
            jsonb_build_object('persoon_id', p_persoon_id));
end;
$$;

comment on function public.query_dim_persoon_gdpr(uuid, text) is
    'GDPR-gate voor dim_persoon.geslacht + opleidingsniveau read. Column-level REVOKE (T-004) blokkeert directe SELECT; deze RPC is de enige lawful path.';

revoke execute on function public.query_dim_persoon_gdpr(uuid, text) from public;
grant execute on function public.query_dim_persoon_gdpr(uuid, text) to authenticated;
