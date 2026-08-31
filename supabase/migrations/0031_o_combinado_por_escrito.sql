-- 0031 · B19 — o contrato terapêutico com aceite datado.
--
-- Isoladamente, contrato assinado é papelada: sete dos oito concorrentes têm
-- alguma versão disso. O que muda de classe aqui é a amarração — **é o lastro
-- que a D2 cobra, a D14 reajusta e o F2a recibifica** (doc 03 §6). A multa de
-- falta deixa de ser combinado de boca e vira cláusula aceita com data e hora.
--
-- Seis decisões, e todas têm consequência fora do software.
--
-- ## 1. O aceite é do ENQUADRE, não do paciente
--
-- É a decisão que sustenta o resto. Reajustar (D14) fecha um enquadre e abre
-- outro; o contrato aceito para R$ 200 não é o contrato de R$ 240. Pendurar o
-- aceite no paciente faria o sistema afirmar que ela combinou um valor que
-- nunca foi mostrado a ninguém — e essa afirmação apareceria numa cobrança.
-- Pendurado no enquadre, o reajuste **perde o lastro de propósito** e a tela
-- diz isso: o combinado novo precisa de aceite novo.
--
-- ## 2. A política de falta é obrigatória no texto
--
-- Portão ético da fase 2, no doc 07: *"política de falta visível ao paciente no
-- contrato aceito"*. Aqui isso não é recomendação de tela — `publicar_contrato`
-- **recusa** um corpo que não tenha `{{politica}}` e `{{valor}}`. Cobrar por
-- uma regra que não estava escrita é exatamente o constrangimento que o produto
-- existe para eliminar; um contrato que omite a regra é pior do que nenhum,
-- porque dá aparência de acordo ao que não foi acordado.
--
-- ## 3. Isto NÃO é assinatura digital ICP-Brasil
--
-- É um registro datado de aceite: quem clicou, quando, de onde, e o texto exato
-- congelado. Vale como prova (Lei 14.063/2020, assinatura eletrônica simples,
-- admitida entre as partes) e não vale como certificado qualificado. A tela diz
-- isso com todas as letras. Vender mais do que se entrega aqui faria alguém
-- levar um documento a um lugar onde ele não serve — confiando no nosso texto.
--
-- ## 4. Nada é bloqueado por falta de aceite
--
-- Sem contrato aceito o sistema não recusa agendar, não recusa atender e não
-- recusa cobrar. Ele registra a ausência do lastro e mostra. Condicionar
-- atendimento a um clique seria transformar o produto em porteiro de uma
-- relação clínica — a fronteira do doc 11 que não se atravessa nem a pedido.
--
-- ## 5. Quem carimba o relógio é o servidor, e o rótulo vem de quem digita
--
-- `aceito_em` é sempre `now()` do banco, mesmo quando a função que pede é
-- `security definer`: ninguém antedata um aceite, nem ela. E a `origem` não é
-- digitada — é **derivada de quem está no teclado**. Sessão autenticada só
-- consegue gravar `presencial` (ela registrando que a pessoa assinou na sala);
-- só o visitante sem sessão, chegando pelo token, grava `link`. Um campo de
-- procedência que o interessado escolhe não é procedência, é opinião.
--
-- ## 6. Revogar não apaga
--
-- O paciente pode retirar o aceite (LGPD, e antes disso bom senso). Revogar
-- encerra a validade daqui para a frente e **preserva a linha** — apagar o
-- aceite apagaria o lastro das cobranças que já foram feitas sob ele, e essas
-- aconteceram. O que passou continua explicável; o que vem depois não tem mais
-- lastro, e a tela avisa.

-- ------------------------------------------------------- formatação congelada
--
-- O texto do contrato é montado no banco porque é o banco que o congela: se o
-- cliente mandasse a string pronta, o "contrato aceito" seria o que o navegador
-- disse que era. Isso obriga a uma segunda implementação de dinheiro, horário e
-- política — as primeiras estão em `lib/dinheiro.ts` e `lib/enquadre.ts`, e são
-- as que fazem a pré-visualização.
--
-- Duas formatações divergem calada. Então cada uma tem, na sua suíte, o **mesmo
-- caso com a mesma string esperada** — inclusive o espaço fino (U+00A0) que o
-- Intl põe depois do "R$" e que ninguém enxerga num diff.

