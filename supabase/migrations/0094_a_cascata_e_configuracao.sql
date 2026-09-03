-- 0094 · B57 · A cascata é configuração, e o custo entra na conta
--
-- O QUE ESTAVA NO BANCO E NINGUÉM USAVA
--
-- `precos_canal` existe desde sempre, em milésimos de centavo por mensagem:
--
--     e-mail        200      R$ 0,002
--     WhatsApp    4.500      R$ 0,045      22x o e-mail
--     SMS         8.000      R$ 0,080      40x o e-mail
--
-- E o roteamento nunca olhou para ela. A cascata mandava "e-mail + SMS" para
-- urgente sem que ninguém visse que o último degrau custa quarenta vezes o
-- anterior para chegar ao mesmo lugar em quase todo caso.
--
-- POR QUE A CASCATA VIRA TABELA
--
-- Porque a pergunta *"vale gastar quarenta vezes mais para não perder esta
-- oferta?"* **não é de engenharia**. É risco contra dinheiro, e quem responde
-- não deveria precisar de um commit — nem esperar a próxima build para mudar de
-- ideia depois de ver a primeira fatura.
--
-- Tirar o SMS da cascata de urgente passa a ser apagar uma linha. Pôr o e-mail
-- na frente do WhatsApp, trocar duas. E a coluna `motivo` guarda **por que**
-- cada degrau está onde está: a tabela registra a decisão, não só o efeito.
--
-- O QUE NÃO SE CONFIGURA AQUI, E NÃO É ESQUECIMENTO
--
--   · **documento nunca sai por canal não oficial** — a fronteira 8. A trava
--     está em `mensagem_confere_retrato` (na porta), em `reencaminhar_mensagem`
--     (no degrau) e em `ordemDeTentativa` (na ordem). Pôr `whatsapp` na rota de
--     documento não faz nada: as três recusam.
--   · **a mão dela é sempre o último degrau** — ela depende de humano acordado,
--     e trocar uma entrega que ainda tinha caminho por uma tarefa que ela pode
--     não ver hoje é perder a mensagem por comodidade nossa.
--   · **canal sem provedor ou sem contato não é degrau** — rota que peça um
--     canal impossível não vira mensagem sem destino; vira degrau pulado.

create table if not exists public.rota_do_canal (
  classe        text        not null check (classe in ('urgente', 'rotina', 'documento')),
  posicao       smallint    not null check (posicao > 0),
  canal         text        not null check (canal in ('whatsapp', 'sms', 'email')),
  motivo        text,
  atualizado_em timestamptz not null default now(),
  primary key (classe, posicao),
  unique (classe, canal)
);

comment on table public.rota_do_canal is
  'A cascata de saida, por classe e em ordem. E CONFIGURACAO e nao codigo: a pergunta "vale gastar quarenta vezes mais para nao perder esta oferta?" e decisao de risco contra dinheiro, e quem a faz nao deveria precisar de um commit. O que NAO se configura aqui: documento nunca sai por canal nao oficial, e a mao dela e sempre o ultimo degrau.';

comment on column public.rota_do_canal.motivo is
  'Por que este degrau existe nesta posicao. Escrito por quem configurou — a tabela guarda a decisao, nao so o efeito.';

alter table public.rota_do_canal enable row level security;

drop policy if exists rota_do_canal_operador on public.rota_do_canal;
create policy rota_do_canal_operador on public.rota_do_canal
  for select to authenticated using (public.e_operador());

revoke all on public.rota_do_canal from anon;
grant select on public.rota_do_canal to authenticated;
grant all on public.rota_do_canal to service_role;

