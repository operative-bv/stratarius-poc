-- T-032: refresh_mart_loonkloof RPC (manual refresh met rechtsgrondslag)
--
-- SECURITY DEFINER: draait met view-owner privileges (kan REFRESH MATERIALIZED VIEW).
-- Caller moet authenticated zijn (auth.uid() IS NOT NULL).
-- Rechtsgrondslag argument is verplicht (audit trail — geen anonieme refresh).
--
-- POC simplificatie: audit_log INSERT deferred als ISS (geen audit_log tabel yet).
-- Voor nu: refresh + return JSON metadata die caller kan loggen.

create or replace function public.refresh_mart_loonkloof(
    p_rechtsgrondslag text
)
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, pg_temp
as $$
declare
    v_initiator uuid;
    v_refreshed_at timestamptz;
begin
    -- Auth guard
    v_initiator := auth.uid();
    if v_initiator is null then
        raise exception 'refresh_mart_loonkloof: authenticated caller required'
            using errcode = '42501';  -- insufficient_privilege
    end if;

    -- Rechtsgrondslag verplicht (audit-vereiste)
    if p_rechtsgrondslag is null or length(trim(p_rechtsgrondslag)) = 0 then
        raise exception 'refresh_mart_loonkloof: p_rechtsgrondslag is verplicht (audit trail)'
            using errcode = '22023';  -- invalid_parameter_value
    end if;

    -- CONCURRENTLY vereist unique index (T-030 mart_loonkloof_pk levert dit).
    -- Voorkomt exclusieve lock op read queries tijdens refresh.
    refresh materialized view concurrently public.mart_loonkloof;

    v_refreshed_at := now();

    return jsonb_build_object(
        'refreshed_at', v_refreshed_at,
        'initiator', v_initiator,
        'rechtsgrondslag', p_rechtsgrondslag,
        'kind', 'manual'
    );
end;
$$;

comment on function public.refresh_mart_loonkloof(text) is
    'Manual refresh RPC voor mart_loonkloof. SECURITY DEFINER met authenticated + rechtsgrondslag guards. Returns JSONB audit-metadata die caller moet loggen. Persistent audit_log tabel deferred als ISS.';

-- REVOKE from public + explicit GRANT authenticated (RPC surface)
revoke execute on function public.refresh_mart_loonkloof(text) from public;
grant execute on function public.refresh_mart_loonkloof(text) to authenticated;