create or replace function public.reais(v numeric)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  bruto  bigint;
  inteiro text;
  grupos  text := '';
begin
  bruto   := round(coalesce(v, 0) * 100)::bigint;
  inteiro := (bruto / 100)::text;

  while length(inteiro) > 3 loop
    grupos  := '.' || right(inteiro, 3) || grupos;
    inteiro := left(inteiro, length(inteiro) - 3);
  end loop;

  -- chr(160) e não um espaço comum: é o que o Intl do navegador produz, e a
  -- pré-visualização precisa bater caractere a caractere com o texto congelado.
  return 'R$' || chr(160) || inteiro || grupos || ',' ||
         lpad((bruto % 100)::text, 2, '0');
end;
$$;

/** "terça, 15h" — espelho de `rotuloHorario` em lib/enquadre.ts. */
create or replace function public.rotulo_horario(p_dia smallint, p_hora time)
returns text
language sql
immutable
set search_path = ''
as $$
  select (array['domingo','segunda','terça','quarta','quinta','sexta','sábado'])[p_dia + 1]
      || ', ' || extract(hour from p_hora)::int::text
      || case when extract(minute from p_hora) = 0
              then 'h'
              else 'h' || lpad(extract(minute from p_hora)::int::text, 2, '0')
         end;
$$;

/** A política em português — espelho de `rotuloPolitica`. */
create or replace function public.rotulo_politica(p_horas smallint, p_pct smallint)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_pct = 0   then 'falta não é cobrada'
    when p_horas = 0 then 'falta cobra ' || p_pct::text || '% em qualquer aviso'
    else 'desmarcar com menos de ' || p_horas::text || ' horas cobra ' ||
         case when p_pct = 100 then 'a sessão inteira' else p_pct::text || '%' end
  end;
$$;

-- ---------------------------------------------------------------- contratos