-- A semente é **o comportamento de hoje**, escrito. Mudar a cascata passa a ser
-- editar estas linhas, e não reabrir a build.
insert into public.rota_do_canal (classe, posicao, canal, motivo) values
  ('urgente',   1, 'whatsapp', 'O canal da paciente, quando é o dela. Mais barato que SMS e com resposta.'),
  ('urgente',   2, 'email',    'Vinte e duas vezes mais barato que o WhatsApp, e chega ao mesmo lugar.'),
  ('urgente',   3, 'sms',      'Último degrau antes do silêncio. Custa 40x o e-mail: está aqui até alguém decidir que não vale.'),
  ('rotina',    1, 'whatsapp', 'O canal da paciente.'),
  ('rotina',    2, 'email',    'Rotina não justifica SMS: ela tolera horas, e a mão dela é o fim.'),
  ('documento', 1, 'email',    'O único canal possível para documento. A trava não é esta linha — é a fronteira 8, no código.')
on conflict (classe, posicao) do nothing;

-- ------------------------------------- o panorama passa a mostrar a decisão
--
-- A rota e o preço entram no painel do operador porque **decisão de dinheiro
-- tomada no escuro vira fatura**: o custo tem de estar na mesma tela em que se
-- muda a ordem dos degraus.

create or replace function public.panorama_do_canal()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  r jsonb;
begin
  if not public.e_operador() then
    raise exception 'só o operador vê o panorama do canal';
  end if;

  select jsonb_build_object(
    'em', now(),
    'varreduras', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nome', v.nome, 'em', v.em, 'cega', v.cega, 'detalhe', v.detalhe)
               order by v.nome)
        from public.varreduras_do_canal v), '[]'::jsonb),
    'disjuntores', coalesce((
      select jsonb_agg(jsonb_build_object(
               'canal', d.canal, 'conta_id', d.conta_id, 'estado', d.estado,
               'motivo', d.motivo, 'desde', d.desde) order by d.canal)
        from public.canal_disjuntor d), '[]'::jsonb),
    'saida', coalesce((
      select jsonb_agg(x order by x->>'canal', x->>'estado')
        from (
          select jsonb_build_object('canal', m.canal, 'estado', m.estado, 'n', count(*)) as x
            from public.mensagens m
           where m.criado_em >= now() - interval '24 hours'
           group by m.canal, m.estado
        ) y), '[]'::jsonb),
    'na_mao_dela', coalesce((
      select jsonb_agg(x order by x->>'n' desc)
        from (
          select jsonb_build_object('conta_id', m.conta_id, 'n', count(*),
                                    'mais_antiga', min(m.criado_em)) as x
            from public.mensagens m
           where m.estado = 'na_sua_mao'
           group by m.conta_id
        ) z), '[]'::jsonb),
    'entrada', jsonb_build_object(
      'recebidas_24h', (select count(*) from public.mensagens_recebidas
                         where recebida_em >= now() - interval '24 hours'),
      'nao_entendidas_24h', (select count(*) from public.mensagens_recebidas
                              where recebida_em >= now() - interval '24 hours'
                                and coalesce(resultado, '') = 'nao_entendida')
    ),
    'rota', coalesce((
      select jsonb_agg(jsonb_build_object(
               'classe', rc.classe, 'posicao', rc.posicao, 'canal', rc.canal,
               'motivo', rc.motivo) order by rc.classe, rc.posicao)
        from public.rota_do_canal rc), '[]'::jsonb),

    -- O preço **vigente**: a linha mais recente cuja vigência já começou. Preço
    -- tem vigência para não reescrever o passado quando a primeira fatura do
    -- provedor chegar e substituir a estimativa.
    'precos', coalesce((
      select jsonb_agg(jsonb_build_object('canal', p.canal,
                                          'centavos_milesimos', p.centavos_milesimos,
                                          'fonte', p.fonte) order by p.canal)
        from (
          select distinct on (pc.canal) pc.canal, pc.centavos_milesimos, pc.fonte
            from public.precos_canal pc
           where pc.vigencia_inicio <= current_date
           order by pc.canal, pc.vigencia_inicio desc
        ) p), '[]'::jsonb)
  ) into r;

  return r;
end;
$function$;

revoke all on function public.panorama_do_canal() from public, anon;
grant execute on function public.panorama_do_canal() to authenticated, service_role;