create table if not exists public.contratos (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,

  -- Sequencial por conta. A versão aparece no rodapé do texto aceito: saber
  -- *qual* contrato a pessoa aceitou é metade da utilidade de ter contrato.
  versao        integer not null,

  titulo        text not null check (length(trim(titulo)) between 1 and 120),
  corpo         text not null check (length(corpo) between 200 and 20000),

  publicado_em  timestamptz,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists contratos_versao
  on public.contratos (conta_id, versao);

-- Um rascunho por vez. Dois rascunhos abertos viram dois contratos "quase
-- prontos" e ninguém sabe qual está valendo.
create unique index if not exists contrato_rascunho_unico
  on public.contratos (conta_id)
  where publicado_em is null;

create index if not exists contratos_publicados
  on public.contratos (conta_id, versao desc)
  where publicado_em is not null;

/**
 * Publicado não se edita.
 *
 * Se o corpo mudasse depois, o `contrato_id` gravado no aceite apontaria para
 * um texto que a pessoa nunca leu — e a defesa da cobrança viraria uma
 * afirmação sem prova. Editar é abrir a versão seguinte; a anterior fica.
 */
create or replace function public.contrato_nao_muda()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.publicado_em is not null then
    if row(new.titulo, new.corpo, new.versao, new.publicado_em)
       is distinct from
       row(old.titulo, old.corpo, old.versao, old.publicado_em)
    then
      raise exception 'contrato publicado não se edita: publique a versão seguinte';
    end if;
  end if;

  new.atualizado_em := now();
  return new;
end;
$$;

drop trigger if exists contratos_imutaveis on public.contratos;
create trigger contratos_imutaveis before update on public.contratos
  for each row execute function public.contrato_nao_muda();

-- `conta_id` é derivado, nunca digitado (mesma regra da 0005).
create or replace function public.contrato_carimba()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.conta_id := public.conta_atual();
  if new.conta_id is null then
    raise exception 'sem conta na sessão';
  end if;
  return new;
end;
$$;

drop trigger if exists contratos_carimbo on public.contratos;
create trigger contratos_carimbo before insert on public.contratos
  for each row execute function public.contrato_carimba();

-- ------------------------------------------------------------------ aceites

create table if not exists public.aceites (
  id            uuid primary key default gen_random_uuid(),
  conta_id      uuid not null references public.contas (id) on delete cascade,
  paciente_id   uuid not null references public.pacientes (id) on delete cascade,

  -- `restrict`: o enquadre é o objeto do qual o aceite fala. Apagar o enquadre
  -- por baixo de um aceite deixaria uma prova sem objeto.
  enquadre_id   uuid not null references public.enquadres (id) on delete restrict,
  contrato_id   uuid not null references public.contratos (id) on delete restrict,

  -- O endereço do link. Gerado no servidor, 128 bits — o cliente não escolhe.
  token         text not null unique check (token ~ '^[0-9a-f]{32}$'),

  -- O texto exato. Enquanto pendente, acompanha o combinado; no instante do
  -- aceite, congela.
  texto         text not null,
  retrato       jsonb not null,

  criado_em     timestamptz not null default now(),
  expira_em     timestamptz not null,

  aceito_em     timestamptz,
  aceito_por    text check (aceito_por is null or length(trim(aceito_por)) between 2 and 120),
  -- Preenchido quando quem aceita é responsável por menor (doc 07).
  parentesco    text check (parentesco is null or length(trim(parentesco)) between 2 and 40),
  origem        text check (origem is null or origem in ('link', 'presencial')),

  -- Qualidade de prova, não de segurança: vêm de quem chama e valem o que
  -- valem. Estão aqui porque um aceite sem procedência nenhuma é mais fraco.
  ip            inet,
  agente        text,

  revogado_em        timestamptz,
  motivo_revogacao   text,

  check (aceito_em is null or aceito_por is not null)
);

create index if not exists aceites_da_conta on public.aceites (conta_id, criado_em desc);
create index if not exists aceites_do_paciente on public.aceites (paciente_id, criado_em desc);

-- Um aceite vivo por enquadre. É a invariante que faz "o combinado tem lastro?"
-- ser uma pergunta com uma resposta só.
create unique index if not exists aceite_vivo_do_enquadre
  on public.aceites (enquadre_id)
  where revogado_em is null;

/**
 * O que o servidor calcula, o cliente não digita.
 *
 * Mesma doutrina do `mensagem_confere_retrato` da 0017: um PATCH direto no
 * PostgREST não forja token, texto, retrato nem conta. Aqui isso importa mais
 * do que lá — o que se forjaria é a prova.
 */
create or replace function public.aceite_monta()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  enq  record;
  pac  record;
  prof record;
  cont record;
  ctr  record;
begin
  new.conta_id := public.conta_atual();
  if new.conta_id is null then
    raise exception 'sem conta na sessão';
  end if;

  select e.* into enq
    from public.enquadres e
   where e.id = new.enquadre_id and e.conta_id = new.conta_id;
  if not found then raise exception 'combinado não encontrado nesta conta'; end if;

  if enq.vigencia_fim is not null then
    raise exception 'combinado já encerrado: o aceite é do combinado vigente';
  end if;

  select p.* into pac from public.pacientes p where p.id = enq.paciente_id;
  select pr.* into prof from public.profissionais pr where pr.id = pac.profissional_id;
  select c.*  into cont from public.contas c where c.id = new.conta_id;

  select ct.* into ctr
    from public.contratos ct
   where ct.conta_id = new.conta_id and ct.publicado_em is not null
   order by ct.versao desc
   limit 1;
  if not found then
    raise exception 'esta conta ainda não publicou um contrato';
  end if;

  new.paciente_id := enq.paciente_id;
  new.contrato_id := ctr.id;
  new.token       := replace(gen_random_uuid()::text, '-', '');
  new.texto       := public.montar_contrato(ctr.corpo, enq.id);
  new.retrato     := jsonb_build_object(
    'contrato_versao', ctr.versao,
    'contrato_titulo', ctr.titulo,
    'paciente',        pac.nome,
    'profissional',    coalesce(prof.assina_como, ''),
    'crp',             coalesce(prof.crp, ''),
    'conta',           cont.nome,
    'cidade',          coalesce(cont.cidade, ''),
    'dia_semana',      enq.dia_semana,
    'hora',            enq.hora,
    'duracao_min',     enq.duracao_min,
    'valor',           enq.valor,
    'modelo_cobranca', enq.modelo_cobranca,
    'politica_horas',      enq.politica_horas,
    'politica_percentual', enq.politica_percentual,
    'preparado_em',    now()
  );

  -- Nada nasce aceito. Aceitar é outro verbo, com outro carimbo.
  new.criado_em   := now();
  new.expira_em   := now() + interval '90 days';
  new.aceito_em   := null;
  new.aceito_por  := null;
  new.parentesco  := null;
  new.origem      := null;
  new.ip          := null;
  new.agente      := null;
  new.revogado_em := null;
  new.motivo_revogacao := null;

  return new;
end;
$$;

/**
 * O congelamento, e a derivação da procedência.
 *
 * Enquanto pendente, o texto acompanha o combinado — nada foi acordado ainda, e
 * mostrar um valor velho seria pior do que reescrever. No instante do aceite,
 * congela: dali em diante só `revogado_em` se mexe.
 *
 * E o relógio é do servidor sempre, inclusive quando quem pede é uma função
 * `security definer`. É o que impede antedatar um aceite para dar lastro a uma
 * cobrança que já saiu.
 */
create or replace function public.aceite_congela()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Estes três nunca mudam, em nenhum estado.
  if row(new.conta_id, new.paciente_id, new.enquadre_id)
     is distinct from row(old.conta_id, old.paciente_id, old.enquadre_id)
  then
    raise exception 'aceite não muda de dono nem de combinado';
  end if;

  if old.aceito_em is not null then
    if row(new.texto, new.retrato, new.token, new.contrato_id,
           new.aceito_em, new.aceito_por, new.parentesco, new.origem)
       is distinct from
       row(old.texto, old.retrato, old.token, old.contrato_id,
           old.aceito_em, old.aceito_por, old.parentesco, old.origem)
    then
      raise exception 'aceite dado não se edita: revogue e prepare outro';
    end if;

    if old.revogado_em is not null and new.revogado_em is null then
      raise exception 'aceite revogado não volta atrás';
    end if;

    return new;
  end if;

  -- Pendente virando aceito: o servidor carimba a hora e deduz a procedência de
  -- quem está no teclado. Sessão autenticada é ela registrando que a pessoa
  -- assinou na sala; sem sessão, é o visitante que chegou pelo token.
  if new.aceito_em is not null then
    new.aceito_em := now();

    if (select auth.uid()) is not null then
      new.origem := 'presencial';
      new.ip     := null;
      new.agente := null;
    else
      new.origem := 'link';
    end if;

    if new.aceito_por is null or length(trim(new.aceito_por)) < 2 then
      raise exception 'quem aceitou precisa se identificar';
    end if;

    if old.revogado_em is not null then
      raise exception 'aceite revogado não é aceito depois';
    end if;

    if now() > old.expira_em then
      raise exception 'este link expirou';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists aceites_montagem on public.aceites;
create trigger aceites_montagem before insert on public.aceites
  for each row execute function public.aceite_monta();

drop trigger if exists aceites_congelamento on public.aceites;
create trigger aceites_congelamento before update on public.aceites
  for each row execute function public.aceite_congela();

-- ------------------------------------------------------------ o texto pronto

/**
 * Troca os marcadores pelos valores do combinado.
 *
 * Os marcadores são poucos e de propósito: cada um é um fato que o sistema
 * conhece e consegue manter verdadeiro. Um marcador a mais é uma promessa a
 * mais de que o texto está atualizado.
 */
create or replace function public.montar_contrato(p_corpo text, p_enquadre uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  enq  record;
  pac  record;
  prof record;
  cont record;
  t    text;
begin
  select e.* into enq from public.enquadres e where e.id = p_enquadre;
  if not found then raise exception 'combinado não encontrado'; end if;

  select p.* into pac from public.pacientes p where p.id = enq.paciente_id;
  select pr.* into prof from public.profissionais pr where pr.id = pac.profissional_id;
  select c.*  into cont from public.contas c where c.id = enq.conta_id;

  t := p_corpo;
  t := replace(t, '{{nome}}',         pac.nome);
  t := replace(t, '{{profissional}}', coalesce(nullif(trim(prof.assina_como), ''), cont.nome));
  t := replace(t, '{{crp}}',          coalesce(nullif(trim(prof.crp), ''), '—'));
  t := replace(t, '{{horario}}',      public.rotulo_horario(enq.dia_semana, enq.hora));
  t := replace(t, '{{duracao}}',      enq.duracao_min::text || ' minutos');
  t := replace(t, '{{valor}}',        public.reais(enq.valor));
  t := replace(t, '{{politica}}',     public.rotulo_politica(enq.politica_horas, enq.politica_percentual));
  t := replace(t, '{{cidade}}',       coalesce(nullif(trim(cont.cidade), ''), '—'));
  t := replace(t, '{{data}}',         to_char(public.hoje_sp(), 'DD/MM/YYYY'));

  return t;
end;
$$;

-- ---------------------------------------------------------------- publicar

/**
 * Publica a próxima versão do contrato da conta.
 *
 * Recusa corpo sem `{{politica}}` e sem `{{valor}}`. Isto não é validação de
 * formulário: é o portão ético da fase 2 do doc 07 escrito como código. A regra
 * pela qual se cobra tem de estar no papel que a pessoa aceitou — senão a
 * cobrança automática vira uma surpresa com aparência de acordo.
 */
create or replace function public.publicar_contrato(p_titulo text, p_corpo text)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  proxima integer;
  novo    uuid;
begin
  if public.papel_atual() is distinct from 'dona' then
    raise exception 'só a dona da conta publica o contrato';
  end if;

  if position('{{politica}}' in p_corpo) = 0 then
    raise exception 'o texto precisa conter {{politica}}: a regra de falta tem de estar visível a quem aceita';
  end if;
  if position('{{valor}}' in p_corpo) = 0 then
    raise exception 'o texto precisa conter {{valor}}: o combinado de dinheiro tem de estar visível a quem aceita';
  end if;

  select coalesce(max(c.versao), 0) + 1 into proxima
    from public.contratos c
   where c.conta_id = public.conta_atual();

  insert into public.contratos (versao, titulo, corpo, publicado_em)
  values (proxima, p_titulo, p_corpo, now())
  returning id into novo;

  return novo;
end;
$$;

-- ------------------------------------------------------------------ preparar

/**
 * Prepara (ou renova) o aceite do combinado vigente e devolve o token.
 *
 * Renovar em vez de recusar é deliberado: o caso comum é ela reenviar o link
 * porque a pessoa perdeu a mensagem, e um erro aqui empurraria a psicóloga para
 * o WhatsApp — que é de onde o produto está tentando tirá-la.
 */
create or replace function public.preparar_aceite(p_enquadre uuid)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  atual  record;
  ctr    record;
  achou  boolean;
  saida  text;
begin
  select a.* into atual
    from public.aceites a
   where a.enquadre_id = p_enquadre and a.revogado_em is null;
  achou := found;

  if achou and atual.aceito_em is not null then
    raise exception 'este combinado já tem aceite: revogue antes de preparar outro';
  end if;

  if achou then
    select ct.* into ctr
      from public.contratos ct
     where ct.conta_id = atual.conta_id and ct.publicado_em is not null
     order by ct.versao desc
     limit 1;
    if not found then raise exception 'esta conta ainda não publicou um contrato'; end if;

    update public.aceites
       set contrato_id = ctr.id,
           texto       = public.montar_contrato(ctr.corpo, p_enquadre),
           token       = replace(gen_random_uuid()::text, '-', ''),
           expira_em   = now() + interval '90 days'
     where id = atual.id
    returning token into saida;

    return saida;
  end if;

  -- Os valores abaixo são descartáveis: o gatilho `aceite_monta` recalcula
  -- todos antes de a linha existir. Estão aqui só porque as colunas são NOT
  -- NULL — e é o gatilho, não este INSERT, que decide o que fica gravado.
  insert into public.aceites (enquadre_id, conta_id, paciente_id, contrato_id,
                              token, texto, retrato, expira_em)
  values (p_enquadre, p_enquadre, p_enquadre, p_enquadre,
          'placeholder', 'placeholder', '{}'::jsonb, now())
  returning token into saida;

  return saida;
end;
$$;

-- -------------------------------------------------------- o lado do visitante

/**
 * O que o link mostra. `security definer` porque quem chega não tem sessão.
 *
 * Devolve o mínimo: título, texto, primeiro nome e estado. Nada de telefone,
 * CPF, valor separado nem qualquer outro paciente. Um token vazado não pode
 * virar uma janela para a conta — o token é a chave de uma porta só, e a porta
 * dá para um cômodo com uma coisa dentro.
 */
create or replace function public.contrato_por_token(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  a record;
begin
  if p_token !~ '^[0-9a-f]{32}$' then
    return jsonb_build_object('estado', 'inexistente');
  end if;

  select * into a from public.aceites where token = p_token;
  if not found then
    return jsonb_build_object('estado', 'inexistente');
  end if;

  return jsonb_build_object(
    'estado', case
                when a.revogado_em is not null then 'revogado'
                when a.aceito_em   is not null then 'aceito'
                when now() > a.expira_em       then 'expirado'
                else 'pendente'
              end,
    'titulo',    a.retrato ->> 'contrato_titulo',
    'versao',    a.retrato ->> 'contrato_versao',
    'texto',     a.texto,
    -- Só o primeiro nome, como nas mensagens: a tela é lida por quem passa.
    'nome',      split_part(coalesce(a.retrato ->> 'paciente', ''), ' ', 1),
    'aceito_em', a.aceito_em,
    'aceito_por', a.aceito_por
  );
end;
$$;

/**
 * O aceite pelo link.
 *
 * A hora e a procedência não vêm daqui — vêm do gatilho, que não confia nem
 * nesta função. `ip` e `agente` são qualidade de prova e valem o que valem.
 */
create or replace function public.aceitar_contrato(
  p_token text,
  p_nome text,
  p_parentesco text default null,
  p_ip text default null,
  p_agente text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  a record;
begin
  if p_token !~ '^[0-9a-f]{32}$' then
    return jsonb_build_object('ok', false, 'motivo', 'inexistente');
  end if;

  select * into a from public.aceites where token = p_token for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'inexistente');
  end if;

  if a.revogado_em is not null then
    return jsonb_build_object('ok', false, 'motivo', 'revogado');
  end if;
  if a.aceito_em is not null then
    return jsonb_build_object('ok', true, 'motivo', 'ja_aceito', 'aceito_em', a.aceito_em);
  end if;
  if now() > a.expira_em then
    return jsonb_build_object('ok', false, 'motivo', 'expirado');
  end if;
  if p_nome is null or length(trim(p_nome)) < 2 then
    return jsonb_build_object('ok', false, 'motivo', 'sem_nome');
  end if;

  update public.aceites
     set aceito_em  = now(),
         aceito_por = trim(p_nome),
         parentesco = nullif(trim(coalesce(p_parentesco, '')), ''),
         ip         = case when p_ip ~ '^[0-9a-fA-F:.]+$' then p_ip::inet else null end,
         agente     = left(coalesce(p_agente, ''), 300)
   where id = a.id;

  insert into public.trilha_acesso (conta_id, paciente_id, acao, detalhe)
  values (a.conta_id, a.paciente_id, 'contrato_aceito',
          jsonb_build_object('aceite_id', a.id, 'origem', 'link'));

  return jsonb_build_object('ok', true, 'motivo', 'aceito');
end;
$$;

-- --------------------------------------------------------- o lado da psicóloga

/** Ela registra que a pessoa assinou na sala. O gatilho rotula como presencial. */
create or replace function public.registrar_aceite_presencial(
  p_enquadre uuid,
  p_quem text,
  p_parentesco text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  a record;
begin
  select * into a
    from public.aceites
   where enquadre_id = p_enquadre and revogado_em is null;

  if not found then raise exception 'prepare o combinado por escrito antes'; end if;
  if a.aceito_em is not null then raise exception 'este combinado já tem aceite'; end if;

  update public.aceites
     set aceito_em  = now(),
         aceito_por = trim(p_quem),
         parentesco = nullif(trim(coalesce(p_parentesco, '')), '')
   where id = a.id;

  perform public.registrar_acesso(a.paciente_id, 'contrato_aceito',
    jsonb_build_object('aceite_id', a.id, 'origem', 'presencial'));
end;
$$;

/** Revogar encerra a validade e preserva a linha. */
create or replace function public.revogar_aceite(p_id uuid, p_motivo text default null)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  a record;
begin
  select * into a from public.aceites where id = p_id;
  if not found then raise exception 'aceite não encontrado'; end if;
  if a.revogado_em is not null then return; end if;

  update public.aceites
     set revogado_em = now(),
         motivo_revogacao = nullif(trim(coalesce(p_motivo, '')), '')
   where id = p_id;

  perform public.registrar_acesso(a.paciente_id, 'contrato_revogado',
    jsonb_build_object('aceite_id', p_id));
end;
$$;

-- ------------------------------------------------------------------- trilha

-- Duas ações novas, e uma folga para o único caso em que quem grava não tem
-- conta na sessão: o visitante que aceita pelo link. Ninguém mais chega aqui
-- sem sessão — `anon` não tem grant nem policy de insert na trilha.
alter table public.trilha_acesso drop constraint if exists trilha_acesso_acao_check;
alter table public.trilha_acesso add constraint trilha_acesso_acao_check
  check (acao in (
    'leu_ficha', 'editou_ficha', 'exportou_paciente',
    'exportou_conta', 'esqueceu_contato', 'arquivou',
    'contrato_enviado', 'contrato_aceito', 'contrato_revogado'
  ));

create or replace function public.trilha_carimba()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.conta_id := coalesce(public.conta_atual(), new.conta_id);
  new.auth_user_id := (select auth.uid());
  new.em := now();

  if new.conta_id is null then
    raise exception 'trilha sem conta: só quem está numa conta registra acesso';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------- RLS

alter table public.contratos enable row level security;
alter table public.aceites   enable row level security;

drop policy if exists "contratos da conta: ler" on public.contratos;
create policy "contratos da conta: ler" on public.contratos
  for select to authenticated using (conta_id = public.conta_atual());

drop policy if exists "contratos da conta: escrever" on public.contratos;
create policy "contratos da conta: escrever" on public.contratos
  for insert to authenticated with check (conta_id = public.conta_atual());

drop policy if exists "contratos da conta: editar" on public.contratos;
create policy "contratos da conta: editar" on public.contratos
  for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

drop policy if exists "aceites da conta: ler" on public.aceites;
create policy "aceites da conta: ler" on public.aceites
  for select to authenticated using (conta_id = public.conta_atual());

drop policy if exists "aceites da conta: escrever" on public.aceites;
create policy "aceites da conta: escrever" on public.aceites
  for insert to authenticated with check (conta_id = public.conta_atual());

drop policy if exists "aceites da conta: editar" on public.aceites;
create policy "aceites da conta: editar" on public.aceites
  for update to authenticated
  using (conta_id = public.conta_atual())
  with check (conta_id = public.conta_atual());

-- Nenhuma policy de delete, nos dois. Contrato e aceite são registro: some com
-- a conta, nunca por clique.

-- ----------------------------------------------------------------- permissões
--
-- Os três, sempre: `public`, `anon` e `authenticated`. `create function` dá
-- EXECUTE a PUBLIC por padrão, e revogar só de `anon, authenticated` deixa a
-- porta aberta — foi o erro das migrações 0018 e 0027, nesta ordem.

revoke execute on function public.montar_contrato(text, uuid) from public, anon;
revoke execute on function public.aceite_monta()   from public, anon, authenticated;
revoke execute on function public.aceite_congela() from public, anon, authenticated;
revoke execute on function public.contrato_nao_muda() from public, anon, authenticated;
revoke execute on function public.contrato_carimba()  from public, anon, authenticated;

revoke execute on function public.publicar_contrato(text, text) from public, anon;
revoke execute on function public.preparar_aceite(uuid) from public, anon;
revoke execute on function public.registrar_aceite_presencial(uuid, text, text) from public, anon;
revoke execute on function public.revogar_aceite(uuid, text) from public, anon;

grant execute on function public.montar_contrato(text, uuid) to authenticated;
grant execute on function public.publicar_contrato(text, text) to authenticated;
grant execute on function public.preparar_aceite(uuid) to authenticated;
grant execute on function public.registrar_aceite_presencial(uuid, text, text) to authenticated;
grant execute on function public.revogar_aceite(uuid, text) to authenticated;

-- As duas do visitante. São `security definer`, então o que elas devolvem é
-- toda a superfície que `anon` tem — e o que devolvem está fechado acima.
grant execute on function public.contrato_por_token(text) to anon, authenticated;
grant execute on function public.aceitar_contrato(text, text, text, text, text) to anon, authenticated;

comment on table public.contratos is
  'Modelo do contrato, versionado por conta. Publicado e imutavel; editar abre a versao seguinte.';
comment on table public.aceites is
  'Aceite datado do combinado vigente. Um vivo por enquadre; congela no aceite; revogar preserva a linha.';
comment on function public.publicar_contrato(text, text) is
  'Recusa corpo sem {{politica}} e {{valor}}: portao etico da fase 2 (doc 07) como codigo.';
